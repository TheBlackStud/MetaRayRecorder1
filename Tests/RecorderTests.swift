import XCTest
import AVFoundation
@testable import MetaRayRecorder

final class RecorderTests: XCTestCase {
    func testTimelineDoesNotAddThreeOrFiveMinuteLimit() {
        var timeline = RecordingTimeline()
        XCTAssertEqual(timeline.videoTime(hostTime: 100), 0)
        XCTAssertEqual(timeline.videoTime(hostTime: 401), 301)
        XCTAssertEqual(timeline.videoTime(hostTime: 3700), 3600)
        XCTAssertNil(timeline.videoTime(hostTime: 3700))
        XCTAssertNil(timeline.videoTime(hostTime: .nan))
        XCTAssertNil(timeline.videoTime(hostTime: 3699))
    }
    func testFrameClockIsIndependentOfVisiblePreview() {
        let clock = StreamActivityClock()
        XCTAssertNil(clock.lastFrameTime())
        clock.mark(time: 100)
        clock.mark(time: 102)
        clock.mark(time: 101)
        XCTAssertEqual(clock.lastFrameTime(), 102)
        clock.reset()
        XCTAssertNil(clock.lastFrameTime())
    }
    func testAudioUsesSameOrigin() {
        var timeline = RecordingTimeline()
        XCTAssertNil(timeline.audioTime(hostTime: 10))
        XCTAssertEqual(timeline.videoTime(hostTime: 100), 0)
        XCTAssertNil(timeline.audioTime(hostTime: 99))
        XCTAssertEqual(timeline.audioTime(hostTime: 101.25), 1.25)
    }
    func testClockFormatting() {
        XCTAssertEqual(ClipNames.time(0), "00:00:00")
        XCTAssertEqual(ClipNames.time(3671), "01:01:11")
        XCTAssertEqual(ClipNames.time(-5), "00:00:00")
        XCTAssertEqual(ClipNames.time(.infinity), "00:00:00")
    }
    func testNamesAreUniqueAndSafe() {
        let first = ClipNames.make()
        let second = ClipNames.make()
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasSuffix(".mp4"))
        XCTAssertFalse(first.contains("/"))
        XCTAssertFalse(first.contains(":"))
    }
    func testMovieWriterProducesReadableVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = MovieWriter()
        try await writer.prepare(url: url, quality: .economy, fps: 24, audio: false,
                                 onFirstFrame: {}, onFailure: { _ in })
        let frame = try makeFrame()
        for index in 0..<8 {
            writer.appendVideo(frame, hostTime: 100 + Double(index) / 24)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let finished = try await writer.finish()
        XCTAssertEqual(finished, url)
        let asset = AVURLAsset(url: finished)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertGreaterThan(duration.seconds, 0)
    }
    func testMovieWriterIncludesAACAudio() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = MovieWriter()
        try await writer.prepare(url: url, quality: .economy, fps: 24, audio: true,
                                 onFirstFrame: {}, onFailure: { _ in })
        let frame = try makeFrame()
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                          channels: 1, interleaved: false),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 640),
              let samples = pcm.floatChannelData else {
            throw RecorderFailure.message("Test PCM buffer")
        }
        pcm.frameLength = 640
        // Immutable silence is enough to validate the conversion from HFP-style PCM to AAC.
        samples[0].initialize(repeating: 0, count: 640)
        for index in 0..<24 {
            let time = 100 + Double(index) / 24
            writer.appendVideo(frame, hostTime: time)
            try await Task.sleep(nanoseconds: 40_000_000)
            writer.appendAudio(pcm, hostTime: time + 0.001)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let finished = try await writer.finish()
        let asset = AVURLAsset(url: finished)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertGreaterThan(duration.seconds, 0)
    }
    func testStoppingWithoutFramesDoesNotLeaveCompletedFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let writer = MovieWriter()
        try await writer.prepare(url: url, quality: .economy, fps: 24, audio: false,
                                 onFirstFrame: {}, onFailure: { _ in })
        do { _ = try await writer.finish(); XCTFail("A recording without frames must fail.") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
    }
    private func makeFrame() throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        let pixelStatus = CVPixelBufferCreate(kCFAllocatorDefault, 360, 640, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
        guard pixelStatus == kCVReturnSuccess, let pixel else { throw RecorderFailure.message("Test pixel buffer") }
        CVPixelBufferLockBaseAddress(pixel, [])
        if let base = CVPixelBufferGetBaseAddress(pixel) { memset(base, 0, CVPixelBufferGetDataSize(pixel)) }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
                                                     formatDescriptionOut: &format)
        guard let format else { throw RecorderFailure.message("Test format") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 24),
                                       presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard result == noErr, let sample else { throw RecorderFailure.message("Test sample") }
        return sample
    }
}
