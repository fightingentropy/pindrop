//
//  NoteEditorViewTests.swift
//  PindropTests
//
//  Created on 2026-03-07.
//

import XCTest

@testable import Pindrop

@MainActor
final class NoteEditorViewTests: XCTestCase {

    func testShouldScheduleAutosaveRequiresPersistedNoteAndChangedDraft() {
        let draft = NoteEditorView.Draft(
            title: "Title",
            content: "Body",
            isPinned: false,
            tags: ["work"]
        )

        XCTAssertFalse(
            NoteEditorView.shouldScheduleAutosave(
                hasPersistedNote: false,
                lastPersistedDraft: nil,
                draft: draft
            )
        )

        XCTAssertFalse(
            NoteEditorView.shouldScheduleAutosave(
                hasPersistedNote: true,
                lastPersistedDraft: draft,
                draft: draft
            )
        )

        XCTAssertTrue(
            NoteEditorView.shouldScheduleAutosave(
                hasPersistedNote: true,
                lastPersistedDraft: nil,
                draft: draft
            )
        )
    }

    func testShouldPersistDraftOnlyWhenNeeded() {
        let persistedDraft = NoteEditorView.Draft(
            title: "Title",
            content: "Body",
            isPinned: false,
            tags: ["work"]
        )
        let updatedDraft = NoteEditorView.Draft(
            title: "Updated",
            content: "Body",
            isPinned: false,
            tags: ["work"]
        )

        XCTAssertFalse(
            NoteEditorView.shouldPersistDraft(
                force: false,
                lastPersistedDraft: persistedDraft,
                draft: persistedDraft
            )
        )

        XCTAssertTrue(
            NoteEditorView.shouldPersistDraft(
                force: false,
                lastPersistedDraft: persistedDraft,
                draft: updatedDraft
            )
        )

        XCTAssertFalse(
            NoteEditorView.shouldPersistDraft(
                force: false,
                lastPersistedDraft: nil,
                draft: updatedDraft
            )
        )

        XCTAssertTrue(
            NoteEditorView.shouldPersistDraft(
                force: true,
                lastPersistedDraft: nil,
                draft: updatedDraft
            )
        )
    }
}
