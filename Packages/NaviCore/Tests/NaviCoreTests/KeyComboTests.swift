import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import NaviCore

struct KeyComboTests {
    private let commandShift = UInt32(cmdKey | shiftKey)
    private let v = UInt32(kVK_ANSI_V)

    @Test func displayOrdersModifiersAsMacOSDoes() {
        let all = KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(all.display == "⌃⌥⇧⌘A")
        #expect(KeyCombo.defaultHistory.display == "⇧⌘V")
    }

    @Test func displayNamesSpecialKeys() {
        #expect(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: UInt32(cmdKey)).display == "⌘F5")
        #expect(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)).display == "⌥Space")
        #expect(KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey)).display == "⌃←")
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_Slash), modifiers: UInt32(cmdKey)).display == "⌘/")
    }

    @Test func unknownKeyShowsItsCode() {
        #expect(KeyCombo(keyCode: 0xFFFF, modifiers: UInt32(cmdKey)).display == "⌘Key 65535")
    }

    @Test func cocoaFlagsMapToCarbonBits() {
        #expect(KeyCombo.from(keyCode: UInt16(kVK_ANSI_V), cocoaFlags: [.command, .shift]) == .defaultHistory)
        let controlOption = KeyCombo.from(keyCode: UInt16(kVK_ANSI_4), cocoaFlags: [.control, .option])
        #expect(controlOption.modifiers == UInt32(controlKey | optionKey))
        #expect(KeyCombo.from(keyCode: 0, cocoaFlags: [.capsLock, .function]).modifiers == 0)
    }

    @Test func carbonBitsMapToCocoaFlags() {
        let combo = KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey | optionKey))
        #expect(combo.cocoaModifiers == [.command, .option])
    }

    @Test func needsCommandOptionOrControl() {
        #expect(KeyCombo(keyCode: v, modifiers: 0).validate(reserved: [:]) == .needsModifier)
        #expect(KeyCombo(keyCode: v, modifiers: UInt32(shiftKey)).validate(reserved: [:]) == .shiftOnly)
        #expect(KeyCombo(keyCode: v, modifiers: UInt32(optionKey)).validate(reserved: [:]) == nil)
        #expect(KeyCombo(keyCode: v, modifiers: UInt32(controlKey)).validate(reserved: [:]) == nil)
    }

    @Test func comboUsedByAnotherActionIsInUse() {
        let reserved = ["Capture Area": KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: commandShift)]
        let clash = KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: commandShift)
        #expect(clash.validate(reserved: reserved) == .inUse("Capture Area"))
        #expect(KeyCombo.defaultHistory.validate(reserved: reserved) == nil)
    }
}

struct HistoryShortcutStoreTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "NaviTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func missingValueLoadsTheDefault() {
        withDefaults { defaults in
            #expect(HistoryShortcutStore(defaults: defaults).load() == .defaultHistory)
        }
    }

    @Test func savedComboRoundTrips() {
        withDefaults { defaults in
            let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | cmdKey))
            HistoryShortcutStore(defaults: defaults).save(combo)
            #expect(HistoryShortcutStore(defaults: defaults).load() == combo)
        }
    }

    @Test func corruptValueLoadsTheDefault() {
        withDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: HistoryShortcutStore.key)
            #expect(HistoryShortcutStore(defaults: defaults).load() == .defaultHistory)
        }
    }

    @Test func resetForgetsTheSavedCombo() {
        withDefaults { defaults in
            let store = HistoryShortcutStore(defaults: defaults)
            store.save(KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey)))
            store.reset()
            #expect(store.load() == .defaultHistory)
            #expect(defaults.object(forKey: HistoryShortcutStore.key) == nil)
        }
    }
}
