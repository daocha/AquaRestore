import SwiftUI

// Media3's PlayerView with its default styled controller (media3-ui 1.9.3), as the Android preview shows it:
// a tap toggles the controller; it hides after 5 s by first leaving only the progress bar for 2 s. Small views
// (the editor's preview box) use the minimal layout with play/pause and a thin progress bar; larger ones (full
// screen) add previous, rewind 5 s, fast-forward 15 s, next, the time and the settings menu above a time bar.

/// Media3's own vector drawables (24-unit viewport), white.
private enum ExoIcon {
    static let play = SVGPath.parse("M 12 2 C 6.48 2 2 6.48 2 12 C 2 17.52 6.48 22 12 22 C 17.52 22 22 17.52 22 12 C 22 6.48 17.52 2 12 2 Z M 10 16.5 L 10 7.5 L 16 12 L 10 16.5 Z")
    static let pause = SVGPath.parse("M 12 2 C 6.48 2 2 6.48 2 12 C 2 17.52 6.48 22 12 22 C 17.52 22 22 17.52 22 12 C 22 6.48 17.52 2 12 2 Z M 11 16 L 9 16 L 9 8 L 11 8 L 11 16 Z M 15 16 L 13 16 L 13 8 L 15 8 L 15 16 Z")
    static let previous = SVGPath.parse("M 6 6 L 8 6 L 8 18 L 6 18 Z M 9.5 12 L 18 18 L 18 6 Z")
    static let next = SVGPath.parse("M 6 18 L 14.5 12 L 6 6 L 6 18 Z M 16 6 L 16 18 L 18 18 L 18 6 L 16 6 Z")
    static let rewind = SVGPath.parse("M 12 5 L 12 1 L 7 6 L 12 11 L 12 7 C 15.31 7 18 9.69 18 13 C 18 16.31 15.31 19 12 19 C 8.69 19 6 16.31 6 13 L 4 13 C 4 17.42 7.58 21 12 21 C 16.42 21 20 17.42 20 13 C 20 8.58 16.42 5 12 5 Z")
    static let check = SVGPath.parse("M 9 16.2 L 4.8 12 L 3.4 13.4 L 9 19 L 21 7 L 19.6 5.6 L 9 16.2 Z")
    static let speed = SVGPath.parse("M 13.05 9.79 L 10 7.5 L 10 16.5 L 13.05 14.21 L 16 12 Z M 13.05 9.79 L 10 7.5 L 10 16.5 L 13.05 14.21 L 16 12 Z M 13.05 9.79 L 10 7.5 L 10 16.5 L 13.05 14.21 L 16 12 Z M 11 4.07 L 11 2.05 C 8.99 2.25 7.16 3.05 5.68 4.26 L 7.1 5.69 C 8.21 4.83 9.54 4.25 11 4.07 Z M 5.69 7.1 L 4.26 5.68 C 3.05 7.16 2.25 8.99 2.05 11 L 4.07 11 C 4.25 9.54 4.83 8.21 5.69 7.1 Z M 4.07 13 L 2.05 13 C 2.25 15.01 3.05 16.84 4.26 18.32 L 5.69 16.89 C 4.83 15.79 4.25 14.46 4.07 13 Z M 5.68 19.74 C 7.16 20.95 9 21.75 11 21.95 L 11 19.93 C 9.54 19.75 8.21 19.17 7.1 18.31 L 5.68 19.74 Z M 22 12 C 22 17.16 18.08 21.42 13.05 21.95 L 13.05 19.93 C 16.97 19.41 20 16.05 20 12 C 20 7.95 16.97 4.59 13.05 4.07 L 13.05 2.05 C 18.08 2.58 22 6.84 22 12 Z")
    static let settings = SVGPath.parse("M 19.43 12.98 C 19.47 12.66 19.5 12.34 19.5 12 C 19.5 11.66 19.47 11.34 19.43 11.02 L 21.54 9.37 C 21.73 9.22 21.78 8.95 21.66 8.73 L 19.66 5.27 C 19.54 5.05 19.27 4.97 19.05 5.05 L 16.56 6.05 C 16.04 5.65 15.48 5.32 14.87 5.07 L 14.49 2.42 C 14.46 2.18 14.25 2 14 2 L 10 2 C 9.75 2 9.54 2.18 9.51 2.42 L 9.13 5.07 C 8.52 5.32 7.96 5.66 7.44 6.05 L 4.95 5.05 C 4.72 4.96 4.46 5.05 4.34 5.27 L 2.34 8.73 C 2.21 8.95 2.27 9.22 2.46 9.37 L 4.57 11.02 C 4.53 11.34 4.5 11.67 4.5 12 C 4.5 12.33 4.53 12.66 4.57 12.98 L 2.46 14.63 C 2.27 14.78 2.22 15.05 2.34 15.27 L 4.34 18.73 C 4.46 18.95 4.73 19.03 4.95 18.95 L 7.44 17.95 C 7.96 18.35 8.52 18.68 9.13 18.93 L 9.51 21.58 C 9.54 21.82 9.75 22 10 22 L 14 22 C 14.25 22 14.46 21.82 14.49 21.58 L 14.87 18.93 C 15.48 18.68 16.04 18.34 16.56 17.95 L 19.05 18.95 C 19.28 19.04 19.54 18.95 19.66 18.73 L 21.66 15.27 C 21.78 15.05 21.73 14.78 21.54 14.63 L 19.43 12.98 Z M 12 15.5 C 10.07 15.5 8.5 13.93 8.5 12 C 8.5 10.07 10.07 8.5 12 8.5 C 13.93 8.5 15.5 10.07 15.5 12 C 15.5 13.93 13.93 15.5 12 15.5 Z")
}

private struct ExoImage: View {
    let path: Path
    var size: CGFloat
    var opacity: Double = 1
    var body: some View {
        IconShape(path: path).fill(Color.white.opacity(opacity)).frame(width: size, height: size)
    }
}

/// The Android PlayerView: the video at its aspect ratio with the controller over it.
struct VideoSurface: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        ZStack {
            Color.black
            Group {
                if let aspect = player.aspect {
                    PlayerChrome(player: player).aspectRatio(aspect, contentMode: .fit)
                } else {
                    PlayerChrome(player: player)
                }
            }
        }
    }
}

private struct PlayerChrome: View {
    @ObservedObject var player: PlayerController
    @State private var ux = UX.none
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubPosition: Int64?
    @State private var settings: SettingsPage?

    enum UX { case all, progressOnly, none }
    enum SettingsPage { case main, speed }

    private static let speeds: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        GeometryReader { geo in
            // Media3 switches to the minimal layout when the full one does not fit: five 52dp center buttons with
            // 5dp margins, and room for the center row plus the bottom bar twice.
            let minimal = geo.size.width <= 310 || geo.size.height <= 52 + 2 * 70
            ZStack {
                PlayerSurface(player: player.player)
                Color.clear.contentShape(Rectangle()).onTapGesture { toggle() }
                if ux == .all {
                    Color.black.opacity(0x98 / 255.0).allowsHitTesting(false).transition(.opacity)
                    centerControls(minimal: minimal).transition(.opacity)
                    if !minimal { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                if ux != .none {
                    timeBar(width: geo.size.width, full: !minimal && ux == .all)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, !minimal && ux == .all ? 52 : 0)
                        .transition(.opacity)
                }
                if let page = settings { settingsMenu(page, in: geo.size) }
            }
            .clipped()
            .animation(.linear(duration: 0.25), value: ux)
        }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: Show / hide

    private func toggle() {
        if settings != nil { settings = nil; resetHide(); return }
        if ux == .all { hideTask?.cancel(); ux = .none } else { ux = .all; resetHide() }
    }

    /// After 5 s the main bar goes and only the progress bar stays; 2 s later that goes too.
    private func resetHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, scrubPosition == nil, settings == nil else { return }
            ux = .progressOnly
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            ux = .none
        }
    }

    // MARK: Center

    private func centerControls(minimal: Bool) -> some View {
        let zh = systemChinese
        return HStack(spacing: 10) {
            button(zh ? "返回" : "Previous") { player.seekToPrevious() } label: { ExoImage(path: ExoIcon.previous, size: 48) }
                .opacity(minimal ? 0 : 1).disabled(minimal)
            amountButton(zh ? "倒轉" : "Rewind", amount: 5, mirrored: false) { player.seek(by: -5_000) }
                .opacity(minimal ? 0 : 1).disabled(minimal)
            button(player.isPlaying ? (zh ? "暫停" : "Pause") : (zh ? "播放" : "Play")) { player.togglePlay() } label: {
                ExoImage(path: player.isPlaying ? ExoIcon.pause : ExoIcon.play, size: 48)
            }
            amountButton(zh ? "快轉" : "Fast forward", amount: 15, mirrored: true) { player.seek(by: 15_000) }
                .opacity(minimal ? 0 : 1).disabled(minimal)
            // With a single item there is nothing next, so Media3 shows it disabled.
            ExoImage(path: ExoIcon.next, size: 48, opacity: 0.33).frame(width: 52, height: 52)
                .opacity(minimal ? 0 : 1)
                .accessibilityLabel(zh ? "繼續" : "Next")
        }
    }

    private func button<Label: View>(_ description: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button { action(); resetHide() } label: { label().frame(width: 52, height: 52).contentShape(Circle()) }
            .buttonStyle(MaterialPress(shape: Circle(), color: .white))
            .accessibilityLabel(description)
    }

    /// The rewind / fast-forward arrow at 70% with the seconds written inside it.
    private func amountButton(_ description: String, amount: Int, mirrored: Bool, action: @escaping () -> Void) -> some View {
        button(description, action: action) {
            ZStack {
                ExoImage(path: ExoIcon.rewind, size: 52 * 0.7).scaleEffect(x: mirrored ? -1 : 1, y: 1)
                Text("\(amount)").font(.system(size: 9, weight: .bold)).foregroundColor(.white).offset(y: 2.5)
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        let zh = systemChinese
        return VStack {
            Spacer()
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(playerTime(scrubPosition ?? player.playhead)).foregroundColor(.white).padding(.horizontal, 4)
                    Text("·").foregroundColor(.white.opacity(0.7)).padding(.horizontal, 4)
                    Text(playerTime(player.durationMs)).foregroundColor(.white.opacity(0.7)).padding(.horizontal, 4)
                }
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 10)
                Spacer()
                Button { settings = .main; hideTask?.cancel() } label: {
                    ExoImage(path: ExoIcon.settings, size: 24).padding(12).contentShape(Circle())
                }
                .buttonStyle(MaterialPress(shape: Circle(), color: .white))
                .padding(.horizontal, 2)
                .accessibilityLabel(zh ? "設定" : "Settings")
            }
            .frame(height: 60)
            .background(Color.black.opacity(0xB0 / 255.0))
        }
    }

    // MARK: Time bar

    /// DefaultTimeBar: a 2dp bar (played white, buffered 80%, unplayed 20%) with a 10dp scrubber (14dp dragged),
    /// in a 48dp touch target. Seeking happens when the drag ends.
    private func timeBar(width: CGFloat, full: Bool) -> some View {
        let duration = max(player.durationMs, 1)
        let position = scrubPosition ?? player.playhead
        return Canvas { ctx, size in
            let barY = full ? size.height - 8 : size.height - 1
            let inset: CGFloat = full ? 7 : 0
            let span = max(size.width - 2 * inset, 1)
            func x(_ ms: Int64) -> CGFloat { inset + span * CGFloat(min(max(Double(ms) / Double(duration), 0), 1)) }
            func bar(_ from: CGFloat, _ to: CGFloat, _ color: Color) {
                ctx.fill(Path(CGRect(x: from, y: barY - 1, width: max(to - from, 0), height: 2)), with: .color(color))
            }
            bar(inset, inset + span, Color.white.opacity(0x33 / 255.0))
            bar(inset, x(min(player.bufferedMs, duration)), Color.white.opacity(0xCC / 255.0))
            bar(inset, x(position), .white)
            if full {
                let r: CGFloat = scrubPosition == nil ? 5 : 7
                ctx.fill(Path(ellipseIn: CGRect(x: x(position) - r, y: barY - r, width: 2 * r, height: 2 * r)), with: .color(.white))
            }
        }
        .frame(height: 48)
        .overlay(TouchArea(
            onPress: { p in hideTask?.cancel(); scrubPosition = time(p.x, width, full, duration) },
            onDrag: { p in scrubPosition = time(p.x, width, full, duration) },
            onRelease: { p, _ in
                player.seek(time(p.x, width, full, duration))
                scrubPosition = nil
                resetHide()
            },
            onCancel: { _ in scrubPosition = nil; resetHide() },
            pressImmediately: true))
    }

    private func time(_ x: CGFloat, _ width: CGFloat, _ full: Bool, _ duration: Int64) -> Int64 {
        let inset: CGFloat = full ? 7 : 0
        let f = min(max((x - inset) / max(width - 2 * inset, 1), 0), 1)
        return Int64(Double(f) * Double(duration))
    }

    // MARK: Settings

    /// The settings popup: 150dp wide, 70% black, 8dp from the bottom-right corner of the player.
    private func settingsMenu(_ page: SettingsPage, in size: CGSize) -> some View {
        let zh = systemChinese
        let names = zh ? ["0.25 倍", "0.5 倍", "0.75 倍", "正常", "1.25 倍", "1.5 倍", "2 倍"] : ["0.25x", "0.5x", "0.75x", "Normal", "1.25x", "1.5x", "2x"]
        let selected = PlayerChrome.speeds.indices.min { abs(PlayerChrome.speeds[$0] - player.rate) < abs(PlayerChrome.speeds[$1] - player.rate) } ?? 3
        return ZStack(alignment: .bottomTrailing) {
            Color.clear.contentShape(Rectangle()).onTapGesture { settings = nil; resetHide() }
            VStack(alignment: .leading, spacing: 0) {
                switch page {
                case .main:
                    Button { settings = .speed } label: {
                        HStack(alignment: .top, spacing: 0) {
                            ExoImage(path: ExoIcon.speed, size: 24).padding(.horizontal, 8).padding(.top, 12)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(zh ? "速度" : "Speed").font(.system(size: 14)).foregroundColor(.white)
                                Text(names[selected]).font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                            }
                            .frame(minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 2).padding(.trailing, 4)
                        }
                        .frame(minWidth: 150, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(MaterialPress(shape: Rectangle(), color: .white))
                case .speed:
                    ForEach(PlayerChrome.speeds.indices, id: \.self) { i in
                        Button {
                            player.overrideRate(PlayerChrome.speeds[i])
                            settings = nil
                            resetHide()
                        } label: {
                            HStack(alignment: .top, spacing: 0) {
                                ExoImage(path: ExoIcon.check, size: 24).opacity(i == selected ? 1 : 0).padding(.horizontal, 8).padding(.top, 12)
                                Text(names[i]).font(.system(size: 14)).foregroundColor(.white)
                                    .frame(minHeight: 52, alignment: .leading).padding(.trailing, 4)
                            }
                            .frame(minWidth: 150, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(MaterialPress(shape: Rectangle(), color: .white))
                    }
                }
            }
            .fixedSize()
            .frame(maxHeight: max(size.height - 16, 52))
            .background(Color.black.opacity(0xB3 / 255.0))
            .padding(8)
        }
    }
}
