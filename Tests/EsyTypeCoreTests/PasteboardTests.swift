import AppKit
import Carbon.HIToolbox
import Testing
@testable import EsyTypeCore

@Test func snapshotRestoresEveryItemAndType() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("EsyTypeTests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let first = NSPasteboardItem(), second = NSPasteboardItem()
    first.setString("hello", forType: .string)
    first.setData(Data([1, 2, 3]), forType: .rtf)
    second.setString("https://example.com", forType: .URL)
    pasteboard.clearContents()
    pasteboard.writeObjects([first, second])

    let snapshot = PasteboardSnapshot(pasteboard)
    let count = Clipboard.write("dictated text", to: pasteboard)
    #expect(pasteboard.string(forType: .string) == "dictated text")
    #expect(pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true)
    #expect(pasteboard.changeCount == count)

    snapshot.restore(to: pasteboard)
    let items = pasteboard.pasteboardItems ?? []
    #expect(items.count == 2)
    #expect(items.first?.string(forType: .string) == "hello")
    #expect(items.first?.data(forType: .rtf) == Data([1, 2, 3]))
    #expect(items.last?.string(forType: .URL) == "https://example.com")
}

@Test func emptyClipboardStaysEmpty() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("EsyTypeTests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    let snapshot = PasteboardSnapshot(pasteboard)
    Clipboard.write("dictated text", to: pasteboard)
    snapshot.restore(to: pasteboard)
    #expect(pasteboard.string(forType: .string) == nil)
}

@Test func pasteKeyIsVOnThisMacsLayout() {
    // Real device: ABC/British/US layouts put V at the ANSI position; other layouts would differ by design.
    #expect(Clipboard.pasteKeyCode() == CGKeyCode(kVK_ANSI_V))
}
