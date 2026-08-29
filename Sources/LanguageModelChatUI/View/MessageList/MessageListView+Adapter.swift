//
//  MessageListView+Adapter.swift
//  LanguageModelChatUI
//

import ListViewKit
import Litext
import MarkdownView
import UIKit

private extension MessageListView {
    enum RowType {
        case userContent
        case userAttachment
        case reasoningContent
        case responseContent
        case hint
        case toolCallHint
        case activityReporting
        case progressCard
        case questionRecord
        case localPreview
        case deliverable
    }
}

extension MessageListView: ListViewAdapter {
    private func entryForRow(at index: Int) -> Entry? {
        dataSource.snapshot().item(at: index)
    }

    public func listView(_: ListView, rowKindFor _: any Identifiable, at index: Int) -> any Hashable {
        guard let entry = entryForRow(at: index) else { return RowType.hint }
        return switch entry {
        case .userContent: RowType.userContent
        case .userAttachment: RowType.userAttachment
        case .reasoningContent: RowType.reasoningContent
        case .responseContent: RowType.responseContent
        case .hint: RowType.hint
        case .toolCallHint: RowType.toolCallHint
        case .activityReporting: RowType.activityReporting
        case .progressCard: RowType.progressCard
        case .questionRecord: RowType.questionRecord
        case .localPreview: RowType.localPreview
        case .deliverable: RowType.deliverable
        }
    }

    public func listViewMakeRow(for kind: any Hashable) -> ListRowView {
        guard let type = kind as? RowType else { return .init() }

        let view: MessageListRowView = switch type {
        case .userContent:
            UserMessageView()
        case .userAttachment:
            UserAttachmentView()
        case .reasoningContent:
            ReasoningContentView()
        case .responseContent:
            ResponseView()
        case .hint:
            HintMessageView()
        case .toolCallHint:
            ToolHintView()
        case .activityReporting:
            ActivityReportingView()
        case .progressCard:
            ProgressCardView()
        case .questionRecord:
            QuestionRecordView()
        case .localPreview:
            LocalPreviewCardView()
        case .deliverable:
            DeliverableCardView()
        }
        view.theme = theme
        return view
    }

    public func listView(_ listView: ListView, heightFor _: any Identifiable, at index: Int) -> CGFloat {
        guard let entry = entryForRow(at: index) else { return 0 }

        let listRowInsets = MessageListView.listRowInsets
        let containerWidth = max(0, listView.bounds.width - listRowInsets.horizontal)
        if containerWidth == 0 { return 0 }

        let bottomInset = listRowInsets.bottom
        let contentHeight: CGFloat = {
            switch entry {
            case let .userContent(_, message):
                let attributedContent = NSAttributedString(string: message.content, attributes: [
                    .font: theme.fonts.body,
                    .foregroundColor: theme.colors.body,
                ])
                let availableWidth = UserMessageView.availableTextWidth(for: containerWidth)
                return boundingSize(with: availableWidth, for: attributedContent).height
                    + UserMessageView.verticalTextPadding * 2
                    + (message.footnote == nil ? 0 : UserMessageView.footnoteHeight)
            case .userAttachment:
                return AttachmentsBar.itemHeight
            case let .reasoningContent(_, message):
                let attributedContent = NSAttributedString(string: message.content, attributes: [
                    .font: theme.fonts.footnote,
                    .paragraphStyle: ReasoningContentView.paragraphStyle,
                ])
                if message.isRevealed {
                    return boundingSize(with: containerWidth - 16, for: attributedContent).height
                        + ReasoningContentView.spacing
                        + ReasoningContentView.revealedTileHeight
                        + 2
                } else {
                    return ReasoningContentView.unrevealedTileHeight
                }
            case let .responseContent(_, message):
                markdownViewForSizeCalculation.theme = theme
                let package = markdownPackageCache.package(for: message, theme: theme)
                markdownViewForSizeCalculation.setMarkdownManually(package)
                // Measured at the width the prose will actually get: the mark's
                // column comes off the left, and a height taken at full width
                // undercounts every message that wraps.
                return ceil(markdownViewForSizeCalculation.boundingSize(for: containerWidth - AgentAvatarView.column).height)
            case .hint:
                return ceil(theme.fonts.footnote.lineHeight + 16)
            case let .activityReporting(content):
                let textHeight = boundingSize(with: .greatestFiniteMagnitude, for: NSAttributedString(string: content, attributes: [
                    .font: theme.fonts.body,
                ])).height
                return max(textHeight, ActivityReportingView.loadingSymbolSize.height + 16)
            case let .toolCallHint(_, toolCall):
                let bodyLineHeight = theme.fonts.body.lineHeight
                guard toolCall.isExpanded else {
                    return ToolHintView.height(isExpanded: false, detailHeight: 0, bodyLineHeight: bodyLineHeight)
                }
                let detailHeight = boundingSize(
                    with: containerWidth - 24,
                    for: NSAttributedString(string: toolCall.parameters, attributes: [
                        .font: theme.fonts.footnote,
                    ])
                ).height
                return ToolHintView.height(
                    isExpanded: true,
                    detailHeight: ceil(detailHeight),
                    bodyLineHeight: bodyLineHeight
                )
            case let .progressCard(_, block, steps, isExpanded, _):
                return ProgressCardView.height(
                    steps: steps.count,
                    hasFooter: block.stepCount > ProgressCardView.window || isExpanded,
                    isRunning: block.state == .running,
                    isExpanded: isExpanded
                )
            case let .questionRecord(_, record):
                return QuestionRecordView.height(for: record)
            case .localPreview:
                return LocalPreviewCardView.cardHeight
            case let .deliverable(_, items):
                return DeliverableCardView.height(for: items)
            }
        }()

        return contentHeight + bottomInset
    }

    public func listView(_: ListView, configureRowView rowView: ListRowView, for _: any Identifiable, at index: Int) {
        guard let entry = entryForRow(at: index) else { return }

        if let card = rowView as? ProgressCardView {
            if case let .progressCard(id, block, steps, isExpanded, _) = entry {
                card.configure(block: block, steps: steps, isExpanded: isExpanded)
                card.expandHandler = { [weak self] in
                    guard let self, let message = session?.message(for: id) else { return }
                    message.isProgressExpanded.toggle()
                    message.markContentChanged()
                    session?.notifyMessagesDidChange(scrolling: false)
                }
            }
            return
        }

        if let deliverableRow = rowView as? DeliverableCardView {
            if case let .deliverable(_, items) = entry {
                deliverableRow.theme = theme
                deliverableRow.thumbProvider = deliverableThumbProvider
                deliverableRow.configure(items)
                deliverableRow.openHandler = { [weak self] item in
                    self?.onDeliverableOpen?(item)
                }
            }
            return
        }

        if let previewCard = rowView as? LocalPreviewCardView {
            if case let .localPreview(_, record) = entry {
                previewCard.theme = theme
                previewCard.configure(record, machineName: localPreviewMachineName)
                previewCard.openHandler = { [weak self] in
                    self?.onLocalPreviewOpen?(record)
                }
            }
            return
        }

        if let questionView = rowView as? QuestionRecordView {
            if case let .questionRecord(id, record) = entry {
                questionView.theme = theme
                questionView.configure(record)
                questionView.expandHandler = { [weak self] in
                    guard let self, let message = session?.message(for: id) else { return }
                    message.question?.isExpanded.toggle()
                    message.markContentChanged()
                    session?.notifyMessagesDidChange(scrolling: false)
                }
            }
            return
        }

        if let userMessageView = rowView as? UserMessageView {
            if case let .userContent(_, message) = entry {
                userMessageView.theme = theme
                userMessageView.text = message.content
                userMessageView.footnote = message.footnote
            }
        } else if let userAttachmentView = rowView as? UserAttachmentView {
            if case let .userAttachment(_, attachments) = entry {
                userAttachmentView.theme = theme
                userAttachmentView.update(with: attachments)
            }
        } else if let responseView = rowView as? ResponseView {
            if case let .responseContent(id, message) = entry {
                responseView.theme = theme
                let package = markdownPackageCache.package(for: message, theme: theme)
                responseView.markdownView.setMarkdown(package)
                // Copy and export live in the long-press menu. The gate is
                // asked at press time, not configure time, so a message that
                // finishes streaming grows its menu without a reconfigure.
                responseView.contextMenuProvider = { [weak self] _ in
                    guard let self, messageActionsProvider?(id) == true else { return nil }
                    var actions = [
                        UIAction(
                            title: String.localized("Copy"),
                            image: UIImage(systemName: "doc.on.doc")
                        ) { [weak self] _ in self?.onMessageCopy?(id) },
                        UIAction(
                            title: String.localized("Export as Image"),
                            image: UIImage(systemName: "photo")
                        ) { [weak self] _ in self?.onMessageExport?(id) },
                    ]
                    // Only hosts that know what a memory is offer one.
                    if onMessageMemorize != nil {
                        actions.append(UIAction(
                            title: String.localized("Add to Memory"),
                            image: UIImage(systemName: "folder")
                        ) { [weak self] _ in self?.onMessageMemorize?(id) })
                    }
                    return UIMenu(children: actions)
                }
            }
        } else if let hintMessageView = rowView as? HintMessageView {
            if case let .hint(_, content) = entry {
                hintMessageView.theme = theme
                hintMessageView.text = content
            }
        } else if let activityReportingView = rowView as? ActivityReportingView {
            if case let .activityReporting(content) = entry {
                activityReportingView.theme = theme
                activityReportingView.text = content
            }
        } else if let reasoningContentView = rowView as? ReasoningContentView {
            if case let .reasoningContent(_, message) = entry {
                reasoningContentView.theme = theme
                reasoningContentView.isRevealed = message.isRevealed
                reasoningContentView.isThinking = message.isThinking
                reasoningContentView.thinkingDuration = message.thinkingDuration
                reasoningContentView.text = message.content
                reasoningContentView.thinkingTileTapHandler = { [weak self] _ in
                    guard let self, let conversationMessage = session?.message(for: message.id) else { return }
                    for (index, part) in conversationMessage.parts.enumerated() {
                        if case var .reasoning(reasoningPart) = part {
                            reasoningPart.isCollapsed.toggle()
                            conversationMessage.parts[index] = .reasoning(reasoningPart)
                            break
                        }
                    }
                    // The row's revealed state drew from the part; the snapshot
                    // cache keys on the message's version, so say so.
                    conversationMessage.markContentChanged()
                    session?.notifyMessagesDidChange(scrolling: false)
                }
            }
        } else if let toolHintView = rowView as? ToolHintView {
            if case let .toolCallHint(_, toolCall) = entry {
                toolHintView.theme = theme
                toolHintView.toolName = toolCall.toolName
                toolHintView.text = toolCall.parameters
                toolHintView.state = toolCall.state
                toolHintView.isExpanded = toolCall.isExpanded
                toolHintView.clickHandler = { [weak self] in
                    guard let self,
                          let message = session?.message(containingPart: toolCall.id) else { return }
                    for (index, part) in message.parts.enumerated() {
                        if case var .toolCall(tc) = part, tc.id == toolCall.id {
                            tc.isExpanded.toggle()
                            message.parts[index] = .toolCall(tc)
                            break
                        }
                    }
                    message.markContentChanged()
                    session?.notifyMessagesDidChange(scrolling: false)
                }
            }
        }
    }

    private func boundingSize(with width: CGFloat, for attributedString: NSAttributedString) -> CGSize {
        labelForSizeCalculation.preferredMaxLayoutWidth = width
        labelForSizeCalculation.attributedText = attributedString
        let contentSize = labelForSizeCalculation.intrinsicContentSize
        return .init(width: ceil(contentSize.width), height: ceil(contentSize.height))
    }
}
