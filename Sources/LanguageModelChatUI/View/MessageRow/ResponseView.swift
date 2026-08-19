//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import UIKit

final class ResponseView: MessageListRowView {
    private(set) lazy var markdownView: MarkdownTextView = .init().with {
        $0.throttleInterval = 1 / 60
    }

    var linkTapHandler: ((LinkPayload, NSRange, CGPoint) -> Void)? {
        get { markdownView.linkHandler }
        set { markdownView.linkHandler = newValue }
    }

    var codePreviewHandler: ((String?, NSAttributedString) -> Void)? {
        get { markdownView.codePreviewHandler }
        set { markdownView.codePreviewHandler = newValue }
    }

    init() {
        super.init(frame: .zero)
        configureSubviews()
    }

    /// The hand-off that decides what the prose is drawn in: the render reads
    /// the text view's own theme (TextBuilder.build takes `view.theme`), so a
    /// row that never passes it draws at the default sizes while its height
    /// was measured at the themed ones.
    override func themeDidUpdate() {
        super.themeDidUpdate()
        if markdownView.theme != theme {
            markdownView.theme = theme
        }
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let avatar = AgentAvatarView()

    private func configureSubviews() {
        contentView.addSubview(avatar)
        contentView.addSubview(markdownView)
        // Links open in a sheet over the transcript by default; a host that
        // wants different routing replaces `linkTapHandler` and this is gone.
        markdownView.linkHandler = { [weak self] payload, _, _ in
            self?.openLink(payload)
        }
    }

    private func openLink(_ payload: LinkPayload) {
        let url: URL? = switch payload {
        case let .url(url): url
        // A bare `example.com` in prose carries no scheme; browsing is the
        // only thing a tap on it can mean.
        case let .string(string): URL(string: string.contains("://") ? string : "https://" + string)
        }
        guard let url else { return }

        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let viewController = next as? UIViewController {
                    viewController.present(LinkPreviewController.sheet(for: url), animated: true)
                    return
                }
                responder = next
            }
        } else {
            // mailto:, tel: and friends are not pages; the system owns them.
            UIApplication.shared.open(url)
        }
    }

    /// The mark stands beside the prose exactly as it stands beside a working
    /// block: everything an agent says gets it, and a transcript where only
    /// the tool cards carried it read as two different speakers.
    override func layoutSubviews() {
        super.layoutSubviews()
        avatar.frame = .init(x: 0, y: 2, width: AgentAvatarView.size, height: AgentAvatarView.size)
        markdownView.frame = contentView.bounds.inset(by: .init(top: 0, left: AgentAvatarView.column, bottom: 0, right: 0))
        markdownView.bindContentOffset(from: nearestScrollView)
    }
}
