import Foundation

struct MusicTrack: Equatable { let url: URL; let name: String; let durationMs: Int64 }

/// How the exported soundtrack is built: the video's own audio and an optional background track.
struct AudioMix: Equatable {
    var originalVolume: Float = 1
    var music: MusicTrack?
    var musicStartMs: Int64 = 0
    var musicVolume: Float = 1

    var hasMusic: Bool { music != nil && musicVolume > 0 }
    /// Anything other than the untouched original audio requires re-encoding it.
    var changesAudio: Bool { originalVolume != 1 || hasMusic }
}

/// A closed range of milliseconds, like Kotlin's `LongRange`.
typealias MsRange = ClosedRange<Int64>

/// The part of a song that plays under `outputMs` of video, starting near `startMs`. The start is
/// kept within the song so the window never runs past its end; a song shorter than the video
/// plays from the beginning and loops.
func musicWindow(songMs: Int64, startMs: Int64, outputMs: Int64) -> MsRange {
    if songMs <= outputMs { return 0...songMs }
    let start = min(max(startMs, 0), songMs - outputMs)
    return start...(start + outputMs)
}

/// Song sections that fill `outputMs`: the window once, or repeated with the last copy cut short.
func musicPieces(window: MsRange, outputMs: Int64) -> [MsRange] {
    let length = window.upperBound - window.lowerBound
    if length <= 0 || outputMs <= 0 { return [] }
    return (0..<((outputMs + length - 1) / length)).map { i in
        window.lowerBound...(window.lowerBound + min(length, outputMs - i * length))
    }
}

/// Where the song should be for `elapsedMs` of output, or nil when it is silent.
func musicPosition(songMs: Int64, window: MsRange, elapsedMs: Int64) -> Int64? {
    if elapsedMs < 0 || songMs <= 0 { return nil }
    if songMs <= window.upperBound - window.lowerBound { return elapsedMs % songMs }
    if window.lowerBound + elapsedMs < window.upperBound { return window.lowerBound + elapsedMs }
    return nil
}

/// "m:ss.t" with tenths of a second, as shown on the trim bar.
func clock(_ ms: Int64) -> String {
    let tenths = (max(ms, 0) + 50) / 100
    return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
}

/// Volume from 0 to 200%, clipping loud samples instead of wrapping them.
enum Gain {
    static func apply(_ sample: Int16, _ gain: Float) -> Int16 {
        Int16(min(max((Float(sample) * gain).rounded(), -32768), 32767))
    }
    static func apply(_ sample: Float, _ gain: Float) -> Float { min(max(sample * gain, -1), 1) }
}
