//
//  ProgressStep.swift
//  LanguageModelChatUI
//

import Foundation

/// One line inside a working block.
///
/// Flattened from the message's parts so the card can draw them without
/// re-deciding what each one is on every layout pass — a block is rewritten
/// many times a second while a turn runs.
public struct ProgressStep: Hashable, Sendable {
    /// Equality ignores the step's text on purpose. A running block's text
    /// grows on every redraw, and hashing it per frame is most of the diff
    /// cost of a streaming turn; the card row is re-created when the owning
    /// message's `contentVersion` changes, which is bumped on every rewrite.
    /// The text still rides the value — the row reads it from the entry it
    /// was configured with — it just does not take part in identity.
    public static func == (lhs: ProgressStep, rhs: ProgressStep) -> Bool {
        lhs.kind == rhs.kind && lhs.failed == rhs.failed
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(failed)
    }
    public enum Kind: Hashable, Sendable {
        case thinking
        case tool
        case result
        case note

        /// The word in the card's gutter. Fixed width, so a rewrite lands text
        /// in the right row instead of reflowing the block.
        public var label: String {
            switch self {
            case .thinking: String.localized("Thinking")
            case .tool: String.localized("Tool")
            case .result: String.localized("Result")
            case .note: String.localized("Note")
            }
        }
    }

    public var kind: Kind
    /// What the step says, already one line: the card truncates rather than
    /// wraps, because a step is a label and not a paragraph.
    public var text: String
    public var failed: Bool

    public init(kind: Kind, text: String, failed: Bool = false) {
        self.kind = kind
        self.text = text
        self.failed = failed
    }

    /// Reads a message's parts as the steps of a working block.
    public static func steps(of message: ConversationMessage) -> [ProgressStep] {
        message.parts.compactMap { part in
            switch part {
            case let .reasoning(reasoning):
                return ProgressStep(kind: .thinking, text: reasoning.text)
            case let .toolCall(call):
                let detail = call.parameters.isEmpty ? call.toolName : "\(call.toolName) \(call.parameters)"
                switch call.state {
                case .running:
                    return ProgressStep(kind: .tool, text: detail)
                case .succeeded:
                    return ProgressStep(kind: .result, text: detail)
                case .failed:
                    return ProgressStep(kind: .result, text: detail, failed: true)
                }
            case let .text(text):
                return ProgressStep(kind: .note, text: text.text)
            default:
                return nil
            }
        }
    }
}
