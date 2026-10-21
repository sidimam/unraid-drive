#if os(macOS)
import Foundation
import CoreServices

/// Watches a folder tree with FSEvents and calls back once things settle (debounced), so a
/// continuous sync pair runs shortly after the user stops touching files.
final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private var pending: DispatchWorkItem?
    private let debounce: TimeInterval

    init(url: URL, debounce: TimeInterval = 3, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounce = debounce
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    private func fire() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: w)
    }

    deinit {
        pending?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
#endif
