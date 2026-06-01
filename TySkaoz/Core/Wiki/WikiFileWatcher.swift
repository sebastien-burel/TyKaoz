import Foundation
import CoreServices

/// Watches `wiki/` for filesystem changes (Obsidian saves, manual edits,
/// `write_wiki_page` from the agent) and triggers a reindex through the
/// `WikiContext`'s indexer. Coalesces bursts of writes via a debounce
/// window so a rapid sequence of saves results in a single reindex.
@MainActor
final class WikiFileWatcher {
    private let context: WikiContext
    private let debounceMs: UInt64
    private var stream: FSEventStreamRef?
    private var pendingTask: Task<Void, Never>?
    private let eventQueue = DispatchQueue(
        label: "net.haruni.tykaoz.wiki.watcher",
        qos: .utility
    )

    /// Set after each reindex completes — tests `await` on this to know
    /// when work has settled. Production code doesn't need it.
    private(set) var lastIndexReport: IndexReport?

    init(context: WikiContext, debounceMs: UInt64 = 500) {
        self.context = context
        self.debounceMs = debounceMs
    }

    /// Starts the FSEvents stream. No-op if already started. Path passed
    /// to FSEvents is the `wiki/` directory so external edits in Obsidian
    /// or via the CLI trigger reindexing.
    func start() throws {
        guard stream == nil else { return }
        let info = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var ctx = FSEventStreamContext(
            version: 0, info: info, retain: nil, release: nil, copyDescription: nil
        )
        // FSEvents requires the canonical path — macOS returns paths
        // like /var/folders/... which are symlinks into /private/var,
        // and the symlinked form silently never fires callbacks.
        let canonical = context.wikiRoot.resolvingSymlinksInPath().path
        guard let s = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<WikiFileWatcher>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in watcher.notify() }
            },
            &ctx,
            [canonical] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.0,
            UInt32(
                kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagIgnoreSelf
                | kFSEventStreamCreateFlagNoDefer
            )
        ) else {
            throw WikiFileWatcherError.streamCreationFailed
        }
        FSEventStreamSetDispatchQueue(s, eventQueue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            throw WikiFileWatcherError.streamStartFailed
        }
        self.stream = s
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        pendingTask?.cancel()
        pendingTask = nil
    }

    /// Each call schedules a reindex `debounceMs` from now. A second
    /// `notify()` inside the window cancels the first — only the last
    /// scheduled reindex actually runs. Public for testability; the
    /// FSEvents callback above is the only production caller.
    func notify() {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(Int(self.debounceMs)))
            guard !Task.isCancelled else { return }
            let indexer = self.context.makeIndexer()
            if let report = try? await indexer.reindexAll() {
                self.lastIndexReport = report
            }
        }
    }

    /// Waits for any in-flight debounced work to settle. Test affordance.
    func waitForSettled() async {
        await pendingTask?.value
    }
}

enum WikiFileWatcherError: Error, LocalizedError {
    case streamCreationFailed
    case streamStartFailed

    var errorDescription: String? {
        switch self {
        case .streamCreationFailed: return "FSEvents : création du flux échouée."
        case .streamStartFailed:    return "FSEvents : démarrage du flux échoué."
        }
    }
}
