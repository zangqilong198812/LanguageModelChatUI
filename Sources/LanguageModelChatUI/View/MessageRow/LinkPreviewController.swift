//
//  LinkPreviewController.swift
//  LanguageModelChatUI
//

import UIKit
import WebKit

/// The in-app landing spot for a link inside a message. A transcript is a
/// working surface: leaving the app to look at a page the agent mentioned
/// breaks the loop the user is in, so the page comes to them instead —
/// a sheet they can flick away to get back to the conversation.
///
/// Public because the host has links of its own — a feedback page in
/// settings — and two webview chromes in one app would read as two apps.
public final class LinkPreviewController: UIViewController {
    private let initialURL: URL
    private let webView: WKWebView
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private var observations: [NSKeyValueObservation] = []

    init(url: URL) {
        initialURL = url
        let configuration = WKWebViewConfiguration()
        // Inline playback: a video that force-fullscreens fights the sheet.
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Wraps the preview in the navigation chrome it needs; present this.
    public static func sheet(for url: URL) -> UIViewController {
        let navigation = UINavigationController(rootViewController: LinkPreviewController(url: url))
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        return navigation
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.share() }
        )
        // The host stands in until the page yields a title, so the bar is
        // never blank while a slow page loads.
        navigationItem.title = initialURL.host()

        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressBar)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            progressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                guard let title = webView.title, !title.isEmpty else { return }
                self?.navigationItem.title = title
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                guard let self else { return }
                let progress = Float(webView.estimatedProgress)
                progressBar.progress = progress
                progressBar.isHidden = progress >= 1
            },
        ]

        webView.load(URLRequest(url: initialURL))
    }

    private func share() {
        // Sharing what is on screen now, not what was tapped: after in-page
        // navigation the tapped URL is history.
        let url = webView.url ?? initialURL
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activity, animated: true)
    }
}

extension LinkPreviewController: WKUIDelegate {
    /// A `target="_blank"` link expects a new window this sheet does not
    /// have; loading it in place is the only sensible reading of that intent.
    public func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
