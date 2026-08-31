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

    /// Where the content may not go: under a navigation bar, under a composer.
    ///
    /// Public because a host that embeds the list without the shipped
    /// container has to say this itself — with it at zero the last row sits
    /// half under whatever the app lays over the bottom.
    public var contentSafeAreaInsets: UIEdgeInsets = .zero {
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
        didSet {
            // The cache holds content attributed with the old theme, and its
            // key does not know a theme exists — reloading without dropping it
            // reads the old sizes straight back.
            markdownPackageCache.invalidate()
            listView.reloadData()
        }
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

    /// Public for hosts that drive the wait from their own state: Runline's
    /// transcript shows "thinking" as a trailing row of this list rather than
    /// an overlay floating above it.
    public func loading(with message: String = .init()) {
        loadingState.send(message)
    }

    /// The same wait, wearing the shape of the work: an SF Symbol name drawn
    /// ahead of the words. Hosts that have nothing to draw keep calling
    /// `loading(with:)` and get the row exactly as it was.
    public func loading(with message: String, symbol: String?) {
        guard let symbol, !symbol.isEmpty else {
            loadingState.send(message)
            return
        }
        loadingState.send(Self.packSymbol(symbol, into: message))
    }

    /// The symbol rides inside the string so the whole pipeline — the entry
    /// enum, its identity, its height — keeps working untouched. The unit
    /// separator never appears in a sentence, and readers of the old shape
    /// see a plain message.
    static let symbolSeparator = "\u{001F}"

    static func packSymbol(_ symbol: String, into message: String) -> String {
        symbol + symbolSeparator + message
    }

    static func unpackSymbol(_ raw: String) -> (symbol: String?, message: String) {
        guard let range = raw.range(of: symbolSeparator) else { return (nil, raw) }
        return (String(raw[raw.startIndex ..< range.lowerBound]), String(raw[range.upperBound...]))
    }

    public func stopLoading() {
        loadingState.send(nil)
    }

    /// For the host's own sends: a message the user just wrote must be seen
    /// leaving, wherever the list happened to be scrolled. Re-arms the
    /// bottom-following the reader may have broken by scrolling up.
    public func scrollToBottom(animated: Bool = true) {
        isAutoScrollingToBottom = true
        // ListScrollView drives its own display-link animation and *asserts*
        // on `setContentOffset(_:animated: true)` — the UIKit-animated path
        // crashed debug builds the moment a send scrolled the list. Animated
        // means its spring, not UIKit's.
        if animated {
            listView.scroll(to: .init(x: 0, y: listView.maximumContentOffset.y))
        } else {
            listView.setContentOffset(.init(x: 0, y: listView.maximumContentOffset.y), animated: false)
        }
        settleAtBottom()
    }

    /// One more pass after layout lands. A scroll target pinned in the same
    /// runloop as a snapshot rides on the *old* content size — the send's echo
    /// and the thinking row have not been measured yet — so the spring parked
    /// one row short of the actual bottom.
    private func settleAtBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAutoScrollingToBottom else { return }
            let target = self.listView.maximumContentOffset
            if abs(self.listView.contentOffset.y - target.y) > self.autoScrollTolerance {
                self.listView.scroll(to: target)
            }
            self.reportBottomState()
        }
    }

    /// A localhost card was tapped. The list only detects and draws the
    /// mention; opening the tunnel is the host app's business.
    public var onLocalPreviewOpen: ((LocalPreviewRecord) -> Void)?
    /// A delivered file was tapped; opening, sharing and keeping are the
    /// host app's to decide.
    public var onDeliverableOpen: ((DeliverableItem) -> Void)?
    /// Thumbnail bytes for a delivered image, if the host app has them yet.
    /// Nil draws the quiet placeholder; refresh the row to fill it in.
    public var deliverableThumbProvider: ((DeliverableItem) -> UIImage?)?

    /// 30-2's gate: whether an assistant message offers copy/export in its
    /// long-press menu. Nil (the default) offers none — hosts opt in and
    /// decide "done being written" themselves, since only they know the
    /// turn's state.
    public var messageActionsProvider: ((String) -> Bool)?
    /// Copy chosen from a message's long-press menu; the host owns the
    /// pasteboard.
    public var onMessageCopy: ((String) -> Void)?
    /// Export chosen from a message's long-press menu — the host opens its
    /// export sheet.
    public var onMessageExport: ((String) -> Void)?
    /// Add-to-memory chosen from a message's long-press menu — the host owns
    /// what a memory is; nil hides the item from the menu.
    public var onMessageMemorize: ((String) -> Void)?
    /// What the localhost card calls the machine — "在 MacBook Pro 上". The
    /// list knows messages, not machines, so the name is handed in.
    public var localPreviewMachineName: String?

    /// Reports the reader leaving or returning to the bottom, for a host that
    /// shows its own "jump to newest" affordance. Fired on scroll and after
    /// content changes, deduplicated to transitions.
    public var onBottomStateChange: ((Bool) -> Void)?
    private var lastReportedBottom = true

    /// Reports the reader reaching or leaving the top, for a host that loads
    /// older history on approach. Deduplicated to transitions, so a prepend
    /// that leaves the reader at the seam does not cascade into loading the
    /// whole archive — the next page waits for the reader to move again.
    public var onTopStateChange: ((Bool) -> Void)?
    private var lastReportedTop = false
    private let topAffordanceTolerance: CGFloat = 120
    /// Top is only reportable once the reader has actually been at the
    /// bottom: a freshly opened list sits at the top while its first page
    /// lays out and scrolls down, and reporting that as "reached the top"
    /// made hosts cascade-load the whole archive on open.
    private var hasVisitedBottom = false

    /// Roomier than the auto-scroll tolerance on purpose: the affordance is
    /// for a reader who left, not one a hairline off the edge.
    private let bottomAffordanceTolerance: CGFloat = 80

    private func reportBottomState() {
        let near = isContentOffsetNearBottom(tolerance: bottomAffordanceTolerance)
        if near != lastReportedBottom {
            lastReportedBottom = near
            onBottomStateChange?(near)
        }
        if near { hasVisitedBottom = true }
        let nearTop = hasVisitedBottom && listView.contentOffset.y <= topAffordanceTolerance
        if nearTop != lastReportedTop {
            lastReportedTop = nearTop
            onTopStateChange?(nearTop)
        }
    }

    func updateList() {
        let entries = entries(from: session.messages)
        dataSource.applySnapshot(using: entries, animatingDifferences: false)
    }

    /// Derived entries for the last message set, with the signature that
    /// produced them.
    ///
    /// A host pokes the list for reasons that do not touch the transcript —
    /// the thinking row's clock, a reload after a send — and re-deriving
    /// every row of a long conversation for those is the waste this cache
    /// removes. The signature is per-message content version plus footnote
    /// (the footnote is the app's own delivery state, which never bumps a
    /// version), so an in-place rewrite still rebuilds — exactly the rows
    /// that must.
    private var lastEntries: [Entry]?
    private var lastSignature: [String: MessageSignature]?

    private struct MessageSignature: Equatable {
        let contentVersion: Int
        let footnote: String?
    }

    private func signature(of messages: [ConversationMessage]) -> [String: MessageSignature] {
        var result: [String: MessageSignature] = [:]
        result.reserveCapacity(messages.count)
        for message in messages {
            result[message.id] = .init(
                contentVersion: message.contentVersion,
                footnote: message.metadata["footnote"]
            )
        }
        return result
    }

    private func entriesIfUnchanged(_ messages: [ConversationMessage]) -> [Entry]? {
        guard let lastEntries, let lastSignature else { return nil }
        return signature(of: messages) == lastSignature ? lastEntries : nil
    }

    func updateFromUpstreamPublisher(_ messages: [ConversationMessage], _ scrolling: Bool, isLoading: String?) {
        var entries = entriesIfUnchanged(messages) ?? entries(from: messages)
        lastEntries = entries
        lastSignature = signature(of: messages)

        for entry in entries {
            switch entry {
            case let .responseContent(_, messageRepresentation):
                _ = markdownPackageCache.package(for: messageRepresentation, theme: theme)
            default: break
            }
        }

        if let isLoading { entries.append(.activityReporting(isLoading)) }

        let shouldScrolling = scrolling && isAutoScrollingToBottom

        // A list filling for the first time is a first load, whoever asked
        // first. A host reloads once before its messages have arrived, and
        // that empty pass used to consume this path — so the real content came
        // second and rode in on the animated one, scrolling visibly to the
        // bottom of a screen the reader had only just opened.
        let isFilling = entryCount == 0 && !entries.isEmpty
        entryCount = entries.count
        if isFirstLoad || isFilling || alpha == 0 {
            isFirstLoad = false
            dataSource.applySnapshot(using: entries, animatingDifferences: false)
            listView.setContentOffset(.init(x: 0, y: listView.maximumContentOffset.y), animated: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                UIView.animate(withDuration: 0.25) { self.alpha = 1 }
            }
        } else {
            // Never animated. ListViewKit's animated apply forces a layout in
            // its completion using the *previous* layout cache's row indices;
            // a snapshot that shrank in the meantime — the thinking row
            // retiring as the reply lands — makes that lookup run off the end
            // of the new data source and trip its assertion. The row-level
            // reconfigure already carries streaming updates without animation,
            // so the insert animation is all this ever bought.
            dataSource.applySnapshot(using: entries, animatingDifferences: false)
            if shouldScrolling {
                listView.scroll(to: listView.maximumContentOffset)
                // The offset above was pinned against the pre-snapshot content
                // size; the rows just applied land a frame later.
                settleAtBottom()
            } else {
                reportBottomState()
            }
        }
    }
}

extension MessageListView: UIScrollViewDelegate {
    public func scrollViewDidScroll(_: UIScrollView) {
        reportBottomState()
    }

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
