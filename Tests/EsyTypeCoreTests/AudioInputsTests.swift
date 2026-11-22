import EsyTypeCore
import Testing

/// Real device: reads this Mac's Core Audio devices.
@Test func listsThisMacsMicrophones() throws {
    let inputs = AudioInputs.all()
    #expect(!inputs.isEmpty)
    #expect(Set(inputs.map(\.uid)).count == inputs.count, "UIDs must be unique")
    let defaultID = try #require(AudioInputs.defaultID)
    #expect(inputs.contains { $0.id == defaultID }, "the default input is in the list")
    #expect(inputs.allSatisfy { !$0.name.isEmpty })
}

/// Simulated: the choice logic with a made-up device list.
@Test func resolvesTheChosenMicrophoneOrFallsBack() {
    let builtIn = AudioInput(id: 1, uid: "BuiltIn", name: "MacBook Air Microphone")
    let usb = AudioInput(id: 2, uid: "USB-123", name: "USB Mic")
    #expect(AudioInputs.resolve(uid: "", in: [builtIn, usb]) == nil) // system default
    #expect(AudioInputs.resolve(uid: "USB-123", in: [builtIn, usb]) == usb)
    #expect(AudioInputs.resolve(uid: "USB-123", in: [builtIn]) == nil) // unplugged: fall back to the default
}
