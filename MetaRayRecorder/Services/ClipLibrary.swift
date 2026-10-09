import Foundation
import Photos
import AVFoundation

/// Files remain in Documents until the user explicitly deletes them.
enum ClipLibrary {
    static func directory() throws -> URL {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let target = root.appendingPathComponent("Enregistrements", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }
    static func pendingURL() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let folder = root.appendingPathComponent("Pending", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(ClipNames.make())
    }
    static func commit(_ temporary: URL) throws -> URL {
        let target = try directory().appendingPathComponent(temporary.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }
    static func list() throws -> [SavedClip] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .fileSizeKey, .isRegularFileKey]
        return try FileManager.default.contentsOfDirectory(at: directory(),
                  includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .compactMap { url -> SavedClip? in
                guard let info = try? url.resourceValues(forKeys: keys), info.isRegularFile == true else { return nil }
                return SavedClip(url: url, date: info.creationDate ?? .distantPast,
                                 bytes: Int64(info.fileSize ?? 0))
            }.sorted { $0.date > $1.date }
    }
    static func delete(_ clip: SavedClip) throws {
        // Do not allow a UI item or a deep link to delete anything outside this library.
        let parent = clip.url.deletingLastPathComponent().standardizedFileURL
        guard parent == (try directory()).standardizedFileURL else {
            throw RecorderFailure.message("Emplacement de fichier non autorisé.")
        }
        try FileManager.default.removeItem(at: clip.url)
    }
    static func availableBytes() -> Int64? {
        guard let folder = try? directory(),
              let attrs = try? FileManager.default.attributesOfFileSystem(forPath: folder.path),
              let bytes = attrs[.systemFreeSize] as? NSNumber else { return nil }
        return bytes.int64Value
    }
    static func saveToPhotos(_ url: URL) async throws {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw RecorderFailure.message("L’accès à Photos est refusé. Autorisez l’ajout de vidéos dans les réglages iOS. Le fichier reste disponible dans l’application.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
    /// Preserve interrupted files. Only files containing a readable video track are recovered.
    static func recoverReadableFiles() async -> Int {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true),
              let files = try? FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("Pending"), includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for url in files where url.pathExtension == "mp4" {
            let asset = AVURLAsset(url: url)
            guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
                  let duration = try? await asset.load(.duration), duration.seconds > 0 else { continue }
            if (try? commit(url)) != nil { count += 1 }
        }
        return count
    }
}
