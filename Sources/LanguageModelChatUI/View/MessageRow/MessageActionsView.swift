//
//  MessageActionsView.swift
//  LanguageModelChatUI
//

import MarkdownView
import UIKit

/// 30-2: two quiet keys under a finished assistant message — copy and
/// export. Secondary by construction: bare 15pt line icons, no plate, no
/// label, left-aligned with the prose. Copy answers in place — the icon
/// becomes a check with one small word, then returns — because a toast for
/// "it worked" is noise over a conversation.
final class MessageActionsView: MessageListRowView {
    static let rowHeight: CGFloat = 26

    private let copyButton = UIButton(type: .system)
    private let copiedLabel = UILabel()
    private let exportButton = UIButton(type: .system)

    var copyHandler: (() -> Void)?
    var exportHandler: (() -> Void)?

    override var theme: MarkdownTheme {
        didSet { applyStyle() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        copiedLabel.font = .systemFont(ofSize: 11.5)
        copiedLabel.text = String.localized("Copied")
        copiedLabel.alpha = 0

        contentView.addSubview(copyButton)
        contentView.addSubview(copiedLabel)
        contentView.addSubview(exportButton)
        applyStyle()
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A reused row must never wear the previous row's "copied" moment.
    func reset() {
        showingCopied = false
        copiedLabel.alpha = 0
        applyStyle()
        layoutSubviews()
    }

    private var showingCopied = false

    private func applyStyle() {
        let quiet = theme.colors.body.withAlphaComponent(0.42)
        let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if showingCopied {
            copyButton.setImage(UIImage(systemName: "checkmark", withConfiguration: configuration), for: .normal)
            copyButton.tintColor = .systemGreen
        } else {
            copyButton.setImage(UIImage(systemName: "square.on.square", withConfiguration: configuration), for: .normal)
            copyButton.tintColor = quiet
        }
        exportButton.setImage(UIImage(systemName: "photo", withConfiguration: configuration), for: .normal)
        exportButton.tintColor = quiet
        copiedLabel.textColor = .systemGreen
    }

    @objc private func copyTapped() {
        copyHandler?()
        guard !showingCopied else { return }
        showingCopied = true
        applyStyle()
        setNeedsLayout()
        UIView.animate(withDuration: 0.15) { self.copiedLabel.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, showingCopied else { return }
            showingCopied = false
            applyStyle()
            UIView.animate(withDuration: 0.15) { self.copiedLabel.alpha = 0 }
            setNeedsLayout()
        }
    }

    @objc private func exportTapped() {
        exportHandler?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Aligned with the prose column, not the avatar's.
        let leading = AgentAvatarView.column
        let side: CGFloat = 26
        copyButton.frame = CGRect(x: leading - 6, y: 0, width: side, height: Self.rowHeight)
        copiedLabel.sizeToFit()
        copiedLabel.frame = CGRect(
            x: copyButton.frame.maxX + 1,
            y: (Self.rowHeight - copiedLabel.bounds.height) / 2,
            width: copiedLabel.bounds.width,
            height: copiedLabel.bounds.height
        )
        let exportX = showingCopied ? copiedLabel.frame.maxX + 12 : copyButton.frame.maxX + 8
        exportButton.frame = CGRect(x: exportX, y: 0, width: side, height: Self.rowHeight)
    }
}
