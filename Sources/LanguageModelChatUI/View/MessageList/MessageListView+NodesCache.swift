//
//  MessageListView+NodesCache.swift
//  LanguageModelChatUI
//
//  Thread-safe cache for preprocessed markdown content.
//

import Foundation
import MarkdownParser
import MarkdownView

extension MessageListView {
    class MarkdownPackageCache {
        private var cachedPackages: [String: MarkdownTextView.PreprocessedContent] = [:]
        /// The message's content version the cached package was built for.
        ///
        /// Keyed on the version rather than on a hash of the text: hashing
        /// every row's content to look the cache up would cost exactly what
        /// the cache exists to save, and the version is bumped on every
        /// content change by the same guarantee the diff relies on.
        private var cachedVersions: [String: Int] = [:]
        private let lock = NSLock()
        private let parser = MarkdownParser()

        /// Everything here was attributed with a theme that is no longer the
        /// one in force. The sizes are baked into the packages at build time,
        /// so a reload that reads the cache back changes nothing at all —
        /// which is how a host that set its own typeface kept seeing the
        /// default one.
        func invalidate() {
            lock.lock()
            cachedPackages.removeAll()
            cachedVersions.removeAll()
            lock.unlock()
        }

        func package(
            for messageRepresentation: MessageRepresentation,
            theme: MarkdownTheme
        ) -> MarkdownTextView.PreprocessedContent {
            let id = messageRepresentation.id
            let version = messageRepresentation.contentVersion

            lock.lock()
            if let cached = cachedPackages[id], cachedVersions[id] == version {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let content = updateCache(content: messageRepresentation.content, theme: theme)

            lock.lock()
            cachedPackages[id] = content
            cachedVersions[id] = version
            lock.unlock()

            return content
        }

        private func updateCache(content: String, theme: MarkdownTheme) -> MarkdownTextView.PreprocessedContent {
            let parseResult = parser.parse(content)
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    MarkdownTextView.PreprocessedContent(parserResult: parseResult, theme: theme)
                }
            }
            return DispatchQueue.main.sync {
                MarkdownTextView.PreprocessedContent(parserResult: parseResult, theme: theme)
            }
        }
    }
}
