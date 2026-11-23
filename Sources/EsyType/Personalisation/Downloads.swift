import AppKit
import Foundation

/// Exports go to the Downloads folder (as on Windows), never overwriting: "Name 2.csv" if "Name.csv" exists.
@MainActor
enum Downloads {
    static func save(_ data: Data, name: String, extension ext: String) -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let stamp = Date().formatted(.iso8601.year().month().day())
        var url = folder.appending(path: "\(name) \(stamp).\(ext)")
        var copy = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(name) \(stamp) \(copy).\(ext)")
            copy += 1
        }
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }

    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
