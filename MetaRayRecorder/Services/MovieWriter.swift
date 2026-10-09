import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import QuartzCore

/// Serializes all AVAssetWriter operations. The bounded queues prevent long recordings
/// from accumulating video frames in RAM when the encoder cannot keep up.
final class MovieWriter: @unchecked Sendable {
    private struct Sample: @unchecked Sendable { let value: CMSampleBuffer }
    private struct PCM: @unchecked Sendable { let value: AVAudioPCMBuffer }
    private let queue = DispatchQueue(label: "fr.metarayrecorder.writer", qos: .userInitiated)
    private let videoSlots = DispatchSemaphore(value: 3)
    private let audioSlots = DispatchSemaphore(value: 12)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var fileURL: URL?
    private var timeline = RecordingTimeline()
    private var accepting = false
    private var finishing = false
    private var hasFrames = false
    private var outputWidth = 0
    private var outputHeight = 0
    private var fps = 24
    private var lastAudioTime: Double = -1
    private var firstError: Error?
    private var onFirstFrame: (@Sendable () -> Void)?
    private var onFailure: (@Sendable (String) -> Void)?

    func prepare(url: URL, quality: RecordingQuality, fps: Int, audio: Bool,
                 onFirstFrame: @escaping @Sendable () -> Void,
                 onFailure: @escaping @Sendable (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard self.writer == nil, !self.finishing else {
                        throw RecorderFailure.message("La vidéo précédente est encore en cours de sauvegarde.")
                    }
                    let output = try AVAssetWriter(outputURL: url, fileType: .mp4)
                    let settings: [String: Any] = [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: quality.width,
                        AVVideoHeightKey: quality.height,
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: quality.bitRate,
                            AVVideoExpectedSourceFrameRateKey: fps,
                            AVVideoMaxKeyFrameIntervalKey: fps * 2,
                            AVVideoAllowFrameReorderingKey: false
                        ]
                    ]
                    let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                    video.expectsMediaDataInRealTime = true
                    guard output.canAdd(video) else { throw RecorderFailure.message("Encodage H.264 indisponible.") }
                    output.add(video)
                    let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video,
                        sourcePixelBufferAttributes: [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                            kCVPixelBufferWidthKey as String: quality.width,
                            kCVPixelBufferHeightKey as String: quality.height,
                            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                        ])
                    var sound: AVAssetWriterInput?
                    if audio {
                        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                            AVFormatIDKey: kAudioFormatMPEG4AAC,
                            AVSampleRateKey: 44_100,
                            AVNumberOfChannelsKey: 1,
                            AVEncoderBitRateKey: 64_000
                        ])
                        input.expectsMediaDataInRealTime = true
                        guard output.canAdd(input) else { throw RecorderFailure.message("Encodage audio AAC indisponible.") }
                        output.add(input)
                        sound = input
                    }
                    // A fragmented MP4 improves the chance of recovering an interrupted file.
                    // It is not a guarantee against power loss or forced termination.
                    output.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
                    guard output.startWriting() else { throw output.error ?? RecorderFailure.message("Impossible de créer le fichier vidéo.") }
                    output.startSession(atSourceTime: .zero)
                    self.writer = output
                    self.videoInput = video
                    self.audioInput = sound
                    self.adaptor = pixels
                    self.fileURL = url
                    self.timeline = RecordingTimeline()
                    self.outputWidth = quality.width
                    self.outputHeight = quality.height
                    self.fps = fps
                    self.hasFrames = false
                    self.lastAudioTime = -1
                    self.firstError = nil
                    self.onFirstFrame = onFirstFrame
                    self.onFailure = onFailure
                    self.accepting = true
                    continuation.resume()
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer, hostTime: Double) {
        guard videoSlots.wait(timeout: .now()) == .success else { return }
        let sample = Sample(value: sampleBuffer)
        queue.async {
            defer { self.videoSlots.signal() }
            guard self.accepting, !self.finishing,
                  let writer = self.writer, let input = self.videoInput, let adaptor = self.adaptor else { return }
            guard writer.status == .writing else { self.fail(writer.error ?? RecorderFailure.message("L’encodeur vidéo s’est arrêté.")); return }
            guard input.isReadyForMoreMediaData else { return }
            guard let source = CMSampleBufferGetImageBuffer(sample.value) else {
                self.fail(RecorderFailure.message("Le flux reçu n’est pas un flux vidéo décodé. Vérifiez la version du SDK Meta.")); return
            }
            guard let pool = adaptor.pixelBufferPool else {
                self.fail(RecorderFailure.message("Mémoire de l’encodeur indisponible.")); return
            }
            var destination: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess,
                  let destination else { return }
            let image = CIImage(cvPixelBuffer: source)
            guard image.extent.width > 0, image.extent.height > 0 else { return }
            let w = CGFloat(self.outputWidth), h = CGFloat(self.outputHeight)
            let factor = min(w / image.extent.width, h / image.extent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            let fitted = scaled.transformed(by: CGAffineTransform(
                translationX: (w - scaled.extent.width) / 2 - scaled.extent.minX,
                y: (h - scaled.extent.height) / 2 - scaled.extent.minY))
            let bounds = CGRect(x: 0, y: 0, width: w, height: h)
            let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: bounds)
            self.context.render(fitted.composited(over: background), to: destination,
                                bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
            guard let seconds = self.timeline.videoTime(hostTime: hostTime) else { return }
            let time = CMTime(seconds: seconds, preferredTimescale: 60_000)
            guard adaptor.append(destination, withPresentationTime: time) else {
                self.fail(writer.error ?? RecorderFailure.message("Échec d’écriture d’une image vidéo.")); return
            }
            if !self.hasFrames {
                self.hasFrames = true
                self.onFirstFrame?()
            }
        }
    }

    /// The caller supplies its own immutable copy of the PCM buffer.
    func appendAudio(_ buffer: AVAudioPCMBuffer, hostTime: Double) {
        guard audioSlots.wait(timeout: .now()) == .success else { return }
        let packet = PCM(value: buffer)
        queue.async {
            defer { self.audioSlots.signal() }
            guard self.accepting, !self.finishing, self.hasFrames,
                  let input = self.audioInput, input.isReadyForMoreMediaData,
                  let writer = self.writer, writer.status == .writing,
                  let seconds = self.timeline.audioTime(hostTime: hostTime), seconds > self.lastAudioTime else { return }
            do {
                let sample = try Self.audioSample(packet.value, seconds: seconds)
                if input.append(sample) { self.lastAudioTime = seconds }
                else { self.fail(writer.error ?? RecorderFailure.message("Échec d’écriture de la piste audio.")) }
            } catch { self.fail(error) }
        }
    }

    private static func audioSample(_ buffer: AVAudioPCMBuffer, seconds: Double) throws -> CMSampleBuffer {
        var description: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            asbd: buffer.format.streamDescription, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard formatStatus == noErr, let description else { throw RecorderFailure.message("Format du microphone non reconnu.") }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(buffer.format.sampleRate)),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 60_000),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil,
            dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: description, sampleCount: Int(buffer.frameLength),
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
        guard sampleStatus == noErr, let sample else { throw RecorderFailure.message("Impossible de préparer les échantillons audio.") }
        let dataStatus = CMSampleBufferSetDataBufferFromAudioBufferList(sample,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, bufferList: buffer.audioBufferList)
        guard dataStatus == noErr else { throw RecorderFailure.message("Impossible de copier les échantillons audio.") }
        return sample
    }

    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            queue.async {
                guard !self.finishing, let writer = self.writer, let url = self.fileURL else {
                    continuation.resume(throwing: RecorderFailure.message("Aucun enregistrement à sauvegarder.")); return
                }
                self.accepting = false
                self.finishing = true
                guard self.hasFrames else {
                    writer.cancelWriting()
                    self.reset()
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(throwing: RecorderFailure.message("Aucune image reçue pendant l’enregistrement.")); return
                }
                if writer.status == .writing {
                    let end = max(0, self.timeline.lastVideo) + 1.0 / Double(self.fps)
                    writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 60_000))
                    self.videoInput?.markAsFinished()
                    self.audioInput?.markAsFinished()
                    writer.finishWriting {
                        self.queue.async {
                            let error = writer.error ?? self.firstError
                            let succeeded = writer.status == .completed
                            self.reset()
                            if succeeded { continuation.resume(returning: url) }
                            else { continuation.resume(throwing: error ?? RecorderFailure.message("Le fichier n’a pas pu être finalisé. Un fichier récupérable sera recherché au prochain lancement.")) }
                        }
                    }
                } else {
                    let error = writer.error ?? self.firstError ?? RecorderFailure.message("L’enregistrement a été interrompu par l’encodeur.")
                    self.reset()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fail(_ error: Error) {
        guard firstError == nil else { return }
        firstError = error
        accepting = false
        onFailure?(error.localizedDescription)
    }
    private func reset() {
        writer = nil; videoInput = nil; audioInput = nil; adaptor = nil; fileURL = nil
        accepting = false; finishing = false; hasFrames = false
        onFirstFrame = nil; onFailure = nil; firstError = nil
    }
}
