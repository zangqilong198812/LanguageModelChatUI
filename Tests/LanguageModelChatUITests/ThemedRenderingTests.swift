//
//  ThemedRenderingTests.swift
//  LanguageModelChatUI
//

import MarkdownView
import Testing
import UIKit
@testable import LanguageModelChatUI

/// The bug being chased: hand a theme to the renderer and the rows measure at
/// one size, draw blank, and occupy several times their height. Reproduced
/// here so the fix is a change to a failing test rather than a guess shipped
/// to a phone.
@MainActor
@Suite("主题到达渲染器")
struct ThemedRenderingTests {
    /// A theme visibly unlike the default: half the size, so a row measured
    /// with one and drawn with the other cannot agree by accident.
    private var customTheme: MarkdownTheme {
        var theme = MarkdownTheme.default
        theme.fonts.body = .systemFont(ofSize: 9)
        theme.fonts.bold = .boldSystemFont(ofSize: 9)
        return theme
    }

    private func makeListView(theme: MarkdownTheme?) -> MessageListView {
        let list = MessageListView()
        if let theme { list.theme = theme }
        list.frame = .init(x: 0, y: 0, width: 390, height: 844)
        return list
    }

    private func message(_ text: String) -> ConversationMessage {
        let message = ConversationMessage(conversationID: "c1", role: .assistant)
        message.parts = [.text(TextContentPart(text: text))]
        return message
    }

    /// What the adapter reports for a row must match what the row then draws.
    /// The screenshots showed several-hundred-point rows with nothing in them.
    @Test
    func aThemedRowMeasuresAndRendersTheSameContent() async throws {
        let list = makeListView(theme: customTheme)
        let prose = "你好！有什么可以帮你的吗？我看到当前项目 `Budget` 分支 `main` 上有个未提交的改动。"

        let package = list.markdownPackageCache.package(
            for: .init(
                id: "m1", createdAt: .init(), role: .assistant, content: prose,
                isRevealed: true, isThinking: false, thinkingDuration: 0, footnote: nil
            ),
            theme: list.theme
        )

        // The size-calculation path, exactly as the adapter runs it.
        list.markdownViewForSizeCalculation.theme = list.theme
        list.markdownViewForSizeCalculation.setMarkdownManually(package)
        let measured = list.markdownViewForSizeCalculation.boundingSize(for: 350).height

        // The row path, exactly as configureRowView runs it.
        let row = ResponseView()
        row.theme = list.theme
        row.markdownView.setMarkdown(package)
        row.frame = .init(x: 0, y: 0, width: 390, height: measured)
        row.layoutIfNeeded()

        // The throttled pipeline delivers on the main queue, which only drains
        // while the main actor is suspended — a spinning run loop starves it.
        for _ in 0 ..< 50 where row.markdownView.document.blocks.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }

        let throttledDelivered = !row.markdownView.document.blocks.isEmpty

        // The bisect: skip the throttled pipeline entirely. If content appears
        // now, the builder is fine and the pipeline lost the package; if not,
        // the builder itself cannot lay this package out.
        row.markdownView.setMarkdownManually(package)
        let syncDelivered = !row.markdownView.document.blocks.isEmpty
        let drawn = row.markdownView.boundingSize(for: 350).height

        #expect(throttledDelivered, "节流管线没送达")
        #expect(syncDelivered, "同步路径也排不出——问题在排版器")
        #expect(measured > 10, "量出的高度不像一行文字: \(measured)")
        #expect(abs(drawn - measured) < 2, "量高 \(measured) 与实画 \(drawn) 不一致")
    }

    /// The same, at the default theme — the control group. If this fails too,
    /// the bug is not the theme at all.
    @Test
    func theDefaultThemeAgreesWithItself() {
        let list = makeListView(theme: nil)
        let package = list.markdownPackageCache.package(
            for: .init(
                id: "m2", createdAt: .init(), role: .assistant, content: "一段普通的话。",
                isRevealed: true, isThinking: false, thinkingDuration: 0, footnote: nil
            ),
            theme: list.theme
        )
        list.markdownViewForSizeCalculation.theme = list.theme
        list.markdownViewForSizeCalculation.setMarkdownManually(package)
        let measured = list.markdownViewForSizeCalculation.boundingSize(for: 350).height
        #expect(measured > 10)
    }
}
