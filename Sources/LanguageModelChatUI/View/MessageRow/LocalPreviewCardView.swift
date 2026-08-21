//
//  LocalPreviewCardView.swift
//  LanguageModelChatUI
//

import UIKit

/// A localhost the agent mentioned, standing in the transcript as a card
/// instead of a link — it is not a web page, it is a thing running on the
/// paired machine.
///
/// Derived at render time from the message's own prose: the wire carries
/// text, nothing new is stored, and transcripts written before the feature
/// existed grow the card for free. The row only announces the tap; whoever
/// owns the screen decides what opening means.
public struct LocalPreviewRecord: Hashable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public var address: String { "\(host):\(port)" }

    /// The last localhost mention in a message's prose. Fenced code is
    /// excluded — a config sample inside ``` is an example, not an
    /// announcement — while inline code counts, because "起在
    /// `localhost:3000` 了" is exactly the sentence this card exists for.
    public static func detect(in text: String) -> LocalPreviewRecord? {
        guard text.contains("localhost:") || text.contains("127.0.0.1:") else { return nil }
        var prose = text
        while let open = prose.range(of: "```") {
            guard let close = prose.range(of: "```", range: open.upperBound ..< prose.endIndex) else {
                prose.removeSubrange(open.lowerBound ..< prose.endIndex)
                break
            }
            prose.removeSubrange(open.lowerBound ..< close.upperBound)
        }
        var found: LocalPreviewRecord?
        for match in prose.matches(of: /(localhost|127\.0\.0\.1):(\d{2,5})/) {
            if let port = Int(match.2), (1 ... 65535).contains(port) {
                found = LocalPreviewRecord(host: String(match.1), port: port)
            }
        }
        return found
    }
}

/// The card itself: address, which Mac, one arrow. The whole card is the
/// tap target; the arrow is the only thing that looks like an action.
final class LocalPreviewCardView: MessageListRowView {
    static let cardHeight: CGFloat = 62

    // The question card's palette: this too is a quiet system row inside
    // the conversation, not a message bubble.
    private static let cardBackground = UIColor(red: 0xF7 / 255, green: 0xFA / 255, blue: 0xFD / 255, alpha: 1)
    private static let cardStroke = UIColor(red: 0xE5 / 255, green: 0xED / 255, blue: 0xF5 / 255, alpha: 1)
    private static let mutedInk = UIColor(red: 0x7A / 255, green: 0x87 / 255, blue: 0x94 / 255, alpha: 1)
    private static let ink = UIColor(red: 0x10 / 255, green: 0x14 / 255, blue: 0x18 / 255, alpha: 1)
    private static let wellBackground = UIColor(red: 0xF1 / 255, green: 0xF4 / 255, blue: 0xF8 / 255, alpha: 1)

    private let addressLabel = UILabel()
    private let detailLabel = UILabel()
    private let arrowWell = UIView()
    private let arrow = UIImageView()

    /// Called when the card is tapped. The row does not open anything
    /// itself: the tunnel, the paywall, the browser all belong upstairs.
    var openHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 15
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = Self.cardStroke.cgColor
        contentView.backgroundColor = Self.cardBackground
        contentView.clipsToBounds = true

        addressLabel.font = UIFont.monospacedSystemFont(ofSize: 14.5, weight: .semibold)
        addressLabel.textColor = Self.ink
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = Self.mutedInk
        detailLabel.lineBreakMode = .byTruncatingTail

        arrowWell.backgroundColor = Self.wellBackground
        arrowWell.layer.cornerRadius = 15
        let arrowConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        arrow.image = UIImage(systemName: "arrow.up.right", withConfiguration: arrowConfiguration)
        arrow.tintColor = Self.ink
        arrow.contentMode = .center

        contentView.addSubview(addressLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(arrowWell)
        arrowWell.addSubview(arrow)

        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardTapped)))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    @objc private func cardTapped() {
        openHandler?()
    }

    func configure(_ record: LocalPreviewRecord, machineName: String?) {
        addressLabel.text = record.address
        if let machineName, !machineName.isEmpty {
            detailLabel.text = String(format: String.localized("On %@ · tap to preview"), machineName)
        } else {
            detailLabel.text = String.localized("Tap to preview on this phone")
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Indented to the agent's text column, like the question card: it
        // belongs to what the agent just said.
        var box = contentView.frame
        box.origin.x = MessageListView.listRowInsets.left + AgentAvatarView.column
        box.size.width = bounds.width - box.origin.x - MessageListView.listRowInsets.right
        contentView.frame = box

        let inset: CGFloat = 15
        let wellSize: CGFloat = 30
        arrowWell.frame = CGRect(
            x: contentView.bounds.width - inset - wellSize,
            y: (contentView.bounds.height - wellSize) / 2,
            width: wellSize, height: wellSize
        )
        arrow.frame = arrowWell.bounds
        let textWidth = arrowWell.frame.minX - inset - 10
        addressLabel.frame = CGRect(x: inset, y: 13, width: textWidth, height: 18)
        detailLabel.frame = CGRect(x: inset, y: 33, width: textWidth, height: 15)
    }
}
