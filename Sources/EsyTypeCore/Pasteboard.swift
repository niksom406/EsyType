import AppKit
import Carbon.HIToolbox

/// Every item and type on a pasteboard, so it can be put back after EsyType borrows it to paste.
public struct PasteboardSnapshot {
    let items: [[(NSPasteboard.PasteboardType, Data)]]

    public init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }
}

public enum Clipboard {
    /// Clipboard managers skip these (nspasteboard.org), so dictations don't pile up in their history.
    static let privateTypes = [NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
                               NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")]

    /// Writes `text` and returns the pasteboard's change count afterwards.
    @discardableResult
    public static func write(_ text: String, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.declareTypes([.string] + privateTypes, owner: nil)
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// The key that types "v" with ⌘ held in the current keyboard layout (Dvorak, AZERTY…). Layouts with no
    /// such key, like Devanagari, use the ANSI V position, which is what macOS matches ⌘V against there.
    public static func pasteKeyCode() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return CGKeyCode(kVK_ANSI_V)
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            for code in 0..<CGKeyCode(128) {
                var deadKeys: UInt32 = 0, length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), UInt32((cmdKey >> 8) & 0xFF),
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                if status == noErr, length == 1, chars[0] == UniChar(UInt8(ascii: "v")) { return code }
            }
            return CGKeyCode(kVK_ANSI_V)
        }
    }
}
