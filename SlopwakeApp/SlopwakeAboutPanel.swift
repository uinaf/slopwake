import AppKit

@MainActor
enum SlopwakeAboutPanel {
    static let repositoryURLString = "https://github.com/uinaf/slopwake"

    static var credits: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
        let credits = NSMutableAttributedString(
            string: "Keep your slopshop awake.\n\nA native macOS menu-bar app by uinaf.\n\n",
            attributes: textAttributes
        )

        if let repositoryURL = URL(string: repositoryURLString) {
            var linkAttributes = textAttributes
            linkAttributes[.foregroundColor] = NSColor.linkColor
            linkAttributes[.link] = repositoryURL
            credits.append(
                NSAttributedString(
                    string: "View on GitHub",
                    attributes: linkAttributes
                )
            )
        }

        return credits
    }

    static func present() {
        let application = NSApplication.shared
        application.activate()
        application.orderFrontStandardAboutPanel(options: [
            .credits: credits,
        ])
    }
}
