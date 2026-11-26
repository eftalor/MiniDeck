import AppKit

/// The standard About window, with the version and a link to the project.
enum About {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static func show() {
        let credits = NSMutableAttributedString(
            string: "A tiny, playlist-focused mini player\nfor Apple Music.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(
            string: "github.com/eftalor/MiniDeck",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .link: URL(string: "https://github.com/eftalor/MiniDeck")!]))
        let centered = NSMutableParagraphStyle(); centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        // The player is a non-activating panel, so bring MiniDeck forward for the About window.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "Version \(version)",
            .version: "",               // hide the "(build)" part; it's the same number
            .credits: credits,
        ])
    }

    /// Menu items need an object target; this one forwards to `show()`.
    final class Target: NSObject { @objc func show() { About.show() } }
    static let target = Target()
}
