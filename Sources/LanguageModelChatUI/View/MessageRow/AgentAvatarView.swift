//
//  AgentAvatarView.swift
//  LanguageModelChatUI
//

import UIKit

/// The mark that stands to the left of everything an agent says.
///
/// Drawn rather than shipped as an image: it is two strokes, and an asset
/// would need a light and a dark copy, a scale for every screen, and a place
/// in a bundle — for a chevron and a line.
final class AgentAvatarView: UIView {
    static let size: CGFloat = 22
    /// What a row leaves clear on the left for it, mark plus gap.
    static let column: CGFloat = 31

    private let chevron = CAShapeLayer()
    private let underline = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous

        for shape in [chevron, underline] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        chevron.strokeColor = UIColor.label.cgColor
        chevron.lineWidth = 2
        // The one piece of colour in the mark: a prompt waiting for input.
        underline.strokeColor = UIColor.tintColor.cgColor
        underline.lineWidth = 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let box = bounds
        chevron.frame = box
        underline.frame = box

        let inset = box.width * 0.28
        let mid = box.midY
        let arrow = UIBezierPath()
        arrow.move(to: .init(x: inset, y: mid - box.height * 0.16))
        arrow.addLine(to: .init(x: box.width * 0.5, y: mid))
        arrow.addLine(to: .init(x: inset, y: mid + box.height * 0.16))
        chevron.path = arrow.cgPath

        let line = UIBezierPath()
        line.move(to: .init(x: box.width * 0.58, y: mid + box.height * 0.16))
        line.addLine(to: .init(x: box.width - inset * 0.7, y: mid + box.height * 0.16))
        underline.path = line.cgPath
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        chevron.strokeColor = UIColor.label.cgColor
        underline.strokeColor = UIColor.tintColor.cgColor
    }
}
