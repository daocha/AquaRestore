import SwiftUI

/// Filmstrip trim bar: original (uncorrected) thumbnails, a framed selection with a handle on each side, dimmed
/// footage outside it, and the playhead. Dragging near a handle moves it; a tap or drag elsewhere
/// places the cursor, with tools above it to start or end the trim exactly on that frame.
struct TrimBar: View {
    let frames: [CGImage]
    let duration: Int64
    let range: MsRange
    @ObservedObject var player: PlayerController
    let enabled: Bool
    let description: String
    let onChange: (MsRange) -> Void
    let onDone: () -> Void
    let onScrub: (Int64, Bool) -> Void

    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    // The frame the user placed the cursor on. Playback continues from it, so its tools stay pinned
    // to that frame (marked on the strip) until one is used or a handle moves.
    @State private var picked: Int64?
    @State private var toolsWidth: CGFloat = 0
    @State private var target = 0 // -1 start handle, 1 end handle, 0 playhead
    @State private var position: Double = 0
    @State private var dragOrigin: CGFloat = 0

    private let handle: CGFloat = 14
    private let reach: CGFloat = 24

    var body: some View {
        // Keep at least half a second (or the whole clip, if shorter) between the handles.
        let minimum = min(500, duration)
        let showTools = enabled && picked.map { range.contains($0) } == true
        GeometryReader { geo in
            let barWidth = geo.size.width
            let track = max(barWidth - 2 * handle, 1)
            let total = max(Double(duration), 1)
            let x: (Int64) -> CGFloat = { t in handle + CGFloat(Double(t) / total) * track }
            let time: (CGFloat) -> Int64 = { px in Int64((Double((px - handle) / track) * total).rounded()) }
            VStack(spacing: 0) {
                if showTools, let at = picked {
                    tools(at: at, minimum: minimum)
                        .background(GeometryReader { g in Color.clear.preference(key: WidthKey.self, value: g.size.width) })
                        .onPreferenceChange(WidthKey.self) { toolsWidth = $0 }
                        .offset(x: min(max(x(at) - toolsWidth / 2, 0), max(barWidth - toolsWidth, 0)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                        .transition(.expandVertically)
                }
                ZStack {
                    HStack(spacing: 0) {
                        ForEach(frames.indices, id: \.self) { i in
                            Image(decorative: frames[i], scale: 1).resizable().scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(c.surfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.horizontal, handle)
                    overlay(x: x)
                }
                .frame(height: 56)
                .overlay(TouchArea(
                    onDragStart: { touch in
                        guard enabled else { return }
                        // A touch within reach of a handle moves it; anywhere else picks a preview frame inside the range.
                        let toStart = abs(touch.x - (x(range.lowerBound) - handle / 2))
                        let toEnd = abs(touch.x - (x(range.upperBound) + handle / 2))
                        target = min(toStart, toEnd) > reach ? 0 : (toStart <= toEnd ? -1 : 1)
                        dragOrigin = touch.x
                        switch target {
                        case -1: position = Double(range.lowerBound)
                        case 1: position = Double(range.upperBound)
                        default: position = Double(time(touch.x))
                        }
                        if target == 0 { pick(clamp(Int64(position.rounded())), play: false) } else { picked = nil }
                    },
                    onDrag: { point in
                        guard enabled else { return }
                        let t = Int64((position + Double((point.x - dragOrigin) / track) * total).rounded())
                        switch target {
                        case -1: onChange(min(max(t, 0), range.upperBound - minimum)...range.upperBound)
                        case 1: onChange(range.lowerBound...min(max(t, range.lowerBound + minimum), duration))
                        default: pick(clamp(t), play: false)
                        }
                    },
                    onRelease: { point, dragged in
                        guard enabled else { return }
                        if !dragged { pick(clamp(time(point.x)), play: true) } else { finish() }
                    },
                    onCancel: { dragged in if enabled && dragged { finish() } }))
                .accessibilityLabel(description)
            }
        }
        .frame(height: 56 + (showTools ? 48 + 6 : 0))
        .animation(.spring(response: 0.35, dampingFraction: 1), value: showTools)
        .onChange(of: duration) { _ in picked = nil }
    }

    private func clamp(_ t: Int64) -> Int64 { min(max(t, range.lowerBound), range.upperBound) }
    private func pick(_ t: Int64, play: Bool) { picked = t; onScrub(t, play) }
    private func finish() { if target != 0 { onDone() } else if let picked { onScrub(picked, true) } }

    /// `Surface(RoundedCornerShape(16), primaryContainer)` with "Set start" and "Set end" text buttons.
    private func tools(at: Int64, minimum: Int64) -> some View {
        HStack(spacing: 0) {
            M3TextButton(title: s.text("Set start", "設為起點"), fontSize: 12, icon: .firstPage) {
                onChange(at...range.upperBound); onDone(); picked = nil
            }
            .disabled(at > range.upperBound - minimum)
            Rectangle().fill(c.onPrimaryContainer.opacity(0.2)).frame(width: 1, height: 20)
            M3TextButton(title: s.text("Set end", "設為終點"), fontSize: 12, icon: .lastPage, iconTrailing: true) {
                onChange(range.lowerBound...at); onDone(); picked = nil
            }
            .disabled(at < range.lowerBound + minimum)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.primaryContainer))
        .contentColor(c.onPrimaryContainer)
    }

    /// Dimmed footage outside the selection, frame, handles with grips, cursor and playhead.
    private func overlay(x: @escaping (Int64) -> CGFloat) -> some View {
        Canvas { ctx, size in
            let s = x(range.lowerBound), e = x(range.upperBound)
            let dim = Color.black.opacity(0.6)
            ctx.fill(Path(CGRect(x: handle, y: 0, width: max(s - handle, 0), height: size.height)), with: .color(dim))
            ctx.fill(Path(CGRect(x: e, y: 0, width: max(size.width - handle - e, 0), height: size.height)), with: .color(dim))
            let border: CGFloat = 3
            ctx.fill(Path(CGRect(x: s, y: 0, width: e - s, height: border)), with: .color(c.primary))
            ctx.fill(Path(CGRect(x: s, y: size.height - border, width: e - s, height: border)), with: .color(c.primary))
            ctx.fill(Path(roundedRect: CGRect(x: s - handle, y: 0, width: handle, height: size.height), cornerRadius: 4), with: .color(c.primary))
            ctx.fill(Path(roundedRect: CGRect(x: e, y: 0, width: handle, height: size.height), cornerRadius: 4), with: .color(c.primary))
            for grip in [s - handle / 2, e + handle / 2] {
                var line = Path()
                line.move(to: CGPoint(x: grip, y: size.height * 0.35)); line.addLine(to: CGPoint(x: grip, y: size.height * 0.65))
                ctx.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let at = picked, range.contains(at) {
                var line = Path()
                line.move(to: CGPoint(x: x(at), y: 0)); line.addLine(to: CGPoint(x: x(at), y: size.height))
                ctx.stroke(line, with: .color(c.primary), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: x(at) - 4, y: 0, width: 8, height: 8)), with: .color(c.primary))
            }
            let now = player.playhead
            if range.contains(now) {
                var line = Path()
                line.move(to: CGPoint(x: x(now), y: border)); line.addLine(to: CGPoint(x: x(now), y: size.height - border))
                ctx.stroke(line, with: .color(.white), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The whole song as a loudness envelope, with a window as long as the video's output. Dragging
/// slides the window to choose which part of the song plays; a tap centres it on that spot.
struct MusicBar: View {
    let envelope: [Float]?
    let songMs: Int64
    let window: MsRange
    let movable: Bool
    let description: String
    let onMove: (Int64) -> Void
    let onDone: () -> Void

    @Environment(\.palette) private var c
    @State private var start: Double = 0
    @State private var origin: CGFloat = 0

    var body: some View {
        let length = window.upperBound - window.lowerBound
        GeometryReader { geo in
            Canvas { ctx, size in
                let total = Double(max(songMs, 1))
                let left = CGFloat(Double(window.lowerBound) / total) * size.width
                let right = CGFloat(Double(window.upperBound) / total) * size.width
                let bars = envelope ?? []
                let step = bars.isEmpty ? 0 : size.width / CGFloat(bars.count)
                let idle = c.onSurfaceVariant.opacity(0.35)
                for (i, level) in bars.enumerated() {
                    let x = CGFloat(i) * step + step / 2
                    let h = (0.12 + 0.88 * CGFloat(level)) * size.height * 0.8
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: (size.height - h) / 2)); line.addLine(to: CGPoint(x: x, y: (size.height + h) / 2))
                    ctx.stroke(line, with: .color(x >= left && x <= right ? c.primary : idle),
                               style: StrokeStyle(lineWidth: max(step * 0.6, 1), lineCap: .round))
                }
                // A 3dp stroke centred on the window's edges, clipped by the bar's rounded shape like the Compose canvas.
                ctx.stroke(Path(roundedRect: CGRect(x: left, y: 0, width: right - left, height: size.height), cornerRadius: 6),
                           with: .color(c.primary), lineWidth: 3)
            }
            .background(c.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(TouchArea(
                onDragStart: { touch in
                    guard movable else { return }
                    start = Double(window.lowerBound)
                    origin = touch.x
                },
                onDrag: { point in
                    guard movable else { return }
                    let t = start + Double((point.x - origin) / max(geo.size.width, 1)) * Double(songMs)
                    onMove(min(max(Int64(t.rounded()), 0), songMs - length))
                },
                onRelease: { point, dragged in
                    guard movable else { return }
                    if !dragged {
                        let centre = Double(point.x / max(geo.size.width, 1)) * Double(songMs) - Double(length) / 2
                        onMove(min(max(Int64(centre.rounded()), 0), songMs - length))
                    }
                    onDone()
                },
                onCancel: { dragged in if movable && dragged { onDone() } }))
        }
        .frame(height: 48)
        .accessibilityLabel(description)
    }
}
