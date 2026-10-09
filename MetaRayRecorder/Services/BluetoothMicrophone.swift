import Foundation
@preconcurrency import AVFoundation
import QuartzCore

struct MicrophoneRoute: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Only the explicitly selected Bluetooth HFP input is accepted. The iPhone
/// microphone is never a fallback, including after a route change.
@MainActor
final class BluetoothMicrophone {
    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []
    private var selectedUID: String?

    private func configure() throws {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 26.0, *) {
            try session.setCategory(.playAndRecord, mode: .videoRecording,
                                    options: [.allowBluetoothHFP, .mixWithOthers])
        } else {
            try session.setCategory(.playAndRecord, mode: .videoRecording,
                                    options: [.allowBluetooth, .mixWithOthers])
        }
        try session.setActive(true)
    }

    func routes() async throws -> [MicrophoneRoute] {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderFailure.message("Le microphone est refusé. Autorisez-le dans Réglages, ou désactivez le son dans MetaRay Recorder.")
        }
        try configure()
        defer { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        try await Task.sleep(nanoseconds: 250_000_000)
        return (AVAudioSession.sharedInstance().availableInputs ?? [])
            .filter { $0.portType == .bluetoothHFP }
            .map { MicrophoneRoute(id: $0.uid, name: $0.portName) }
    }

    func start(uid: String, onBuffer: @escaping @Sendable (AVAudioPCMBuffer, Double) -> Void,
               onInterrupted: @escaping @MainActor @Sendable (String) -> Void) async throws {
        stop()
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderFailure.message("Autorisez le microphone dans les réglages iOS, ou filmez sans son.")
        }
        try configure()
        selectedUID = uid // Ensure stop() also cleans up a cancelled or failed setup.
        let session = AVAudioSession.sharedInstance()
        guard let input = session.availableInputs?.first(where: { $0.uid == uid && $0.portType == .bluetoothHFP }) else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderFailure.message("Le microphone Bluetooth choisi n’est plus disponible. Connectez les Ray-Ban et recherchez les micros à nouveau.")
        }
        try session.setPreferredInput(input)
        for _ in 0..<12 {
            if session.currentRoute.inputs.contains(where: { $0.uid == uid && $0.portType == .bluetoothHFP }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard session.currentRoute.inputs.contains(where: { $0.uid == uid && $0.portType == .bluetoothHFP }) else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderFailure.message("iOS n’a pas activé le microphone des lunettes. Déconnectez les autres casques puis réessayez.")
        }
        let newEngine = AVAudioEngine()
        let node = newEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderFailure.message("Le microphone ne fournit pas de format audio valide.")
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, audioTime in
            // Recheck on the audio callback: no phone samples can slip through before
            // the main-thread route-change notification is delivered.
            guard AVAudioSession.sharedInstance().currentRoute.inputs.contains(where: {
                $0.uid == uid && $0.portType == .bluetoothHFP
            }), let copy = Self.copy(buffer) else { return }
            let host = audioTime.isHostTimeValid
                ? AVAudioTime.seconds(forHostTime: audioTime.hostTime)
                : CACurrentMediaTime() - Double(buffer.frameLength) / format.sampleRate
            onBuffer(copy, host)
        }
        engine = newEngine
        selectedUID = uid
        do { newEngine.prepare(); try newEngine.start() }
        catch { stop(); throw error }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: session, queue: .main) { _ in
            Task { @MainActor in
                if !session.currentRoute.inputs.contains(where: { $0.uid == uid && $0.portType == .bluetoothHFP }) {
                    onInterrupted("Microphone Bluetooth déconnecté : arrêt de l’enregistrement.")
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: session, queue: .main) { note in
            guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  value == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in onInterrupted("Audio interrompu par iOS : arrêt de l’enregistrement.") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: session, queue: .main) { _ in
            Task { @MainActor in onInterrupted("Le service audio iOS a redémarré : arrêt de l’enregistrement.") }
        })
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            self.engine = nil
        }
        if selectedUID != nil {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        selectedUID = nil
    }

    private nonisolated static func copy(_ original: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: original.format, frameCapacity: original.frameLength) else { return nil }
        buffer.frameLength = original.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: original.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        for index in 0..<source.count {
            guard let from = source[index].mData, let to = destination[index].mData else { return nil }
            let length = min(Int(source[index].mDataByteSize), Int(destination[index].mDataByteSize))
            memcpy(to, from, length)
        }
        return buffer
    }
}
