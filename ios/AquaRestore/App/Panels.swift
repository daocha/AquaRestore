import SwiftUI

// The editor's panels, one per Android Panel in MainActivity.kt, in the same order and with the same rows.

struct SpeedPanel: View {
    @ObservedObject var model: EditorModel
    @Binding var expanded: Bool
    let enabled: Bool
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s

    private func label(_ value: Float) -> String { value == 0.5 ? "0.5×" : "\(Int(value))×" }

    var body: some View {
        Panel {
            ExpandHeader(expanded: expanded, toggle: { expanded.toggle() }) {
                MIcon(.speed, size: 20)
                Spacer().frame(width: 10)
                MText(s.text("Video speed", "影片速度"), weight: .medium).frame(maxWidth: .infinity, alignment: .leading)
                if !expanded { MText(label(model.speed), size: 13, color: c.primary).unweighted() }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([Float(0.5), 1, 2, 4], id: \.self) { value in
                            FilterChip(label: label(value), selected: model.speed == value) { model.speed = value }
                                .disabled(!enabled)
                        }
                    }
                    MText(s.text("Applied to preview and export; audio keeps its pitch.", "套用至預覽與匯出；音訊保留原音高。"), size: 12)
                }
                .transition(.expandVertically)
            }
        }
    }
}

struct TrimPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var player: PlayerController
    let duration: Int64
    @Binding var expanded: Bool
    let enabled: Bool
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s

    var body: some View {
        let trim = model.trim
        let trimmed = trim.lowerBound > 0 || trim.upperBound < duration
        Panel {
            ExpandHeader(expanded: expanded, toggle: { expanded.toggle() }) {
                MIcon(.contentCut, size: 20)
                Spacer().frame(width: 10)
                MText(s.text("Trim", "剪輯長度"), weight: .medium).frame(maxWidth: .infinity, alignment: .leading)
                MText("\(clock(trim.lowerBound))–\(clock(trim.upperBound)) (\(clock(trim.upperBound - trim.lowerBound)))", size: 13,
                      color: trimmed ? c.primary : c.onSurfaceVariant).unweighted()
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    TrimBar(frames: model.filmstrip, duration: duration, range: trim, player: player, enabled: enabled,
                            description: s.text("Trim range", "剪輯範圍"),
                            onChange: { model.trimming = true; model.trim = $0 },
                            onDone: { model.trimming = false },
                            onScrub: { position, play in model.scrub.send((position, play)) })
                    HStack(alignment: .center, spacing: 0) {
                        PlayheadTime(player: player)
                        MText(s.text("Edges: trim · tap a frame to play from it", "邊框：剪輯 · 點按影格從該處播放"), size: 11,
                              color: c.onSurfaceVariant, maxLines: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if trimmed {
                            M3TextButton(title: s.text("Full clip", "完整長度")) { model.trim = 0...duration }.disabled(!enabled).unweighted()
                        }
                    }
                }
                .transition(.expandVertically)
            }
        }
    }
}

private struct PlayheadTime: View {
    @ObservedObject var player: PlayerController
    @Environment(\.palette) private var c
    var body: some View {
        // Isolated so playback ticks redraw only this label.
        MText(clock(player.playhead), size: 12, weight: .medium, color: c.primary).unweighted().padding(.trailing, 8)
    }
}

struct AudioPanel: View {
    @ObservedObject var model: EditorModel
    @Binding var expanded: Bool
    let enabled: Bool
    let pickMusic: () -> Void
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s

    var body: some View {
        Panel {
            ExpandHeader(expanded: expanded, toggle: { expanded.toggle() }) {
                MIcon(.musicNote, size: 20)
                Spacer().frame(width: 10)
                MText(s.text("Audio", "音訊"), weight: .medium).unweighted()
                Spacer().frame(width: 12)
                MText(model.music?.name ?? (model.originalVolume == 0 ? s.text("Muted", "已靜音") : s.text("Original sound", "原聲")),
                      size: 13, color: model.music != nil ? c.primary : c.onSurfaceVariant, maxLines: 1, align: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    VolumeRow(label: s.text("Original sound", "原聲"), value: model.originalVolume, enabled: enabled) { model.originalVolume = $0 }
                    if let current = model.music {
                        VolumeRow(label: s.text("Music", "音樂"), value: model.musicVolume, enabled: enabled) { model.musicVolume = $0 }
                        let outputMs = Int64(Double(model.trim.upperBound - model.trim.lowerBound) / Double(model.speed))
                        let window = musicWindow(songMs: current.durationMs, startMs: model.musicStartMs, outputMs: outputMs)
                        MusicBar(envelope: model.musicEnvelope, songMs: current.durationMs, window: window,
                                 movable: enabled && current.durationMs > outputMs, description: s.text("Music section", "音樂片段"),
                                 onMove: { model.musicStartMs = $0 }, onDone: { model.audition.send() })
                        HStack(alignment: .center, spacing: 0) {
                            MText(current.durationMs <= outputMs ? s.text("Song is shorter than the video, so it repeats", "音樂比影片短，會重複播放")
                                  : s.text("Plays \(clock(window.lowerBound))–\(clock(window.upperBound))", "播放 \(clock(window.lowerBound))–\(clock(window.upperBound))"),
                                  size: 11, color: c.onSurfaceVariant, maxLines: 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            M3TextButton(title: s.text("Replace", "更換"), action: pickMusic).disabled(!enabled).unweighted()
                            M3TextButton(title: s.text("Remove", "移除")) { model.removeMusic() }.disabled(!enabled).unweighted()
                        }
                    } else {
                        M3Button(title: s.text("Add music", "加入音樂"), icon: .libraryMusic, iconSize: 18, iconSpacing: 8, style: .outlined,
                                 spinner: model.musicLoading, fullWidth: true, action: pickMusic)
                            .disabled(!enabled || model.musicLoading)
                    }
                }
                .transition(.expandVertically)
            }
        }
    }
}

struct RestorePanel: View {
    @ObservedObject var model: EditorModel
    let result: Analysis
    @Binding var expanded: Bool
    let enabled: Bool
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s

    var body: some View {
        Panel {
            ExpandHeader(expanded: expanded, toggle: { expanded.toggle() }) {
                MIcon(.autoAwesome, size: 20, color: c.primary)
                Spacer().frame(width: 10)
                MText(s.text("Intelligent restore", "智慧色彩還原"), weight: .semibold, maxLines: 1).frame(maxWidth: .infinity, alignment: .leading)
                MText("\(Int((model.grade.strength * 100).rounded()))%", weight: .bold, color: c.primary).unweighted()
                M3TextButton(title: s.text("Reset", "重設")) { model.reset() }.disabled(!enabled).unweighted()
            }
            M3Slider(value: model.grade.strength, range: 0...1, onChange: { v in var g = model.grade; g.strength = v; model.setGrade(g) },
                     accessibility: s.text("Restore intensity", "還原強度")).disabled(!enabled)
            if result.confidence < 0.25 {
                MText(s.text("Low-light or limited color detail: use a gentle strength and check the result.",
                             "光線或色彩資訊不足：建議使用較低強度並確認效果。"), size: 12, color: c.tertiary)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    MText(s[result.cast], size: 12, color: c.primary)
                    HStack {
                        MText(s.text("0% · Original colors", "0% · 原始色彩"), size: 11, color: c.onSurfaceVariant)
                        Spacer(minLength: 0)
                        MText(s.text("100% · Full restore", "100% · 完整還原"), size: 11, color: c.onSurfaceVariant)
                    }
                    MText(s.text("Scales every correction together; the advanced sliders below follow it.",
                                 "同時等比例調整所有校正，下方進階滑桿會跟著變化。"), size: 13, color: c.onSurfaceVariant)
                }
                .transition(.expandVertically)
            }
        }
    }
}

struct AdvancedPanel: View {
    @ObservedObject var model: EditorModel
    let enabled: Bool
    @State private var expanded = false
    @Environment(\.strings) private var s

    var body: some View {
        Panel {
            ExpandHeader(expanded: expanded, toggle: { expanded.toggle() }) {
                MIcon(.tune, size: 20)
                Spacer().frame(width: 10)
                MText(s.text("Advanced adjustments", "進階調整"), weight: .medium).frame(maxWidth: .infinity, alignment: .leading)
            }
            if expanded { AdvancedSliders(model: model, enabled: enabled).transition(.expandVertically) }
        }
    }
}

struct AdvancedSliders: View {
    @ObservedObject var model: EditorModel
    let enabled: Bool
    @Environment(\.strings) private var s

    private static func applied(_ p: Grade) -> Grade {
        var e = p.effective()
        e.strength = 1
        return e
    }

    var body: some View {
        // Sliders show what is applied at the current intensity, so they move with it. Edits are stored
        // relative to the intensity; at 0% the (all-zero) applied values become the new base at 100%.
        let p = model.grade
        let k = p.strength
        let e = Self.applied(p)
        func edit(_ value: Float, _ update: (inout Grade, Float) -> Void) {
            var g = k > 0 ? p : e
            update(&g, k > 0 ? value / k : value)
            model.setGrade(g)
        }
        return VStack(alignment: .leading, spacing: 0) {
            Adjustment(label: s.text("Auto levels", "自動色階"), value: e.levels, range: 0...1, enabled: enabled) { edit($0) { g, v in g.levels = v } }
            Adjustment(label: s.text("Red recovery", "紅色補償"), value: e.red, range: 0...1, enabled: enabled) { edit($0) { g, v in g.red = v } }
            Adjustment(label: s.text("Protect cool water", "保護冷色水域"), value: e.coolProtection, range: 0...1, enabled: enabled) { edit($0) { g, v in g.coolProtection = v } }
            Adjustment(label: s.text("Warmth", "色溫"), value: e.temperature, range: -1...1, enabled: enabled) { edit($0) { g, v in g.temperature = v } }
            Adjustment(label: s.text("Green → magenta tint", "綠 → 洋紅色偏"), value: e.tint, range: -1...1, enabled: enabled) { edit($0) { g, v in g.tint = v } }
            Adjustment(label: s.text("Exposure (EV)", "曝光（EV）"), value: e.exposure, range: -2...2, enabled: enabled) { edit($0) { g, v in g.exposure = v } }
            Adjustment(label: s.text("Dehaze", "去霧"), value: e.haze, range: 0...1, enabled: enabled) { edit($0) { g, v in g.haze = v } }
            Adjustment(label: s.text("Clarity", "清晰度"), value: e.clarity, range: 0...1, enabled: enabled) { edit($0) { g, v in g.clarity = v } }
            Adjustment(label: s.text("Contrast", "對比"), value: e.contrast, range: -0.5...0.5, enabled: enabled) { edit($0) { g, v in g.contrast = v } }
            Adjustment(label: s.text("Saturation", "飽和度"), value: e.saturation, range: -1...1, enabled: enabled) { edit($0) { g, v in g.saturation = v } }
            Adjustment(label: s.text("Shadows", "陰影"), value: e.shadows, range: -1...1, enabled: enabled) { edit($0) { g, v in g.shadows = v } }
        }
    }
}

private struct Adjustment: View {
    @Environment(\.palette) private var c
    let label: String
    let value: Float
    let range: ClosedRange<Float>
    let enabled: Bool
    let change: (Float) -> Void
    var body: some View {
        HStack(alignment: .top) {
            MText(label, size: 13)
            Spacer(minLength: 0)
            MText(String(format: "%.2f", value), size: 12, color: c.onSurfaceVariant)
        }
        M3Slider(value: min(max(value, range.lowerBound), range.upperBound), range: range, onChange: change, accessibility: label)
            .disabled(!enabled)
    }
}

/// The Android `Volume` row: a 96dp label, the slider, and the percentage in 44dp.
struct VolumeRow: View {
    @Environment(\.palette) private var c
    let label: String
    let value: Float
    let enabled: Bool
    let change: (Float) -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            MText(label, size: 13, maxLines: 1).frame(width: 96, alignment: .leading)
            M3Slider(value: value, range: 0...2, onChange: change, accessibility: label).disabled(!enabled)
            MText("\(Int((value * 100).rounded()))%", size: 12, color: c.onSurfaceVariant, align: .trailing).frame(width: 44, alignment: .trailing)
        }
    }
}
