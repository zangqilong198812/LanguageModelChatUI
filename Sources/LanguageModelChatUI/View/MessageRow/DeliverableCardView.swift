//
//  DeliverableCardView.swift
//  LanguageModelChatUI
//

import UIKit

/// Files the agent handed the user, standing in the transcript as white
/// cards: 说明是话,文件是东西 — the agent's words arrive as its own message,
/// and this row is only the things.
///
/// Images sit side by side as thumbnails; everything else is a file card
/// with its name and size. The row resolves no bytes itself — thumbnails
/// come from the host app through a provider, and every tap is announced
/// upstairs, where opening, sharing and keeping are decided.
final class DeliverableCardView: MessageListRowView {
    private static let ink = UIColor(red: 0x10 / 255, green: 0x14 / 255, blue: 0x18 / 255, alpha: 1)
    private static let mutedInk = UIColor(red: 0x5B / 255, green: 0x68 / 255, blue: 0x75 / 255, alpha: 1)
    private static let faintInk = UIColor(red: 0x9A / 255, green: 0xA6 / 255, blue: 0xB2 / 255, alpha: 1)
    private static let cardStroke = UIColor(red: 0xE5 / 255, green: 0xED / 255, blue: 0xF5 / 255, alpha: 1)
    private static let chipWell = UIColor(red: 0xF1 / 255, green: 0xF4 / 255, blue: 0xF8 / 255, alpha: 1)

    static let thumbSide: CGFloat = 96
    static let fileCardHeight: CGFloat = 56
    static let rowGap: CGFloat = 8

    /// A thumb keeps the picture's own shape: height fixed at thumbSide,
    /// width from the aspect ratio — clamped so a panorama or a tall phone
    /// shot still reads as a card instead of a ribbon.
    private static let thumbMinWidth: CGFloat = 54
    private static let thumbMaxWidth: CGFloat = 170

    /// The whole group's height, computed the same way layoutSubviews will
    /// place it — the list asks before the row exists.
    static func height(for items: [DeliverableItem]) -> CGFloat {
        let images = items.filter(\.isImage)
        let files = items.count - images.count
        var height: CGFloat = 0
        if !images.isEmpty { height += thumbSide + rowGap }
        height += CGFloat(files) * (fileCardHeight + rowGap)
        return max(height, 0)
    }

    var openHandler: ((DeliverableItem) -> Void)?
    var thumbProvider: ((DeliverableItem) -> UIImage?)?

    private var items: [DeliverableItem] = []
    private var itemViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    func configure(_ items: [DeliverableItem]) {
        self.items = items
        for view in itemViews { view.removeFromSuperview() }
        itemViews = []

        for (index, item) in items.enumerated() {
            let view: UIView = item.isImage ? thumbView(item) : fileCard(item)
            view.tag = index
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemTapped(_:))))
            view.isUserInteractionEnabled = true
            contentView.addSubview(view)
            itemViews.append(view)
        }
        setNeedsLayout()
    }

    @objc private func itemTapped(_ recognizer: UITapGestureRecognizer) {
        guard let index = recognizer.view?.tag, items.indices.contains(index) else { return }
        openHandler?(items[index])
    }

    private func thumbView(_ item: DeliverableItem) -> UIView {
        let image = UIImageView()
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 12
        image.layer.cornerCurve = .continuous
        image.layer.borderWidth = 1
        image.layer.borderColor = Self.cardStroke.cgColor
        image.backgroundColor = Self.chipWell
        image.image = thumbProvider?(item)
        if image.image == nil {
            // Bytes still in flight: a quiet well with the kind's mark, and
            // the provider refreshing the row will fill it in.
            let placeholder = UIImageView(image: UIImage(
                systemName: "photo",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .light)
            ))
            placeholder.tintColor = Self.faintInk
            placeholder.contentMode = .center
            placeholder.frame = CGRect(x: 0, y: 0, width: Self.thumbSide, height: Self.thumbSide)
            placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            image.addSubview(placeholder)
        }
        return image
    }

    private func fileCard(_ item: DeliverableItem) -> UIView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = Self.cardStroke.cgColor

        let well = UIView()
        well.backgroundColor = Self.chipWell
        well.layer.cornerRadius = 10
        well.frame = CGRect(x: 11, y: 11, width: 34, height: 34)
        let icon = UIImageView(image: UIImage(
            systemName: symbolFor(item.mediaType),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ))
        icon.tintColor = Self.mutedInk
        icon.contentMode = .center
        icon.frame = well.bounds
        icon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        well.addSubview(icon)
        card.addSubview(well)

        let name = UILabel()
        name.font = .systemFont(ofSize: 13.5, weight: .semibold)
        name.textColor = Self.ink
        name.lineBreakMode = .byTruncatingMiddle
        name.text = item.name
        name.tag = 101
        card.addSubview(name)

        let meta = UILabel()
        meta.font = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        meta.textColor = Self.faintInk
        meta.text = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        meta.tag = 102
        card.addSubview(meta)

        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        ))
        chevron.tintColor = Self.faintInk
        chevron.contentMode = .center
        chevron.tag = 103
        card.addSubview(chevron)
        return card
    }

    /// Square while the bytes are still in flight — the placeholder has no
    /// shape to borrow; the provider refresh re-lays the row with the real one.
    private static func thumbWidth(for image: UIImage?) -> CGFloat {
        guard let size = image?.size, size.height > 0 else { return thumbSide }
        return min(max(thumbSide * size.width / size.height, thumbMinWidth), thumbMaxWidth)
    }

    private func symbolFor(_ mediaType: String) -> String {
        if mediaType.hasPrefix("video/") { return "play.rectangle.fill" }
        if mediaType.hasPrefix("audio/") { return "waveform" }
        if mediaType.contains("pdf") { return "doc.richtext" }
        if mediaType.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var box = contentView.frame
        box.origin.x = MessageListView.listRowInsets.left + AgentAvatarView.column
        box.size.width = bounds.width - box.origin.x - MessageListView.listRowInsets.right
        contentView.frame = box

        let width = contentView.bounds.width
        var y: CGFloat = 0
        var thumbX: CGFloat = 0
        var placedThumb = false

        for (index, item) in items.enumerated() {
            guard index < itemViews.count else { break }
            let view = itemViews[index]
            if item.isImage {
                // Side by side until the row runs out; the overflow clips,
                // which for the two-or-three images a turn sends is never
                // reached.
                let thumbWidth = Self.thumbWidth(for: (view as? UIImageView)?.image)
                if thumbX + thumbWidth > width { continue }
                view.frame = CGRect(x: thumbX, y: y, width: thumbWidth, height: Self.thumbSide)
                thumbX += thumbWidth + Self.rowGap
                placedThumb = true
            } else {
                if placedThumb {
                    y += Self.thumbSide + Self.rowGap
                    placedThumb = false
                    thumbX = 0
                }
                view.frame = CGRect(x: 0, y: y, width: width, height: Self.fileCardHeight)
                if let name = view.viewWithTag(101), let meta = view.viewWithTag(102), let chevron = view.viewWithTag(103) {
                    let textX: CGFloat = 55
                    let textWidth = width - textX - 34
                    name.frame = CGRect(x: textX, y: 11, width: textWidth, height: 17)
                    meta.frame = CGRect(x: textX, y: 30, width: textWidth, height: 14)
                    chevron.frame = CGRect(x: width - 28, y: (Self.fileCardHeight - 20) / 2, width: 20, height: 20)
                }
                y += Self.fileCardHeight + Self.rowGap
            }
        }
    }
}
