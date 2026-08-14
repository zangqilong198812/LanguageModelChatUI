//
//  Created by ktiays on 2025/1/31.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import Litext
import MarkdownView
import UIKit

final class UserMessageView: MessageListRowView {
    static let contentPadding: CGFloat = 20
    static let textPadding: CGFloat = 13
    static let verticalTextPadding: CGFloat = 10
    static let maximumIdealWidth: CGFloat = 800
    /// The three round corners and the one that is nearly square. The odd one
    /// is the tail: it points at the person who typed it.
    static let cornerRadius: CGFloat = 17
    static let tailRadius: CGFloat = 5
    static let footnoteHeight: CGFloat = 16

    var text: String? {
        didSet {
            guard let text else {
                attributedText = nil
                return
            }
            // Reversed out of the bubble, which is solid rather than tinted.
            attributedText = .init(string: text, attributes: [
                .font: theme.fonts.body,
                .foregroundColor: UIColor.systemBackground,
            ])
        }
    }

    private var attributedText: NSAttributedString? {
        didSet {
            textView.attributedText = attributedText ?? .init()
        }
    }

    /// Who said it and whether it landed, under the bubble. Nil for a message
    /// whose sender did not say.
    var footnote: String? {
        didSet {
            footnoteLabel.text = footnote
            footnoteLabel.isHidden = footnote == nil
        }
    }

    private let bubbleShape = CAShapeLayer()
    private let footnoteLabel = UILabel()
    private lazy var textView: LTXLabel = .init().with { $0.isSelectable = true }

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Solid, and taken from the label colour so the bubble stays the
        // darkest thing on a light screen and the lightest on a dark one.
        bubbleShape.fillColor = UIColor.label.cgColor
        contentView.layer.insertSublayer(bubbleShape, at: 0)
        contentView.backgroundColor = .clear

        footnoteLabel.textAlignment = .right
        footnoteLabel.textColor = .tertiaryLabel
        footnoteLabel.isHidden = true

        textView.backgroundColor = .clear
        contentView.addSubview(textView)
        addSubview(footnoteLabel)
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        textView.intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let insets = MessageListView.listRowInsets
        let textContainerWidth = Self.availableTextWidth(for: bounds.width - insets.horizontal)
        textView.preferredMaxLayoutWidth = textContainerWidth
        let textSize = textView.intrinsicContentSize
        let contentWidth = ceil(textSize.width) + Self.textPadding * 2
        let footnoteSpace = footnoteLabel.isHidden ? 0 : Self.footnoteHeight
        contentView.frame = .init(
            x: bounds.width - contentWidth - insets.right,
            y: 0,
            width: contentWidth,
            height: bounds.height - insets.bottom - footnoteSpace
        )
        bubbleShape.frame = contentView.bounds
        bubbleShape.path = Self.bubblePath(in: contentView.bounds).cgPath
        textView.frame = contentView.bounds.insetBy(dx: Self.textPadding, dy: Self.verticalTextPadding)

        footnoteLabel.font = theme.fonts.codeInline.withSize(10)
        footnoteLabel.frame = .init(
            x: insets.left,
            y: contentView.frame.maxY + 4,
            width: bounds.width - insets.horizontal,
            height: Self.footnoteHeight - 4
        )
    }

    /// Three rounded corners and a tail. `byRoundingCorners` takes one radius
    /// for every corner it is given, so the shape is walked by hand.
    static func bubblePath(in rect: CGRect) -> UIBezierPath {
        let r = cornerRadius
        let t = tailRadius
        let path = UIBezierPath()
        path.move(to: .init(x: rect.minX + r, y: rect.minY))
        path.addLine(to: .init(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: .init(x: rect.maxX, y: rect.minY + r), controlPoint: .init(x: rect.maxX, y: rect.minY))
        path.addLine(to: .init(x: rect.maxX, y: rect.maxY - t))
        path.addQuadCurve(to: .init(x: rect.maxX - t, y: rect.maxY), controlPoint: .init(x: rect.maxX, y: rect.maxY))
        path.addLine(to: .init(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: .init(x: rect.minX, y: rect.maxY - r), controlPoint: .init(x: rect.minX, y: rect.maxY))
        path.addLine(to: .init(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: .init(x: rect.minX + r, y: rect.minY), controlPoint: .init(x: rect.minX, y: rect.minY))
        path.close()
        return path
    }

    @inlinable
    static func availableContentWidth(for width: CGFloat) -> CGFloat {
        max(0, min(maximumIdealWidth, width - contentPadding * 2))
    }

    @inlinable
    static func availableTextWidth(for width: CGFloat) -> CGFloat {
        availableContentWidth(for: width) - textPadding * 2
    }
}
