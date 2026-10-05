#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n scripts/*.sh
[[ -x scripts/install.sh ]] || {
  echo "error: scripts/install.sh must be executable" >&2
  exit 1
}
install_help="$(scripts/install.sh --help)"
grep -Fq -- '--version VERSION' <<<"${install_help}"
grep -Fq -- '--install-dir DIRECTORY' <<<"${install_help}"
grep -Fq -- '--force' <<<"${install_help}"
grep -Fq 'https://raw.githubusercontent.com/uinaf/slopwake/main/scripts/install.sh' README.md
grep -Fq '| bash -s -- --help' README.md
awk '
  index($0, "chmod -R u+rwX,go+rX,go-w \"$staged_app\"") { normalized = NR }
  index($0, "codesign --verify --deep --strict --verbose=2 \"$staged_app\"") { signed = NR }
  index($0, "spctl --assess --type execute --verbose=2 \"$staged_app\"") { assessed = NR }
  index($0, "mv \"$staged_app\" \"$target_app\"") { replaced = NR }
  END {
    if (normalized > 0 && signed > normalized && assessed > signed && replaced > assessed) exit 0
    print "installer must normalize, revalidate, and replace the staged app in order" > "/dev/stderr"
    exit 1
  }
' scripts/install.sh
ruby -rjson -e '
  JSON.parse(File.read("renovate.json"))
  config = JSON.parse(File.read(".releaserc.json"))
  plugins = config.fetch("plugins").flatten
  abort "expected @jno21/semantic-release-github-commit" unless plugins.include?("@jno21/semantic-release-github-commit")
  abort "unsigned @semantic-release/git writeback" if plugins.include?("@semantic-release/git")
'
ruby -ryaml -rstrscan - <<'RUBY'
# Evaluates the GitHub expression subset the workflow's concurrency and step
# conditions use, so the contract holds for any equivalent spelling.
def evaluate(source, context)
  scanner = StringScanner.new(source)
  tokens = []
  until (scanner.skip(/\s*/) && scanner.eos?)
    token = scanner.scan(/==|!=|&&|\|\||[!()]|'(?:[^']|'')*'|[A-Za-z_][\w.-]*/)
    abort "unsupported expression: #{source}" unless token
    tokens << token
  end
  value = either(tokens, context, source)
  abort "unsupported expression: #{source}" unless tokens.empty?
  value
end

def truthy?(value)
  ![nil, false, "", 0].include?(value)
end

def either(tokens, context, source)
  value = both(tokens, context, source)
  while tokens.first == "||"
    tokens.shift
    right = both(tokens, context, source)
    value = right unless truthy?(value)
  end
  value
end

def both(tokens, context, source)
  value = equality(tokens, context, source)
  while tokens.first == "&&"
    tokens.shift
    right = equality(tokens, context, source)
    value = right if truthy?(value)
  end
  value
end

def equality(tokens, context, source)
  value = operand(tokens, context, source)
  while ["==", "!="].include?(tokens.first)
    operator = tokens.shift
    right = operand(tokens, context, source)
    same = value.is_a?(String) && right.is_a?(String) ? value.casecmp?(right) : value == right
    value = operator == "==" ? same : !same
  end
  value
end

def operand(tokens, context, source)
  token = tokens.shift
  case token
  when "!" then !truthy?(operand(tokens, context, source))
  when "("
    value = either(tokens, context, source)
    abort "unsupported expression: #{source}" unless tokens.shift == ")"
    value
  when "true" then true
  when "false" then false
  when /\A'/ then token[1...-1].gsub("''", "'")
  else context.fetch(token) { abort "unsupported context #{token} in: #{source}" }
  end
end

def resolve(value, context)
  return value unless value.is_a?(String)
  whole = value.match(/\A\s*\$\{\{(.*)\}\}\s*\z/m)
  return evaluate(whole[1], context) if whole && !whole[1].include?("}}")
  value.gsub(/\$\{\{(.*?)\}\}/m) { evaluate(Regexp.last_match(1), context).to_s }
end

def condition(value, context)
  return true if value.nil?
  value = value.to_s
  truthy?(value.include?("${{") ? resolve(value, context) : evaluate(value, context))
end

def github(event, run_id, extra = {})
  {
    "github.workflow" => "CI",
    "github.repository" => "uinaf/slopwake",
    "github.event_name" => event,
    "github.ref" => event == "pull_request" ? "refs/pull/7/merge" : "refs/heads/main",
    "github.run_id" => run_id,
  }.merge(extra)
end

def concurrency(job, context)
  settings = job["concurrency"]
  settings = { "group" => settings } if settings.is_a?(String)
  abort "job is missing a concurrency group" unless settings.is_a?(Hash) && settings["group"]
  [resolve(settings["group"], context).to_s, truthy?(resolve(settings.fetch("cancel-in-progress", false), context))]
end

workflow = YAML.load_file(".github/workflows/ci.yml")
# YAML 1.1 reads a bare `on` key as true.
triggers = workflow.key?("on") ? workflow["on"] : workflow[true]
abort "CI must accept workflow_dispatch for release recovery" unless triggers.is_a?(Hash) && triggers.key?("workflow_dispatch")
jobs = workflow.fetch("jobs")

product = jobs.fetch("verify-product")
pull_requests = %w[1 2].map { |id| concurrency(product, github("pull_request", id)) }
unless pull_requests.map(&:first).uniq.size == 1 && pull_requests.all?(&:last)
  abort "verify-product must cancel superseded runs of the same pull request"
end
%w[push workflow_dispatch].each do |event|
  runs = %w[3 4].map { |id| concurrency(product, github(event, id)) }
  if runs[0][0] == runs[1][0] || runs.any?(&:last)
    abort "verify-product must give every #{event} run its own group and never cancel it"
  end
end
product_steps = product.fetch("steps")
abort "verify-product must fingerprint the Xcode toolchain" unless product_steps.any? { |step| step["id"] == "xcode-toolchain" }
caches = product_steps.select { |step| step["uses"].to_s.start_with?("actions/cache@") }
cache_paths = lambda do |prefix|
  step = caches.find { |cache| cache.dig("with", "key").to_s.start_with?(prefix) }
  abort "verify-product must restore a #{prefix} cache" unless step
  step.dig("with", "path").to_s.split("\n").map(&:strip)
end
cache_paths.call("verify-swiftpm-v1-")
xcode_paths = cache_paths.call("verify-xcode-v1-")
missing = [".artifacts/xcodegen", "Slopwake.xcodeproj", "DerivedData/Test", "DerivedData/Build"] - xcode_paths
abort "the Xcode cache must keep #{missing.join(', ')}" unless missing.empty?

release = jobs.fetch("release")
release_runs = [%w[push 5], %w[push 6], %w[workflow_dispatch 7]].map { |event, id| concurrency(release, github(event, id)) }
unless release_runs.map(&:first).uniq.size == 1 && release_runs.none?(&:last)
  abort "release must queue every run in one non-cancelling group"
end
release_steps = release.fetch("steps")
semantic_release = release_steps.find { |step| step["uses"].to_s.start_with?("cycjimmy/semantic-release-action@") }
abort "release must cut versions with semantic-release" unless semantic_release
active = { "steps.gate.outputs.active" => "true", "steps.preflight.outputs.recovery" => "false" }
unless condition(semantic_release["if"], github("push", "8", active)) && !condition(semantic_release["if"], github("workflow_dispatch", "9", active))
  abort "release recovery dispatches must never cut a new version"
end
scripts = release_steps.map { |step| step["run"].to_s }.join("\n")
[
  %q{gh release view "${RELEASE_TAG}" --json databaseId,isDraft},
  %q{gh api "repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}"},
  %q{cp homebrew-tap/Casks/slopwake.rb "${tap_root}/Casks/slopwake.rb"},
  %q{brew style --cask uinaf/tap/slopwake},
  %q{brew audit --online --strict --cask uinaf/tap/slopwake},
].each { |command| abort "release must run: #{command}" unless scripts.include?(command) }
if scripts.include?(%q{echo "draft=false"})
  abort "release discovery must fail closed when an expected draft is not visible"
end
tap_commit = release_steps.find { |step| step["uses"].to_s.start_with?("pgaskin/push-signed-commits@") }
unless tap_commit && tap_commit.dig("with", "app-key").to_s.gsub(/\s+/, "") == "${{secrets.UINAF_CI_APP_PRIVATE_KEY}}"
  abort "the Homebrew tap commit must be signed with the uinaf-ci app key"
end
smoke = release_steps.find { |step| step["run"].to_s.include?("brew install --cask uinaf/tap/slopwake") }
abort "the Homebrew smoke must not auto-update Homebrew" unless smoke && smoke.dig("env", "HOMEBREW_NO_AUTO_UPDATE").to_s == "1"
RUBY
grep -Fq -- '--use-cache' scripts/generate-project.sh
grep -Fq -- '--cache-path "${cache_path}"' scripts/generate-project.sh
for package_flag in -disableAutomaticPackageResolution -skipPackageUpdates; do
  grep -Fq -- "${package_flag}" Makefile
done
grep -Fq '"${app}/Contents/MacOS/slopwake" &' scripts/smoke-installed-app.sh

version="$(sed -n '1p' VERSION)"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: VERSION must contain one stable semantic version" >&2
  exit 1
}
project_version="$(sed -n 's/^        MARKETING_VERSION: //p' project.yml)"
[[ "${project_version}" == "${version}" ]] || {
  echo "error: VERSION and project.yml MARKETING_VERSION differ" >&2
  exit 1
}

fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT
tap_root="${fixture_root}/tap"
archive="${fixture_root}/slopwake-1.2.3-macos-universal.zip"
mkdir -p "${tap_root}"
git -C "${tap_root}" init -q
printf 'slopwake release fixture\n' >"${archive}"
scripts/update-homebrew-cask.sh 1.2.3 "${archive}" "${tap_root}" >/dev/null
ruby -c "${tap_root}/Casks/slopwake.rb" >/dev/null
expected_checksum="$(shasum -a 256 "${archive}" | awk '{print $1}')"
grep -q "sha256 \"${expected_checksum}\"" "${tap_root}/Casks/slopwake.rb"

echo "release contract ok"
