//
//  MessageListView.swift
//  LanguageModelChatUI
//
//  High-performance message list using ListViewKit.
//  Adapted from FlowDown's MessageListView.
//

import Combine
import ListViewKit
import Litext
import MarkdownView
import SnapKit
import UIKit

public final class MessageListView: UIView {
    private lazy var listView: ListViewKit.ListView = .init()

    public var contentSize: CGSize {
        listView.contentSize
    }

    lazy var dataSource: ListViewDiffableDataSource<Entry> = .init(listView: listView)

    private var entryCount = 0
    private var isFirstLoad: Bool = true
    private let autoScrollTolerance: CGFloat = 2

    /// The conversation this list draws.
    ///
    /// Public so a host can supply one it fills itself. Runline's transcript
    /// arrives from a relay, and setting this is the whole of what it needs
    /// from the renderer.
    public var session: ConversationSession! {
        didSet {
            isFirstLoad = true
            alpha = 0
            sessionScopedCancellables.forEach { $0.cancel() }
            sessionScopedCancellables.removeAll()
            Publishers.CombineLatest(
                session.messagesDidChange,
                loadingState
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v1, v2 in
                guard let self else { return }
                updateFromUpstreamPublisher(v1.0, v1.1, isLoading: v2)
            }
            .store(in: &sessionScopedCancellables)
            session.userDidSendMessage
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.isAutoScrollingToBottom = true
                }
                .store(in: &sessionScopedCancellables)
        }
    }

    private var isAutoScrollingToBottom: Bool = true
    private var sessionScopedCancellables: Set<AnyCancellable> = .init()
    let loadingState = CurrentValueSubject<String?, Never>(nil)

    var contentSafeAreaInsets: UIEdgeInsets = .zero {
        didSet { setNeedsLayout() }
    }

    static let listRowInsets: UIEdgeInsets = .init(top: 0, left: 20, bottom: 16, right: 20)

    /// The typeface and colours everything in the list is drawn in.
    ///
    /// Public so a host app can hand over its own. A font registered by the
    /// app is registered for the whole process, so this needs the font object
    /// and not the file — the package bundling a second copy of a typeface the
    /// app already ships would be pure weight.
    public var theme: MarkdownTheme = .default {
        didSet { listView.reloadData() }
    }

    private(set) lazy var labelForSizeCalculation: LTXLabel = .init()
    private(set) lazy var markdownViewForSizeCalculation: MarkdownTextView = .init()
    private(set) lazy var markdownPackageCache: MarkdownPackageCache = .init()

    /// Constructible from outside the package.
    ///
    /// Runline drives this list from a relay rather than from a
    /// `ConversationSession` running inference, so it builds the view itself
    /// instead of going through `ChatViewController` — which owns an input bar
    /// and a session manager an app holding no model has no use for.
    public init() {
        super.init(frame: .zero)

        listView.delegate = self
        listView.adapter = self
        listView.alwaysBounceVertical = true
        listView.alwaysBounceHorizontal = false
        listView.contentInsetAdjustmentBehavior = .never
        listView.showsVerticalScrollIndicator = false
        listView.showsHorizontalScrollIndicator = false
        addSubview(listView)
        listView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        listView.gestureRecognizers?.forEach {
            guard $0 is UIPanGestureRecognizer else { return }
            $0.cancelsTouchesInView = false
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override public func layoutSubviews() {
        let wasNearBottom = isContentOffsetNearBottom()
        super.layoutSubviews()

        listView.contentInset = contentSafeAreaInsets

        if isAutoScrollingToBottom || wasNearBottom {
            let targetOffset = listView.maximumContentOffset
            if abs(listView.contentOffset.y - targetOffset.y) > autoScrollTolerance {
                listView.scroll(to: targetOffset)
            }
            if wasNearBottom {
                isAutoScrollingToBottom = true
            }
        }
    }

    private func updateAutoScrolling() {
        if isContentOffsetNearBottom() {
            isAutoScrollingToBottom = true
        }
    }

    private func isContentOffsetNearBottom(tolerance: CGFloat? = nil) -> Bool {
        let tolerance = tolerance ?? autoScrollTolerance
        return abs(listView.contentOffset.y - listView.maximumContentOffset.y) <= tolerance
    }

    func loading(with message: String = .init()) {
        loadingState.send(message)
    }

    func stopLoading() {
        loadingState.send(nil)
    }

    func updateList() {
        let entries = entries(from: session.messages)
        dataSource.applySnapshot(using: entries, animatingDifferences: false)
    }

    func updateFromUpstreamPublisher(_ messages: [ConversationMessage], _ scrolling: Bool, isLoading: String?) {
        var entries = entries(from: messages)

        for entry in entries {
            switch entry {
            case let .responseContent(_, messageRepresentation):
                _ = markdownPackageCache.package(for: messageRepresentation, theme: theme)
            default: break
            }
        }

        if let isLoading { entries.append(.activityReporting(isLoading)) }

        let shouldScrolling = scrolling && isAutoScrollingToBottom

        entryCount = entries.count
        if isFirstLoad || alpha == 0 {
            isFirstLoad = false
            dataSource.applySnapshot(using: entries, animatingDifferences: false)
            listView.setContentOffset(.init(x: 0, y: listView.maximumContentOffset.y), animated: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                UIView.animate(withDuration: 0.25) { self.alpha = 1 }
            }
        } else {
            dataSource.applySnapshot(using: entries, animatingDifferences: true)
            if shouldScrolling {
                listView.scroll(to: listView.maximumContentOffset)
            }
        }
    }
}

extension MessageListView: UIScrollViewDelegate {
    public func scrollViewWillBeginDragging(_: UIScrollView) {
        isAutoScrollingToBottom = false
    }

    public func scrollViewDidEndDecelerating(_: UIScrollView) {
        updateAutoScrolling()
    }

    public func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateAutoScrolling()
        }
    }
}
