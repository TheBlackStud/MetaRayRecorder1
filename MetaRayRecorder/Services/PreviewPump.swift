import UIKit
import QuartzCore
@preconcurrency import MWDATCamera

/// At most one preview image waits for the main thread; recording is independent.
final class PreviewPump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fr.metarayrecorder.preview", qos: .userInitiated)
    private let slot = DispatchSemaphore(value: 1)
    private var lastPreview: Double = 0
    private let enabledLock = NSLock()
    private var enabled = true
    func setEnabled(_ value: Bool) {
        enabledLock.lock()
        enabled = value
        enabledLock.unlock()
    }
    private func isEnabled() -> Bool {
        enabledLock.lock()
        defer { enabledLock.unlock() }
        return enabled
    }
    func receive(_ frame: VideoFrame, deliver: @escaping @MainActor @Sendable (UIImage) -> Void) {
        guard isEnabled(), slot.wait(timeout: .now()) == .success else { return }
        queue.async {
            guard self.isEnabled() else { self.slot.signal(); return }
            let now = CACurrentMediaTime()
            guard now - self.lastPreview >= 1.0 / 12.0, let image = frame.makeUIImage() else {
                self.slot.signal(); return
            }
            self.lastPreview = now
            Task { @MainActor in
                deliver(image)
                self.slot.signal()
            }
        }
    }
}

/// Closing the gate prevents a previous stream from feeding a later recording.
final class StreamFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    func withActiveStream(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        if active { body() }
    }
    func close() {
        lock.lock(); defer { lock.unlock() }
        active = false
    }
}
