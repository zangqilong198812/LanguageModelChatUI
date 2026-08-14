//
//  QuestionRecordView.swift
//  LanguageModelChatUI
//

import MarkdownView
import UIKit

/// A settled question, kept to one line of history.
///
/// While the question was open it filled the bottom of the screen; what it
/// leaves behind must not. The row says what was asked and what was chosen,
/// and unfolds to the options that were offered only when asked to — the
/// transcript is for reading back, not for re-living the decision.
final class QuestionRecordView: MessageListRowView {
    static let headerHeight: CGFloat = 18
    static let answerRowHeight: CGFloat = 25
    static let optionRowHeight: CGFloat = 18
    static let optionRowSpacing: CGFloat = 6
    private static let padding: CGFloat = 11
    private static let inset: CGFloat = 13
    private static let gap: CGFloat = 8

    /// The row's height for a record, known without laying anything out.
    static func height(for record: QuestionRecord) -> CGFloat {
        var height = padding * 2 + headerHeight
        if record.answer != nil {
            height += gap + answerRowHeight
        }
        if record.isExpanded, !record.options.isEmpty {
            height += gap + CGFloat(record.options.count) * optionRowHeight
                + CGFloat(record.options.count - 1) * optionRowSpacing
        }
        return height
    }

    // The design's inks. This card records a decision rather than reporting
    // system state, so it does not borrow the tint the working card uses.
    private static let cardBackground = UIColor(red: 0xF7 / 255, green: 0xFA / 255, blue: 0xFD / 255, alpha: 1)
    private static let cardStroke = UIColor(red: 0xE5 / 255, green: 0xED / 255, blue: 0xF5 / 255, alpha: 1)
    private static let mutedInk = UIColor(red: 0x7A / 255, green: 0x87 / 255, blue: 0x94 / 255, alpha: 1)
    private static let ghostInk = UIColor(red: 0x9A / 255, green: 0xA6 / 255, blue: 0xB2 / 255, alpha: 1)
    private static let faintInk = UIColor(red: 0xB4 / 255, green: 0xBE / 255, blue: 0xC8 / 255, alpha: 1)
    private static let chipBackground = UIColor(red: 0xEA / 255, green: 0xF5 / 255, blue: 0xFE / 255, alpha: 1)
    private static let ink = UIColor(red: 0x10 / 255, green: 0x14 / 255, blue: 0x18 / 255, alpha: 1)

    private let avatar = AgentAvatarView()
    private let questionIcon = UIImageView()
    private let promptLabel = UILabel()
    private let chevron = UIImageView()
    private let choseLabel = UILabel()
    private let answerChip = UILabel()
    private let timeLabel = UILabel()
    private var optionViews: [QuestionOptionRowView] = []

    /// Called when the card is tapped. The row does not own the expanded
    /// state: whoever holds the transcript decides what a tap means.
    var expandHandler: (() -> Void)?

    private var record: QuestionRecord?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 15
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = Self.cardStroke.cgColor
        contentView.backgroundColor = Self.cardBackground
        contentView.clipsToBounds = true

        let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        questionIcon.image = UIImage(systemName: "questionmark.circle", withConfiguration: iconConfiguration)
        questionIcon.tintColor = Self.mutedInk
        questionIcon.contentMode = .scaleAspectFit

        promptLabel.textColor = Self.mutedInk
        promptLabel.lineBreakMode = .byTruncatingTail

        chevron.tintColor = Self.faintInk
        chevron.contentMode = .scaleAspectFit

        choseLabel.textColor = Self.ghostInk
        answerChip.textColor = Self.ink
        answerChip.backgroundColor = Self.chipBackground
        answerChip.layer.cornerRadius = 9
        answerChip.layer.cornerCurve = .continuous
        answerChip.clipsToBounds = true
        answerChip.textAlignment = .center
        timeLabel.textColor = Self.faintInk

        contentView.addSubview(questionIcon)
        contentView.addSubview(promptLabel)
        contentView.addSubview(chevron)
        contentView.addSubview(choseLabel)
        contentView.addSubview(answerChip)
        contentView.addSubview(timeLabel)
        addSubview(avatar)

        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        contentView.isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() { expandHandler?() }

    func configure(_ record: QuestionRecord) {
        self.record = record

        promptLabel.font = theme.fonts.body.withSize(12.5)
        choseLabel.font = theme.fonts.codeInline.withSize(10)
        answerChip.font = theme.fonts.bold.withSize(13)
        timeLabel.font = theme.fonts.codeInline.withSize(10)

        promptLabel.text = String(format: String.localized("Asked: %@"), record.prompt)
        let chevronConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        chevron.image = UIImage(
            systemName: record.isExpanded ? "chevron.up" : "chevron.down",
            withConfiguration: chevronConfiguration
        )

        let hasAnswer = record.answer != nil
        choseLabel.isHidden = !hasAnswer
        answerChip.isHidden = !hasAnswer
        timeLabel.isHidden = !hasAnswer
        choseLabel.text = String.localized("You chose")
        answerChip.text = record.answer
        timeLabel.text = record.answeredAt.map { Self.timeFormatter.string(from: $0) }

        let shownOptions = record.isExpanded ? record.options : []
        while optionViews.count < shownOptions.count {
            let view = QuestionOptionRowView()
            contentView.addSubview(view)
            optionViews.append(view)
        }
        for (index, view) in optionViews.enumerated() {
            view.isHidden = index >= shownOptions.count
            guard index < shownOptions.count else { continue }
            let option = shownOptions[index]
            view.configure(
                option,
                letter: Self.letter(at: index),
                isChosen: option.label == record.answer,
                theme: theme
            )
        }
        setNeedsLayout()
    }

    private static func letter(at index: Int) -> String {
        guard let scalar = Unicode.Scalar(65 + index), index < 26 else { return "·" }
        return String(Character(scalar))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatar.frame = .init(
            x: MessageListView.listRowInsets.left,
            y: 2,
            width: AgentAvatarView.size,
            height: AgentAvatarView.size
        )
        var box = contentView.frame
        box.origin.x = MessageListView.listRowInsets.left + AgentAvatarView.column
        box.size.width = bounds.width - box.origin.x - MessageListView.listRowInsets.right
        contentView.frame = box

        let width = contentView.bounds.width
        var y = Self.padding

        questionIcon.frame = .init(x: Self.inset, y: y + 2.5, width: 13, height: 13)
        chevron.frame = .init(x: width - Self.inset - 13, y: y + 2.5, width: 13, height: 13)
        let promptX = Self.inset + 13 + 8
        promptLabel.frame = .init(
            x: promptX,
            y: y,
            width: max(0, chevron.frame.minX - 8 - promptX),
            height: Self.headerHeight
        )
        y += Self.headerHeight

        if record?.answer != nil {
            y += Self.gap
            let choseWidth = choseLabel.intrinsicContentSize.width
            choseLabel.frame = .init(x: Self.inset, y: y, width: choseWidth, height: Self.answerRowHeight)
            let chipWidth = min(
                answerChip.intrinsicContentSize.width + 20,
                width - Self.inset * 2 - choseWidth - 60
            )
            answerChip.frame = .init(x: Self.inset + choseWidth + 8, y: y, width: max(0, chipWidth), height: Self.answerRowHeight)
            timeLabel.frame = .init(
                x: answerChip.frame.maxX + 8,
                y: y,
                width: 44,
                height: Self.answerRowHeight
            )
            y += Self.answerRowHeight
        }

        if let record, record.isExpanded {
            y += Self.gap
            for view in optionViews where !view.isHidden {
                view.frame = .init(x: Self.inset, y: y, width: width - Self.inset * 2, height: Self.optionRowHeight)
                y += Self.optionRowHeight + Self.optionRowSpacing
            }
        }
    }
}

/// One offered option: its letter in a fixed gutter, then one line.
private final class QuestionOptionRowView: UIView {
    private let letterLabel = UILabel()
    private let textLabel = UILabel()

    private static let blueInk = UIColor(red: 0x1A / 255, green: 0x6F / 255, blue: 0xBF / 255, alpha: 1)
    private static let bodyInk = UIColor(red: 0x29 / 255, green: 0x32 / 255, blue: 0x3C / 255, alpha: 1)
    private static let mutedInk = UIColor(red: 0x7A / 255, green: 0x87 / 255, blue: 0x94 / 255, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        textLabel.lineBreakMode = .byTruncatingTail
        addSubview(letterLabel)
        addSubview(textLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ option: QuestionRecord.Option, letter: String, isChosen: Bool, theme: MarkdownTheme) {
        letterLabel.font = theme.fonts.codeInline.withSize(10)
        letterLabel.text = letter
        letterLabel.textColor = isChosen ? Self.blueInk : Self.mutedInk

        let text = NSMutableAttributedString(
            string: option.label,
            attributes: [
                .font: isChosen ? theme.fonts.bold.withSize(13) : theme.fonts.body.withSize(13),
                .foregroundColor: isChosen ? Self.blueInk : Self.bodyInk,
            ]
        )
        if let detail = option.detail, !detail.isEmpty {
            text.append(NSAttributedString(
                string: " — " + detail,
                attributes: [
                    .font: theme.fonts.body.withSize(12),
                    .foregroundColor: Self.mutedInk,
                ]
            ))
        }
        textLabel.attributedText = text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        letterLabel.frame = .init(x: 0, y: 0, width: 16, height: bounds.height)
        textLabel.frame = .init(x: 20, y: 0, width: max(0, bounds.width - 20), height: bounds.height)
    }
}
