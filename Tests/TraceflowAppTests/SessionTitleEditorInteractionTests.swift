import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionTitleEditorInteractionTests: XCTestCase {
    func testNativeInputRejectsMultilineAndPreservesDraftAfterHook() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("interaction", event: .sessionStart)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 280),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: SessionTitleEditorView(model: fixture.model, session: try fixture.session("interaction")))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("第一行\n第二行", replacementRange: editor.selectedRange())
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(editor.string, "第一行\n第二行")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(try fixture.session("interaction").persisted.customTitle)
        editor.selectAll(nil)
        editor.insertText("后台更新仍保留草稿", replacementRange: editor.selectedRange())
        try await fixture.hook("interaction", event: .userPromptSubmit)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(editor.string, "后台更新仍保留草稿")
        XCTAssertNil(try fixture.session("interaction").persisted.customTitle)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await fixture.waitUntil {
            fixture.model.sessions.first?.persisted.customTitle == "后台更新仍保留草稿"
        }
    }
}
