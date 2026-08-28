//
//  ConversationMessage.swift
//  LanguageModelChatUI
//

import Foundation

/// A message in a conversation, composed of typed content parts.
public final class ConversationMessage: Identifiable, @unchecked Sendable {
    public let id: String
    public let conversationID: String
    public var role: MessageRole
    public var parts: [ContentPart]
    public var createdAt: Date
    public var metadata: [String: String]
    /// Files the assistant handed the user — the deliver channel. Rendered
    /// as their own card row; bytes are resolved by the host app, the list
    /// only names them.
    public var deliverables: [DeliverableItem] = []

    /// Bumped whenever the message's displayable content changes in place.
    ///
    /// The list derives a row's identity from this rather than from hashing
    /// the whole content text: a turn's block is rewritten many times a
    /// second, and re-hashing every message's text on every rewrite is most
    /// of the cost of a streaming turn. Any code that replaces `parts` or the
    /// text a row draws must call `markContentChanged`, or the diff will not
    /// notice and the row will go stale.
    public private(set) var contentVersion: Int = 0


    /// Set when this message is a coding agent's working block rather than
    /// prose: a turn's steps, rewritten in place as it works.
    ///
    /// The list draws one card for the whole block instead of a row per tool
    /// call, because a turn can run a dozen tools and the reply must not be
    /// pushed off the screen by its own plumbing.
    public var progress: ProgressBlock?

    /// Whether the working card is showing every step rather than its window.
    ///
    /// Carried on the message rather than the block: the block is rebuilt from
    /// every frame, and a flag on it would be reset by the next redraw.
    public var isProgressExpanded: Bool = false

    /// Set when this message records a question the agent asked and settled.
    ///
    /// While a question is open it is a bar the user acts on, not a row — the
    /// list renders rows that cannot be tapped. What lands here afterwards is
    /// the receipt: one line of history, expandable to the options that were
    /// offered at the time.
    public var question: QuestionRecord?


    /// Records that the content a row draws changed. The list keys its
    /// snapshots on this, so a mutation that skips it is a row that never
    /// repaints.
    public func markContentChanged() {
        contentVersion &+= 1
    }

    public init(
        id: String = UUID().uuidString,
        conversationID: String,
        role: MessageRole,
        parts: [ContentPart] = [],
        createdAt: Date = .init(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.parts = parts
        self.createdAt = createdAt
        self.metadata = metadata
        self.isProgressExpanded = false
    }
}

/// A turn's working block: how far it got, and how much of it is being shown.
public struct ProgressBlock: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case running, completed, failed
    }

    public var state: State
    /// Steps in the whole block, including the ones the card is not showing.
    public var stepCount: Int
    /// The host dropped earlier steps before sending it.
    public var truncated: Bool

    public init(state: State, stepCount: Int, truncated: Bool = false) {
        self.state = state
        self.stepCount = stepCount
        self.truncated = truncated
    }
}

/// A question the agent asked, kept after it was answered.
///
/// The prompt and the options are the host's, shown as given. The answer is
/// whichever option label was chosen — free-text answers travel as ordinary
/// user messages and never produce one of these.
public struct QuestionRecord: Hashable, Sendable {
    public struct Option: Hashable, Sendable {
        public var label: String
        public var detail: String?

        public init(label: String, detail: String? = nil) {
            self.label = label
            self.detail = detail
        }
    }

    public var prompt: String
    /// The chosen option's label, if this phone knows it. A question can be
    /// settled elsewhere, and a record must not invent the answer it missed.
    public var answer: String?
    public var answeredAt: Date?
    public var options: [Option]
    /// Whether the row is showing the options it collapsed. Carried on the
    /// record rather than in the view: rows are reused, and state left in a
    /// view surfaces on whichever message is dealt that view next.
    public var isExpanded: Bool

    public init(
        prompt: String,
        answer: String? = nil,
        answeredAt: Date? = nil,
        options: [Option] = [],
        isExpanded: Bool = false
    ) {
        self.prompt = prompt
        self.answer = answer
        self.answeredAt = answeredAt
        self.options = options
        self.isExpanded = isExpanded
    }
}

// MARK: - Convenience Accessors

public extension ConversationMessage {
    /// The primary text content of this message (first text part).
    var textContent: String {
        get {
            for part in parts {
                if case let .text(textPart) = part {
                    return textPart.text
                }
            }
            return ""
        }
        set {
            for (index, part) in parts.enumerated() {
                if case var .text(textPart) = part {
                    guard textPart.text != newValue else { return }
                    textPart.text = newValue
                    parts[index] = .text(textPart)
                    markContentChanged()
                    return
                }
            }
            parts.insert(.text(TextContentPart(text: newValue)), at: 0)
            markContentChanged()
        }
    }

    /// The finish reason for this message, stored in metadata.
    var finishReason: FinishReason? {
        get {
            guard let raw = metadata["finishReason"] else { return nil }
            return FinishReason(rawValue: raw)
        }
        set {
            metadata["finishReason"] = newValue?.rawValue
        }
    }

    /// The reasoning content of this message (first reasoning part), if any.
    var reasoningContent: String? {
        get {
            for part in parts {
                if case let .reasoning(rp) = part {
                    return rp.text
                }
            }
            return nil
        }
        set {
            for (index, part) in parts.enumerated() {
                if case var .reasoning(rp) = part {
                    guard rp.text != (newValue ?? "") else { return }
                    rp.text = newValue ?? ""
                    parts[index] = .reasoning(rp)
                    markContentChanged()
                    return
                }
            }
            if let newValue, !newValue.isEmpty {
                parts.append(.reasoning(ReasoningContentPart(text: newValue)))
                markContentChanged()
            }
        }
    }
}

/// One delivered file, as the conversation names it. `id` doubles as the
/// host app's storage key.
public struct DeliverableItem: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let mediaType: String
    public let size: Int64

    public init(id: String, name: String, mediaType: String, size: Int64) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.size = size
    }

    public var isImage: Bool { mediaType.hasPrefix("image/") }
}
