import Foundation

/// Values used by the UI, the encoder and the build's platform-independent checks.
enum RecordingQuality: String, CaseIterable, Identifiable, Codable {
    case economy, balanced, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .economy: return "Économie · 360 × 640"
        case .balanced: return "Équilibré · 504 × 896"
        case .high: return "Haute · 720 × 1280"
        }
    }
    var width: Int { switch self { case .economy: return 360; case .balanced: return 504; case .high: return 720 } }
    var height: Int { switch self { case .economy: return 640; case .balanced: return 896; case .high: return 1280 } }
    var bitRate: Int { switch self { case .economy: return 1_000_000; case .balanced: return 2_000_000; case .high: return 4_000_000 } }
}

enum RecorderFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

enum ClipNames {
    static func make(date: Date = Date(), id: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "MetaRay_\(formatter.string(from: date))_\(id.uuidString.lowercased()).mp4"
    }
    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00:00" }
        let value = Int(min(max(seconds, 0), 359_999))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
}

/// Monotonic host-clock timestamps. No artificial 3/5-minute cutoff is introduced.
struct RecordingTimeline {
    private(set) var origin: TimeInterval?
    private(set) var lastVideo: TimeInterval = -1
    mutating func videoTime(hostTime: TimeInterval) -> TimeInterval? {
        guard hostTime.isFinite else { return nil }
        if origin == nil { origin = hostTime }
        guard let origin else { return nil }
        let elapsed = hostTime - origin
        guard elapsed >= 0, elapsed > lastVideo else { return nil }
        lastVideo = elapsed
        return elapsed
    }
    func audioTime(hostTime: TimeInterval) -> TimeInterval? {
        guard let origin, hostTime.isFinite, hostTime >= origin else { return nil }
        return hostTime - origin
    }
}

struct SavedClip: Identifiable, Equatable {
    let url: URL
    let date: Date
    let bytes: Int64
    var id: String { url.lastPathComponent }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

/// Suivi du dernier échantillon réellement reçu, même écran éteint.
/// Séparé de l’aperçu SwiftUI : aucun rafraîchissement d’interface nécessaire.
final class StreamActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var timestamp: TimeInterval?

    func mark(time: TimeInterval) {
        guard time.isFinite else { return }
        lock.lock()
        if let previous = timestamp {
            if time >= previous { timestamp = time }
        } else {
            timestamp = time
        }
        lock.unlock()
    }

    func lastFrameTime() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return timestamp
    }

    func reset() {
        lock.lock()
        timestamp = nil
        lock.unlock()
    }
}
