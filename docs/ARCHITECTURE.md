# Architecture

Invariants the code must keep. `WakeMenuModel` reconciles live inputs into
`WakePolicy`, which alone decides whether `CaffeinateController` holds.

## Detection

- Evaluate Codex, Claude, and Cursor desktop and CLI surfaces independently.
- Never read process arguments or user content. Codex Desktop remote sessions
  are found from the orphaned launch shell, app-server tree, and code-mode
  worker; their CPU progress sums the app-server root and worker subtrees.
- Headless CLI processes count as active for their lifetime.
- Interactive CLI and desktop processes count while their own CPU counters
  move; activity expires after 30 quiet minutes.
- Claude Desktop may also count while its local agent descendant lives.
- Process identity is PID plus start time, so a reused PID never inherits a
  session.
- A failed snapshot keeps evidence for enabled surfaces only and never causes
  an idle transition.

## Wake policy

- Manual and automatic demand form a union.
- Manual holds last 30 minutes, one hour, or eight hours.
- The battery cutoff releases demand, and fails safe when charge is unknown on
  battery power.
- Timers use monotonic time; wall-clock changes never extend or shorten them.

## Child process

- At most one `/usr/bin/caffeinate` child: `-ims -w <app-pid>`, or
  `-dims -w <app-pid>` when display sleep is off.
- A flag change replaces the child through the same reconciliation path.
- Requested and unexpected exits stay distinct, so the menu can recover or
  report an error.

## Persistence

- `UserDefaults` holds detector toggles, display-sleep choice, battery cutoff,
  and the last seen Start at Login state.
- Service Management stays authoritative for the login item.
- Everything else is memory-only; relaunch starts a new session.
