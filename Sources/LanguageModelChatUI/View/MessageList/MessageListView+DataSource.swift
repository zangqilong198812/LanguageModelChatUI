//
//  MessageListView+DataSource.swift
//  LanguageModelChatUI
//
//  Data source types and message-to-entry conversion.
//

import Foundation
import MarkdownView

extension MessageListView {
    /// A lightweight representation of a message for display purposes.
    ///
    /// Equality deliberately excludes `content`. A turn's block is rewritten
    /// many times a second, and the diff hashes every entry on every rewrite
    /// — hashing the whole text of every message per frame is the cost this
    /// type exists to avoid. `contentVersion` is the change signal instead:
    /// whoever rewrites a message's content bumps it (see
    /// `ConversationMessage.markContentChanged`), so two entries with the same
    /// version and flags necessarily draw the same content.
    struct MessageRepresentation: Hashable {
        let id: String
        let createdAt: Date
        let role: MessageRole
        let content: String
        var isRevealed: Bool
        var isThinking: Bool
        var thinkingDuration: TimeInterval
        /// The owning message's rewrite counter; changes whenever its content
        /// does.
        var contentVersion: Int
        /// A line under the bubble — who said it, when, whether it landed.
        /// Read from the message's metadata, because only the app that put a
        /// message there knows whether it arrived.
        var footnote: String?

        static func == (lhs: MessageRepresentation, rhs: MessageRepresentation) -> Bool {
            lhs.id == rhs.id
                && lhs.createdAt == rhs.createdAt
                && lhs.role == rhs.role
                && lhs.isRevealed == rhs.isRevealed
                && lhs.isThinking == rhs.isThinking
                && lhs.thinkingDuration == rhs.thinkingDuration
                && lhs.contentVersion == rhs.contentVersion
                && lhs.footnote == rhs.footnote
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(createdAt)
            hasher.combine(role)
            hasher.combine(isRevealed)
            hasher.combine(isThinking)
            hasher.combine(thinkingDuration)
            hasher.combine(contentVersion)
            hasher.combine(footnote)
        }
    }

    struct Attachments: Hashable {
        let items: [ChatInputAttachment]
    }

    /// Displayable entries for the list view.
    enum Entry: Hashable, Identifiable {
        case userContent(String, MessageRepresentation)
        case userAttachment(String, Attachments)
        case reasoningContent(String, MessageRepresentation)
        case responseContent(String, MessageRepresentation)
        case hint(String, String)
        case toolCallHint(String, ToolCallContentPart)
        case activityReporting(String)
        /// A coding agent's working block: one card for a turn's steps. The
        /// flag rides in the entry (not just the message) so toggling it
        /// changes the row's identity and the list reconfigures it. The
        /// message's content version rides along for the same reason — a
        /// running block's step text changes without the steps' identity
        /// changing (their equality ignores text), and the version is what
        /// tells the diff the card must be redrawn.
        case progressCard(String, ProgressBlock, [ProgressStep], Bool, Int)
        /// A question the agent asked and settled: one line of history.
        case questionRecord(String, QuestionRecord)
        /// A localhost the message mentioned, derived from its prose.
        case localPreview(String, LocalPreviewRecord)

        var id: String {
            switch self {
            case let .userContent(id, _): "user-\(id)"
            case let .userAttachment(id, _): "user-attachment-\(id)"
            case let .reasoningContent(id, _): "reasoning-\(id)"
            case let .responseContent(id, _): "response-\(id)"
            case let .hint(id, _): "hint-\(id)"
            case let .toolCallHint(id, _): "tool-\(id)"
            case let .activityReporting(msg): "activity-\(msg)"
            case let .progressCard(id, _, _, _, _): "progress-\(id)"
            case let .questionRecord(id, _): "question-\(id)"
            case let .localPreview(id, record): "localpreview-\(id)-\(record.port)"
            }
        }
    }

    /// One formatter pair per process, not per snapshot: a streamed turn
    /// derives every row of the list many times a second, and a DateFormatter
    /// is expensive to construct.
    private static let hintFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Convert conversation messages to displayable entries.
    func entries(from messages: [ConversationMessage]) -> [Entry] {
        var entries: [Entry] = []
        var latestDisplayedDay: Date?

        let dateFormatter = Self.hintFormatter
        let dayKeyFormatter = Self.dayKeyFormatter

        func checkAddDateHint(_ date: Date) {
            if let latestDisplayedDay, Calendar.current.isDate(date, inSameDayAs: latestDisplayedDay) { return }
            latestDisplayedDay = date
            let hintText = dateFormatter.string(from: date)
            let dayKey = dayKeyFormatter.string(from: date)
            entries.append(.hint("date.\(dayKey)", hintText))
        }

        for message in messages {
            checkAddDateHint(message.createdAt)

            let textContent = message.textContent
            let reasoningContent = message.reasoningContent ?? ""
            let isThinking = textContent.isEmpty && !reasoningContent.isEmpty
            var reasoningDuration: TimeInterval = 0
            var reasoningCollapsed = false

            for part in message.parts {
                if case let .reasoning(rp) = part {
                    reasoningDuration = rp.duration
                    reasoningCollapsed = rp.isCollapsed
                }
            }

            let representation = MessageRepresentation(
                id: message.id,
                createdAt: message.createdAt,
                role: message.role,
                content: textContent,
                isRevealed: !reasoningCollapsed,
                isThinking: isThinking,
                thinkingDuration: reasoningDuration,
                contentVersion: message.contentVersion,
                        footnote: message.metadata["footnote"]
            )

            switch message.role {
            case .user:
                let attachmentItems = message.parts.compactMap { part -> ChatInputAttachment? in
                    switch part {
                    case let .image(imagePart):
                        return ChatInputAttachment(
                            type: .image,
                            name: imagePart.name ?? String.localized("Image"),
                            previewImageData: imagePart.previewData ?? imagePart.data,
                            fileData: imagePart.data,
                            storageFilename: imagePart.name ?? "image.jpeg"
                        )
                    case let .audio(audioPart):
                        return ChatInputAttachment(
                            type: .audio,
                            name: audioPart.name ?? String.localized("Audio"),
                            fileData: audioPart.data,
                            textContent: audioPart.transcription ?? audioPart.name ?? "",
                            storageFilename: audioPart.name ?? "audio.m4a"
                        )
                    case let .file(filePart):
                        return ChatInputAttachment(
                            type: .document,
                            name: filePart.name ?? String.localized("Document"),
                            textContent: filePart.textContent ?? String(data: filePart.data, encoding: .utf8) ?? "",
                            storageFilename: filePart.name ?? "document.txt"
                        )
                    case .text, .reasoning, .toolCall, .toolResult:
                        return nil
                    }
                }
                if !attachmentItems.isEmpty {
                    entries.append(.userAttachment(message.id, .init(items: attachmentItems)))
                }
                if !textContent.isEmpty {
                    entries.append(.userContent(message.id, representation))
                }

            case .assistant:
                // A settled question is its receipt, nothing more: the asking
                // happened in a bar the list never drew.
                if let record = message.question {
                    entries.append(.questionRecord(message.id, record))
                    continue
                }

                // A working block is drawn whole. Emitting a row per tool call
                // is what buries the reply under its own plumbing.
                if let block = message.progress {
                    entries.append(.progressCard(
                        message.id,
                        block,
                        ProgressStep.steps(of: message),
                        message.isProgressExpanded,
                        message.contentVersion
                    ))
                    continue
                }

                // Reasoning
                if !reasoningContent.isEmpty {
                    let reasoningRep = MessageRepresentation(
                        id: message.id,
                        createdAt: message.createdAt,
                        role: message.role,
                        content: reasoningContent,
                        isRevealed: !reasoningCollapsed,
                        isThinking: isThinking,
                        thinkingDuration: reasoningDuration,
                        contentVersion: message.contentVersion,
                        footnote: message.metadata["footnote"]
                    )
                    entries.append(.reasoningContent(message.id, reasoningRep))
                }

                // Tool calls
                for part in message.parts {
                    if case let .toolCall(tc) = part {
                        entries.append(.toolCallHint(tc.id, tc))
                    }
                }

                // Text content
                if !textContent.isEmpty {
                    entries.append(.responseContent(message.id, representation))
                    // A mentioned localhost grows a card under the prose —
                    // derived here, at render time, so history gets it too.
                    if let record = LocalPreviewRecord.detect(in: textContent) {
                        entries.append(.localPreview(message.id, record))
                    }
                }

            case .system:
                // System messages are not displayed in the list
                break

            default:
                // Custom roles: display as hint
                if !textContent.isEmpty {
                    entries.append(.hint(message.id, textContent))
                }
            }
        }

        return entries
    }
}

// MARK: - ToolCallContentPart Hashable

extension ToolCallContentPart: Hashable {
    public static func == (lhs: ToolCallContentPart, rhs: ToolCallContentPart) -> Bool {
        lhs.id == rhs.id && lhs.state == rhs.state && lhs.isExpanded == rhs.isExpanded
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(state)
        hasher.combine(isExpanded)
    }
}

extension ToolCallState: Hashable {}
