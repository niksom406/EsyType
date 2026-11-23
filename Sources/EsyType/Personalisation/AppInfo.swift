import AppKit

/// An app's name and icon from its bundle identifier (never its windows or contents).
@MainActor
enum AppInfo {
    private static var icons: [String: NSImage] = [:]

    static func name(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    /// Installed name, else a known name for the apps EsyType suggests, else the identifier.
    static func displayName(_ bundleID: String) -> String { name(bundleID) ?? known[bundleID] ?? bundleID }

    private static let known = [
        "com.microsoft.Outlook": "Outlook", "com.microsoft.Word": "Word", "com.apple.iWork.Pages": "Pages",
        "com.tinyspeck.slackmacgap": "Slack", "com.microsoft.teams2": "Microsoft Teams", "net.whatsapp.WhatsApp": "WhatsApp",
        "com.hnc.Discord": "Discord", "ru.keepcoder.Telegram": "Telegram", "com.apple.MobileSMS": "Messages", "com.apple.mail": "Mail",
    ]

    static func icon(_ bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = image
        return image
    }
}
