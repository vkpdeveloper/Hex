//
//  ModifierSideTests.swift
//  HexCoreTests
//
//  Covers left/right modifier-side hotkey matching:
//  1. `Modifiers.from(carbonFlags:)` device-bit decoding (left/right/either/fn)
//  2. Side-aware `matchesExactly` matching
//  3. End-to-end HotKeyProcessor scenarios for a right-side modifier-only hotkey
//     (the "double-tap RIGHT Control to lock recording" flow).
//

import CoreGraphics
import Dependencies
import Foundation
@testable import HexCore
import Sauce
import Testing

// MARK: - Decoding: Modifiers.from(carbonFlags:)

struct ModifierSideDecodingTests {
    /// Real CGEvents set BOTH the general mask bit and the device-dependent side bit.
    /// We mirror that here so the decoder sees the same shape it does in production.
    private func flags(_ deviceBit: UInt64, _ general: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: deviceBit | general.rawValue)
    }

    @Test
    func rightControlBit_decodesToControlRight() {
        let decoded = Modifiers.from(carbonFlags: flags(0x2000, .maskControl))
        #expect(decoded == [Modifier(kind: .control, side: .right)])
    }

    @Test
    func leftControlBit_decodesToControlLeft() {
        let decoded = Modifiers.from(carbonFlags: flags(0x0001, .maskControl))
        #expect(decoded == [Modifier(kind: .control, side: .left)])
    }

    @Test
    func generalControlMaskOnly_decodesToEither() {
        // No device-specific side bit set -> falls back to .either
        let decoded = Modifiers.from(carbonFlags: .maskControl)
        #expect(decoded == [Modifier(kind: .control, side: .either)])
    }

    @Test
    func rightOptionBit_decodesToOptionRight() {
        let decoded = Modifiers.from(carbonFlags: flags(0x0040, .maskAlternate))
        #expect(decoded == [Modifier(kind: .option, side: .right)])
    }

    @Test
    func leftOptionBit_decodesToOptionLeft() {
        let decoded = Modifiers.from(carbonFlags: flags(0x0020, .maskAlternate))
        #expect(decoded == [Modifier(kind: .option, side: .left)])
    }

    @Test
    func rightCommandBit_decodesToCommandRight() {
        let decoded = Modifiers.from(carbonFlags: flags(0x0010, .maskCommand))
        #expect(decoded == [Modifier(kind: .command, side: .right)])
    }

    @Test
    func leftCommandBit_decodesToCommandLeft() {
        let decoded = Modifiers.from(carbonFlags: flags(0x0008, .maskCommand))
        #expect(decoded == [Modifier(kind: .command, side: .left)])
    }

    @Test
    func rightShiftBit_decodesToShiftRight() {
        let decoded = Modifiers.from(carbonFlags: flags(0x0004, .maskShift))
        #expect(decoded == [Modifier(kind: .shift, side: .right)])
    }

    @Test
    func leftShiftBit_decodesToShiftLeft() {
        let decoded = Modifiers.from(carbonFlags: flags(0x0002, .maskShift))
        #expect(decoded == [Modifier(kind: .shift, side: .left)])
    }

    @Test
    func secondaryFnMask_decodesToFn() {
        let decoded = Modifiers.from(carbonFlags: .maskSecondaryFn)
        #expect(decoded == [.fn])
    }
}

// MARK: - Side-aware matchesExactly

struct ModifierSideMatchingTests {
    @Test
    func rightControlHotkey_matchesRightControlEvent() {
        let hotkey: Modifiers = [Modifier(kind: .control, side: .right)]
        let event: Modifiers = [Modifier(kind: .control, side: .right)]
        #expect(event.matchesExactly(hotkey))
    }

    @Test
    func rightControlHotkey_doesNotMatchLeftControlEvent() {
        let hotkey: Modifiers = [Modifier(kind: .control, side: .right)]
        let event: Modifiers = [Modifier(kind: .control, side: .left)]
        #expect(!event.matchesExactly(hotkey))
    }

    @Test
    func eitherControlHotkey_matchesBothSides() {
        let hotkey: Modifiers = [Modifier(kind: .control, side: .either)]
        let leftEvent: Modifiers = [Modifier(kind: .control, side: .left)]
        let rightEvent: Modifiers = [Modifier(kind: .control, side: .right)]
        #expect(leftEvent.matchesExactly(hotkey))
        #expect(rightEvent.matchesExactly(hotkey))
    }

    @Test
    func rightControlHotkey_matchesEitherControlEvent() {
        // Symmetry: an .either event should satisfy a right-only requirement,
        // matching the `Modifier.matches` "either wildcard" semantics.
        let hotkey: Modifiers = [Modifier(kind: .control, side: .right)]
        let event: Modifiers = [Modifier(kind: .control, side: .either)]
        #expect(event.matchesExactly(hotkey))
    }
}

// MARK: - End-to-end processor scenarios (right-side modifier-only hotkey)

struct ModifierSideProcessorTests {
    private static let rightControl = HotKey(
        key: nil,
        modifiers: [Modifier(kind: .control, side: .right)]
    )

    private static let rightCtrlMods: Modifiers = [Modifier(kind: .control, side: .right)]
    private static let leftCtrlMods: Modifiers = [Modifier(kind: .control, side: .left)]

    /// The user's core flow: double-tap RIGHT Control to lock recording, single tap to stop.
    @Test
    func rightControl_doubleTapLocksAndSingleTapStops() throws {
        runScenario(
            hotkey: Self.rightControl,
            doubleTapLockEnabled: true,
            steps: [
                // First tap: press right-ctrl -> start recording
                ScenarioStep(time: 0.0, key: nil, modifiers: Self.rightCtrlMods, expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap within 0.3s threshold -> start recording again
                ScenarioStep(time: 0.2, key: nil, modifiers: Self.rightCtrlMods, expectedOutput: .startRecording, expectedIsMatched: true),
                // Second release -> lock engages, still matched
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                // Later single press -> stops the locked recording
                ScenarioStep(time: 1.0, key: nil, modifiers: Self.rightCtrlMods, expectedOutput: .stopRecording, expectedIsMatched: false, expectedState: .idle),
            ]
        )
    }

    /// A LEFT Control press must do nothing when the hotkey is right-side only.
    @Test
    func leftControl_doesNothingForRightSideHotkey() throws {
        runScenario(
            hotkey: Self.rightControl,
            doubleTapLockEnabled: true,
            steps: [
                // Wrong side: no recording should start
                ScenarioStep(time: 0.0, key: nil, modifiers: Self.leftCtrlMods, expectedOutput: nil, expectedIsMatched: false, expectedState: .idle),
                // Release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false, expectedState: .idle),
            ]
        )
    }

    /// Regression: while locked via double-tap of RIGHT Control, a LEFT Control press
    /// must NOT stop recording. Only the correct (right) side stops it.
    @Test
    func leftControl_doesNotStopRightControlDoubleTapLock() throws {
        runScenario(
            hotkey: Self.rightControl,
            doubleTapLockEnabled: true,
            steps: [
                // Enter double-tap lock with right-ctrl
                ScenarioStep(time: 0.0, key: nil, modifiers: Self.rightCtrlMods, expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: Self.rightCtrlMods, expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                // Wrong-side (left) control press must not stop recording
                ScenarioStep(time: 1.0, key: nil, modifiers: Self.leftCtrlMods, expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                // Full release clears the "dirty" state the wrong-side press introduced, still recording
                ScenarioStep(time: 1.1, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                // Correct (right) side press finally stops it
                ScenarioStep(time: 1.2, key: nil, modifiers: Self.rightCtrlMods, expectedOutput: .stopRecording, expectedIsMatched: false, expectedState: .idle),
            ]
        )
    }
}
