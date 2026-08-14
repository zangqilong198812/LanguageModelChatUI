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
        // The one piece of colour in the mark: a prompt waiting for input.
        // The design's blue, not the platform tint — the mark is the product's
        // signature and should not change when a host recolours its controls.
        underline.strokeColor = UIColor(red: 0x2E / 255, green: 0x9B / 255, blue: 0xF5 / 255, alpha: 1).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        chevron.frame = bounds
        underline.frame = bounds

        // The design's own numbers: a 12pt glyph centred in a 22pt tile, its
        // paths drawn in a 44-unit box — a chevron at (12,13)→(21,22)→(12,31)
        // and a cursor line at (26,30)→(33,30). Scaled, not re-invented; the
        // first version of this eyeballed the proportions and looked like a
        // different mark.
        let glyph = bounds.width * (12.0 / 22.0)
        let unit = glyph / 44.0
        let origin = CGPoint(x: (bounds.width - glyph) / 2, y: (bounds.height - glyph) / 2)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            .init(x: origin.x + x * unit, y: origin.y + y * unit)
        }

        let arrow = UIBezierPath()
        arrow.move(to: at(12, 13))
        arrow.addLine(to: at(21, 22))
        arrow.addLine(to: at(12, 31))
        chevron.path = arrow.cgPath
        chevron.lineWidth = 4.4 * unit

        let line = UIBezierPath()
        line.move(to: at(26, 30))
        line.addLine(to: at(33, 30))
        underline.path = line.cgPath
        underline.lineWidth = 4.4 * unit
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        chevron.strokeColor = UIColor.label.cgColor
    }
}
