import Foundation

@main
struct CoreChecks {
    static func main() {
        var timeline = RecordingTimeline()
        precondition(timeline.audioTime(hostTime: 10) == nil)
        precondition(timeline.videoTime(hostTime: 100) == 0)
        precondition(timeline.videoTime(hostTime: 401) == 301)
        precondition(timeline.videoTime(hostTime: 3700) == 3600)
        precondition(timeline.videoTime(hostTime: 3700) == nil)
        precondition(timeline.videoTime(hostTime: 3699) == nil)
        precondition(timeline.videoTime(hostTime: .nan) == nil)
        precondition(timeline.audioTime(hostTime: 101.25) == 1.25)
        precondition(ClipNames.time(3671) == "01:01:11")
        precondition(ClipNames.time(-5) == "00:00:00")
        precondition(ClipNames.time(.infinity) == "00:00:00")
        let clock = StreamActivityClock()
        precondition(clock.lastFrameTime() == nil)
        clock.mark(time: 10.0)
        clock.mark(time: 15.0)
        clock.mark(time: 14.0) // Callback hors ordre : ne doit pas reculer.
        clock.mark(time: .nan)
        precondition(clock.lastFrameTime() == 15.0)
        clock.reset()
        precondition(clock.lastFrameTime() == nil)
        let names = (0..<1000).map { _ in ClipNames.make() }
        precondition(Set(names).count == 1000)
        precondition(names.allSatisfy { !$0.contains(":") && !$0.contains("/") && $0.hasSuffix(".mp4") })
        for quality in RecordingQuality.allCases {
            precondition(quality.width % 2 == 0 && quality.height % 2 == 0)
            precondition(quality.bitRate > 0)
        }
        print("PASS: timeline, locked-screen frame clock, quality, filenames. No iOS/hardware execution in this test.")
    }
}
