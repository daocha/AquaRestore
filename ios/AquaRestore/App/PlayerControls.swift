import SwiftUI

// The Android preview has no controller on the video (`useController = false`). Under it sit the clip controls:
// a play/pause pill with the time, a speed button and "Compare", above the trim bar, which is also the progress bar.
// Full screen floats the same controls over the video, above the Adjust button.

/// What the clip controls share between the editor and full screen, as Android's `Editor` keeps it: whether the
/// speed choices are open and the frame the trim bar's cursor sits on. The floating pill and the trim bar are the
/// places a touch does not close them.
final class ClipUI: ObservableObject {
    @Published var speedExpanded = false
    @Published var picked: Int64?
    var overlayFrame: CGRect?
    var trimFrame: CGRect?

    var active: Bool { speedExpanded || picked != nil }

    func openSpeed() { speedExpanded = true; picked = nil }
    func pick(_ at: Int64) { picked = at; speedExpanded = false }
    func dismiss() {
        if speedExpanded { speedExpanded = false }
        if picked != nil { picked = nil }
    }
    func reset() { dismiss(); overlayFrame = nil; trimFrame = nil }
    func isInside(_ point: CGPoint) -> Bool { overlayFrame?.contains(point) == true || trimFrame?.contains(point) == true }
}

/// Where the trim bar and the floating pill are on screen (global coordinates), reported up to `ClipControls`.
struct ClipFrames: Equatable {
    var overlay: CGRect?
    var trim: CGRect?
}

struct ClipFramesKey: PreferenceKey {
    static var defaultValue = ClipFrames()
    static func reduce(value: inout ClipFrames, nextValue: () -> ClipFrames) {
        let next = nextValue()
        if let overlay = next.overlay { value.overlay = overlay }
        if let trim = next.trim { value.trim = trim }
    }
}

private extension View {
    /// Reports this view's frame as the floating pill, so a touch on it does not close the speed choices or trim tools.
    func reportsOverlayFrame() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: ClipFramesKey.self, value: ClipFrames(overlay: geo.frame(in: .global), trim: nil))
        })
    }
}

extension View {
    /// A touch outside the floating pill and the trim bar closes the speed choices and the trim cursor, without
    /// taking the touch from whatever was pressed.
    func closesClipControls(_ ui: ClipUI) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if ui.active && !ui.isInside(value.startLocation) { ui.dismiss() }
                },
            including: ui.active ? .all : .subviews)
    }
}

/// The video at its aspect ratio, nothing drawn over it.
struct VideoSurface: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        ZStack {
            Color.black
            if let aspect = player.aspect {
                PlayerSurface(player: player.player).aspectRatio(aspect, contentMode: .fit)
            } else {
                PlayerSurface(player: player.player)
            }
        }
    }
}

private let pillColor = Color.black.opacity(0.88)
private let floatingColor = Color(red: 0x17 / 255.0, green: 0x17 / 255.0, blue: 0x17 / 255.0)

/// The play controls and the trim bar, as Android's `ClipControls`.
struct ClipControls: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var player: PlayerController
    @ObservedObject var ui: ClipUI
    let duration: Int64
    let enabled: Bool
    @Environment(\.strings) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoControls(model: model, player: player, ui: ui, duration: duration, enabled: enabled)
            TrimBar(frames: model.filmstrip, duration: duration, range: model.trim, player: player, ui: ui, enabled: enabled,
                    description: s.text("Trim range", "剪輯範圍"),
                    onChange: { model.trimming = true; model.trim = $0 },
                    onDone: { model.trimming = false },
                    onScrub: { position, play in model.scrub.send((position, play)) })
        }
        .onPreferenceChange(ClipFramesKey.self) { frames in
            ui.overlayFrame = frames.overlay
            ui.trimFrame = frames.trim
        }
    }
}

/// One 48dp row: "Full clip" (only when trimmed), the play pill with the time, the speed button and Compare. The
/// speed choices, or the trim actions over the cursor, replace it while they are open.
struct VideoControls: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var player: PlayerController
    @ObservedObject var ui: ClipUI
    let duration: Int64
    let enabled: Bool
    @Environment(\.strings) private var s

    private let handle: CGFloat = 14
    private let toolsWidth: CGFloat = 104

    var body: some View {
        let trim = model.trim
        let trimmed = trim.lowerBound > 0 || trim.upperBound < duration
        let target = ui.picked.flatMap { trim.contains($0) ? $0 : nil }
        ZStack {
            if !ui.speedExpanded && target == nil { row(trimmed: trimmed) }
            if ui.speedExpanded { speedChoices }
            if let target, !ui.speedExpanded { trimTools(at: target, range: trim) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }

    private func row(trimmed: Bool) -> some View {
        HStack(spacing: 6) {
            // Whatever room the buttons leave; "Full clip" shortens rather than pushing them off the row.
            HStack(spacing: 0) {
                if trimmed {
                    M3TextButton(title: s.text("Full clip", "完整長度"), padding: 8) { setTrim(0...duration) }
                        .disabled(!enabled)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            playPill
            speedButton
            CompareButton(model: model)
        }
    }

    private var playPill: some View {
        HStack(spacing: 0) {
            Button { player.togglePlay() } label: {
                MIcon(player.isPlaying ? .pause : .playArrow, size: 22, color: .white)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(MaterialPress(shape: Circle(), color: .white))
            .disabled(!enabled || player.player == nil)
            .accessibilityLabel(player.isPlaying ? s.text("Pause", "暫停") : s.text("Play", "播放"))
            Text("\(clock(player.playhead)) / \(clock(duration))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.trailing, 12)
        .frame(height: 40)
        .background(Capsule().fill(pillColor))
    }

    private var speedButton: some View {
        Button { ui.openSpeed() } label: {
            MIcon(.speed, size: 21, color: .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(pillColor))
                .contentShape(Circle())
        }
        .buttonStyle(MaterialPress(shape: Circle(), color: .white))
        .disabled(!enabled)
        .accessibilityLabel(s.text("Video speed", "影片速度"))
    }

    private var speedChoices: some View {
        HStack(spacing: 0) {
            ForEach([Float(0.5), 1, 2, 4], id: \.self) { value in
                let selected = model.speed == value
                Button {
                    model.speed = value
                    ui.speedExpanded = false
                } label: {
                    Text(value == 0.5 ? "0.5×" : "\(Int(value))×")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? .black : .white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(selected ? Color.white : Color.clear))
                        .contentShape(Circle())
                }
                .buttonStyle(MaterialPress(shape: Circle(), color: selected ? .black : .white))
                .disabled(!enabled)
            }
        }
        .padding(3)
        .background(Capsule().fill(floatingColor).shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3))
        .reportsOverlayFrame()
    }

    /// Centred over the cursor, using the trim bar's geometry (14dp handles), kept inside the row.
    private func trimTools(at target: Int64, range: MsRange) -> some View {
        let minimum = min(500, duration)
        return GeometryReader { geo in
            let track = max(geo.size.width - 2 * handle, 1)
            let cursor = handle + (duration > 0 ? CGFloat(target) / CGFloat(duration) : 0) * track
            let left = min(max(cursor - toolsWidth / 2, 0), max(geo.size.width - toolsWidth, 0))
            HStack(spacing: 0) {
                Button { setTrim(target...range.upperBound) } label: {
                    TrimEdgeIcon(start: true, label: s.text("Set start", "設為起點")).frame(width: 48, height: 48).contentShape(Circle())
                }
                .buttonStyle(MaterialPress(shape: Circle(), color: .white))
                .disabled(!enabled || target > range.upperBound - minimum)
                Button { setTrim(range.lowerBound...target) } label: {
                    TrimEdgeIcon(start: false, label: s.text("Set end", "設為終點")).frame(width: 48, height: 48).contentShape(Circle())
                }
                .buttonStyle(MaterialPress(shape: Circle(), color: .white))
                .disabled(!enabled || target < range.lowerBound + minimum)
            }
            .padding(.horizontal, 4)
            .background(Capsule().fill(floatingColor).shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3))
            .reportsOverlayFrame()
            .offset(x: left)
        }
        .frame(height: 48)
    }

    private func setTrim(_ range: MsRange) {
        model.trimming = true
        model.trim = range
        model.trimming = false
        ui.picked = nil
    }
}

/// The trim action icon: the clip's edge with the kept side marked by a bracket.
private struct TrimEdgeIcon: View {
    let start: Bool
    let label: String

    var body: some View {
        Canvas { ctx, size in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * (start ? x : 1 - x), y: size.height * y) }
            func line(_ a: CGPoint, _ b: CGPoint) {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            for i in 0...4 {
                let p = point(0.16, 0.14 + CGFloat(i) * 0.18)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)), with: .color(.white))
            }
            line(point(0.39, 0.14), point(0.39, 0.86))
            line(point(0.39, 0.14), point(0.69, 0.14))
            line(point(0.39, 0.86), point(0.69, 0.86))
            line(point(0.74, 0.22), point(0.74, 0.78))
        }
        .frame(width: 28, height: 28)
        .accessibilityLabel(label)
    }
}

/// "Compare": shows the original while held; styled like the play and speed buttons beside it.
struct CompareButton: View {
    @ObservedObject var model: EditorModel
    @Environment(\.strings) private var s

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 0) {
            MIcon(.compare, size: 16, color: .white)
            Spacer().frame(width: 5)
            Text(s.text("Compare", "對比"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(shape.fill(pillColor))
        .overlay(shape.fill(Color.white.opacity(model.compare ? 0.1 : 0)).allowsHitTesting(false))
        .overlay(TouchArea(
            onPress: { _ in model.setCompare(true) },
            onRelease: { _, _ in model.setCompare(false) },
            onCancel: { _ in model.setCompare(false) },
            pressImmediately: true))
        .clipShape(shape)
        .accessibilityElement()
        .accessibilityLabel(s.text("Hold to compare", "按住對比原片"))
        .accessibilityAddTraits(.isButton)
    }
}
