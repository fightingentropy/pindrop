//
//  AppCoordinatorContextFlowTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import ApplicationServices
import XCTest

@testable import Pindrop

@MainActor
final class AppCoordinatorContextFlowTests: XCTestCase {

    var contextEngine: ContextEngineService!
    var mockAXProvider: MockAXProvider!
    var fakeAppElement: AXUIElement!
    var fakeFocusedWindow: AXUIElement!
    var fakeFocusedElement: AXUIElement!

    override func setUp() async throws {
        mockAXProvider = MockAXProvider()
        fakeAppElement = AXUIElementCreateApplication(88880)
        fakeFocusedWindow = AXUIElementCreateApplication(88881)
        fakeFocusedElement = AXUIElementCreateApplication(88882)

        mockAXProvider.frontmostAppElement = fakeAppElement
        mockAXProvider.frontmostPID = 88880
        mockAXProvider.isTrusted = true

        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "Xcode")
        mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fakeAppElement, value: fakeFocusedWindow)
        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeFocusedWindow, value: "AppCoordinator.swift")
        mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fakeAppElement, value: fakeFocusedElement)
        mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fakeFocusedElement, value: "AXTextArea")
        mockAXProvider.setStringAttribute(kAXSelectedTextAttribute, of: fakeFocusedElement, value: "func startRecording()")

        contextEngine = ContextEngineService(axProvider: mockAXProvider)
    }

    override func tearDown() async throws {
        contextEngine = nil
        mockAXProvider = nil
        fakeAppElement = nil
        fakeFocusedWindow = nil
        fakeFocusedElement = nil
    }

    // MARK: - Tests

    func testEnhancementUsesContextEngineSnapshot() {
        let result = contextEngine.captureAppContext()

        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: result.appContext,
            clipboardText: nil,
            warnings: result.warnings
        )

        XCTAssertNotNil(snapshot.appContext, "Snapshot should contain app context when AX is trusted")
        XCTAssertTrue(snapshot.warnings.isEmpty, "No warnings expected for trusted AX capture")
        XCTAssertTrue(snapshot.hasAnyContext, "Snapshot should report having context")

        let ctx = snapshot.appContext!
        XCTAssertEqual(ctx.windowTitle, "AppCoordinator.swift")
        XCTAssertEqual(ctx.focusedElementRole, "AXTextArea")
        XCTAssertEqual(ctx.selectedText, "func startRecording()")
        XCTAssertTrue(ctx.hasDetailedContext, "Context with window title and selected text should be detailed")

        let legacy = snapshot.asCapturedContext
        XCTAssertNil(legacy.clipboardText, "Legacy bridge should have nil clipboard text when not captured")

        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: false))
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: true))
        XCTAssertFalse(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: false))

        let now = Date()
        XCTAssertTrue(
            AppCoordinator.isDoubleEscapePress(
                now: now,
                lastEscapeTime: now.addingTimeInterval(-0.2),
                threshold: 0.4
            )
        )
        XCTAssertFalse(
            AppCoordinator.isDoubleEscapePress(
                now: now,
                lastEscapeTime: now.addingTimeInterval(-0.6),
                threshold: 0.4
            )
        )
    }

    func testContextTimeoutFallsBackWithoutBlockingTranscription() {
        mockAXProvider.isTrusted = false

        let result = contextEngine.captureAppContext()

        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: result.appContext,
            clipboardText: "some clipboard text",
            warnings: result.warnings
        )

        XCTAssertTrue(
            snapshot.warnings.contains(.accessibilityPermissionDenied),
            "Should have accessibility permission denied warning"
        )
        XCTAssertTrue(snapshot.hasAnyContext, "Snapshot should still report context from clipboard")
        XCTAssertEqual(snapshot.clipboardText, "some clipboard text", "Clipboard text should be preserved")

        let legacy = snapshot.asCapturedContext
        XCTAssertEqual(legacy.clipboardText, "some clipboard text", "Legacy bridge should preserve clipboard text")
    }

    func testEscapeSuppressionOnlyWhenRecordingOrProcessing() {
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: false))
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: true))
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: true))
        XCTAssertFalse(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: false))
    }

    func testDoubleEscapeDetectionHonorsThreshold() {
        let now = Date()
        let withinThreshold = now.addingTimeInterval(-0.25)
        let outsideThreshold = now.addingTimeInterval(-0.6)

        XCTAssertTrue(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: withinThreshold, threshold: 0.4))
        XCTAssertFalse(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: outsideThreshold, threshold: 0.4))
        XCTAssertFalse(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: nil, threshold: 0.4))
    }

    func testNormalizedTranscriptionTextTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(AppCoordinator.normalizedTranscriptionText("  hello world \n"), "hello world")
        XCTAssertEqual(AppCoordinator.normalizedTranscriptionText("\n\t  "), "")
    }

    func testIsTranscriptionEffectivelyEmptyTreatsBlankAudioPlaceholderAsEmpty() {
        XCTAssertTrue(AppCoordinator.isTranscriptionEffectivelyEmpty(""))
        XCTAssertTrue(AppCoordinator.isTranscriptionEffectivelyEmpty("   \n\t"))
        XCTAssertTrue(AppCoordinator.isTranscriptionEffectivelyEmpty("[BLANK AUDIO]"))
        XCTAssertTrue(AppCoordinator.isTranscriptionEffectivelyEmpty("  [blank audio]  "))

        XCTAssertFalse(AppCoordinator.isTranscriptionEffectivelyEmpty("[BLANK AUDIO] detected speech"))
        XCTAssertFalse(AppCoordinator.isTranscriptionEffectivelyEmpty("transcribed text"))
    }

    func testShouldPersistHistoryRequiresSuccessfulOutputAndNonEmptyText() {
        XCTAssertTrue(AppCoordinator.shouldPersistHistory(outputSucceeded: true, text: "transcribed text"))

        XCTAssertFalse(AppCoordinator.shouldPersistHistory(outputSucceeded: false, text: "transcribed text"))
        XCTAssertFalse(AppCoordinator.shouldPersistHistory(outputSucceeded: true, text: "   "))
        XCTAssertFalse(AppCoordinator.shouldPersistHistory(outputSucceeded: true, text: "[BLANK AUDIO]"))
    }

    func testShouldShowIdlePillIndicatorRequiresEnabledPillStyleIdleVisibilityAndNoTemporaryHide() {
        XCTAssertTrue(
            AppCoordinator.shouldShowIdlePillIndicator(
                floatingIndicatorEnabled: true,
                floatingIndicatorType: FloatingIndicatorType.pill.rawValue,
                floatingIndicatorShowsWhenIdle: true,
                isTemporarilyHidden: false
            )
        )

        XCTAssertFalse(
            AppCoordinator.shouldShowIdlePillIndicator(
                floatingIndicatorEnabled: true,
                floatingIndicatorType: FloatingIndicatorType.pill.rawValue,
                floatingIndicatorShowsWhenIdle: false,
                isTemporarilyHidden: false
            )
        )

        XCTAssertFalse(
            AppCoordinator.shouldShowIdlePillIndicator(
                floatingIndicatorEnabled: true,
                floatingIndicatorType: FloatingIndicatorType.notch.rawValue,
                floatingIndicatorShowsWhenIdle: true,
                isTemporarilyHidden: false
            )
        )

        XCTAssertFalse(
            AppCoordinator.shouldShowIdlePillIndicator(
                floatingIndicatorEnabled: true,
                floatingIndicatorType: FloatingIndicatorType.pill.rawValue,
                floatingIndicatorShowsWhenIdle: true,
                isTemporarilyHidden: true
            )
        )
    }

    func testShouldContinueDeferredRecordingStartRequiresHeldKeyForPushToTalkFlows() {
        XCTAssertTrue(
            AppCoordinator.shouldContinueDeferredRecordingStart(
                isPushToTalkSource: true,
                isQuickCapturePTTSource: false,
                isPushToTalkKeyHeld: true,
                isQuickCapturePTTKeyHeld: false
            )
        )

        XCTAssertFalse(
            AppCoordinator.shouldContinueDeferredRecordingStart(
                isPushToTalkSource: true,
                isQuickCapturePTTSource: false,
                isPushToTalkKeyHeld: false,
                isQuickCapturePTTKeyHeld: false
            )
        )

        XCTAssertTrue(
            AppCoordinator.shouldContinueDeferredRecordingStart(
                isPushToTalkSource: false,
                isQuickCapturePTTSource: true,
                isPushToTalkKeyHeld: false,
                isQuickCapturePTTKeyHeld: true
            )
        )

        XCTAssertFalse(
            AppCoordinator.shouldContinueDeferredRecordingStart(
                isPushToTalkSource: false,
                isQuickCapturePTTSource: true,
                isPushToTalkKeyHeld: false,
                isQuickCapturePTTKeyHeld: false
            )
        )

        XCTAssertTrue(
            AppCoordinator.shouldContinueDeferredRecordingStart(
                isPushToTalkSource: false,
                isQuickCapturePTTSource: false,
                isPushToTalkKeyHeld: false,
                isQuickCapturePTTKeyHeld: false
            )
        )
    }

    func testStatusBarDynamicRefreshPlanSkipsMenuRegenerationForUnrelatedSettingsChanges() {
        let previous = makeSettingsObservationSnapshot()
        let current = makeSettingsObservationSnapshot(enableUIContext: true)

        let plan = AppCoordinator.statusBarDynamicRefreshPlan(previous: previous, current: current)

        XCTAssertFalse(plan.updateSummaryItems)
        XCTAssertFalse(plan.refreshPromptPresetCheckmarks)
        XCTAssertFalse(plan.refreshModelMenuItems)
        XCTAssertFalse(plan.refreshAIModelMenuItems)
        XCTAssertFalse(plan.refreshInputDeviceMenu)
        XCTAssertFalse(plan.needsAnyUpdate)
    }

    func testStatusBarDynamicRefreshPlanRefreshesOnlyInputDevicesWhenMicrophoneChanges() {
        let previous = makeSettingsObservationSnapshot(selectedInputDeviceUID: "")
        let current = makeSettingsObservationSnapshot(selectedInputDeviceUID: "usb-mic")

        let plan = AppCoordinator.statusBarDynamicRefreshPlan(previous: previous, current: current)

        XCTAssertFalse(plan.updateSummaryItems)
        XCTAssertFalse(plan.refreshPromptPresetCheckmarks)
        XCTAssertFalse(plan.refreshModelMenuItems)
        XCTAssertFalse(plan.refreshAIModelMenuItems)
        XCTAssertTrue(plan.refreshInputDeviceMenu)
        XCTAssertTrue(plan.needsAnyUpdate)
    }

    func testStatusBarDynamicRefreshPlanRefreshesOnlyAffectedSubmenus() {
        let previous = makeSettingsObservationSnapshot()
        let current = makeSettingsObservationSnapshot(
            selectedPresetId: "preset-1",
            selectedModel: "openai_whisper-small",
            aiModel: "openai/gpt-4.1-mini"
        )

        let plan = AppCoordinator.statusBarDynamicRefreshPlan(previous: previous, current: current)

        XCTAssertTrue(plan.updateSummaryItems)
        XCTAssertTrue(plan.refreshPromptPresetCheckmarks)
        XCTAssertTrue(plan.refreshModelMenuItems)
        XCTAssertTrue(plan.refreshAIModelMenuItems)
        XCTAssertFalse(plan.refreshInputDeviceMenu)
        XCTAssertTrue(plan.needsAnyUpdate)
    }

    private func makeSettingsObservationSnapshot(
        outputMode: String = "clipboard",
        selectedInputDeviceUID: String = "",
        floatingIndicatorEnabled: Bool = true,
        floatingIndicatorType: String = FloatingIndicatorType.pill.rawValue,
        floatingIndicatorShowsWhenIdle: Bool = true,
        aiEnhancementEnabled: Bool = false,
        launchAtLogin: Bool = false,
        selectedPresetId: String? = nil,
        selectedModel: String = SettingsStore.Defaults.selectedModel,
        aiModel: String = SettingsStore.Defaults.aiModel,
        aiProvider: AIProvider = .openai,
        enableUIContext: Bool = false,
        vibeLiveSessionEnabled: Bool = true
    ) -> SettingsObservationSnapshot {
        SettingsObservationSnapshot(
            outputMode: outputMode,
            selectedInputDeviceUID: selectedInputDeviceUID,
            floatingIndicatorEnabled: floatingIndicatorEnabled,
            floatingIndicatorType: floatingIndicatorType,
            floatingIndicatorShowsWhenIdle: floatingIndicatorShowsWhenIdle,
            aiEnhancementEnabled: aiEnhancementEnabled,
            launchAtLogin: launchAtLogin,
            selectedPresetId: selectedPresetId,
            selectedModel: selectedModel,
            aiModel: aiModel,
            aiProvider: aiProvider,
            enableUIContext: enableUIContext,
            vibeLiveSessionEnabled: vibeLiveSessionEnabled,
            hotkeys: HotkeySettingsSnapshot(
                hasCompletedOnboarding: true,
                pushToTalk: HotkeyBindingSnapshot(hotkey: "⌘/", keyCode: 44, modifiers: 0x100),
                toggle: HotkeyBindingSnapshot(hotkey: "⌥Space", keyCode: 49, modifiers: 0x800),
                copyLastTranscript: HotkeyBindingSnapshot(hotkey: "⇧⌘C", keyCode: 8, modifiers: 0x300),
                quickCapturePTT: HotkeyBindingSnapshot(hotkey: "⇧⌥Space", keyCode: 49, modifiers: 0xA00),
                quickCaptureToggle: HotkeyBindingSnapshot(hotkey: "", keyCode: 0, modifiers: 0)
            )
        )
    }
}
