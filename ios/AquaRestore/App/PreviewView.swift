import SwiftUI

/// The Android `Preview` composable: pinned to the top of the editor, with the media, its tags, the file-details and
/// full-screen buttons, and the clip controls under a video. Full screen fills the screen; the media is centred
/// above the controls and can be pinched up to 5×, with Compare, the clip controls and Adjust on top.
struct PreviewView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var player: PlayerController
    @ObservedObject var ui: ClipUI
    let exporting: Bool
    @Binding var maximized: Bool
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    @Environment(\.screenHeight) private var screenHeight
    @State private var adjusting = false
    @State private var infoOpen = false
    @State private var controlsHeight: CGFloat = 0
    @State private var previewSize: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var pan: CGPoint = .zero

    /// Full screen: the media is centred in the space above the controls instead of in the whole screen.
    private var lift: CGFloat {
        guard maximized, let source = model.source else { return 0 }
        return FullScreenLayout.lift(width: previewSize.width, height: previewSize.height, controls: controlsHeight,
                                  mediaWidth: source.width, mediaHeight: source.height)
    }

    /// The video's controls float over it in full screen, once the player exists.
    private var clipControls: Bool {
        maximized && model.previewURL != nil && player.player != nil && (model.source?.durationMs ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.black
                mediaLayer
                if maximized { TransformArea { centroid, panBy, factor in transform(centroid, panBy, factor) } }
                tags
                if !maximized, model.source != nil { infoButton }
                fullscreenButton
                if maximized { maximizedOverlay }
            }
            .frame(height: maximized ? nil : min(max(screenHeight * 0.24, 72), 250))
            .frame(maxWidth: .infinity, maxHeight: maximized ? .infinity : nil)
            .background(GeometryReader { geo in
                Color.clear.onAppear { previewSize = geo.size }.onChange(of: geo.size) { previewSize = $0 }
            })
            .clipShape(RoundedRectangle(cornerRadius: maximized ? 0 : 20, style: .continuous))
            .accessibilityIdentifier("mediaPreview")
            // A video's Compare is in its play row, under the preview.
            if !maximized, model.source.map({ $0.video && $0.durationMs > 0 }) != true {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    CompareButton(model: model)
                }
            }
        }
        .onChange(of: maximized) { value in
            resetZoom()
            infoOpen = false
            model.setDetailWanted(value)
        }
        .onChange(of: model.source) { _ in
            resetZoom()
            infoOpen = false
            model.setDetailWanted(maximized)
        }
        .onDisappear { model.setCompare(false) }
    }

    // MARK: Media

    private var mediaLayer: some View {
        media
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(maximized ? zoom : 1)
            .offset(x: maximized ? pan.x : 0, y: (maximized ? pan.y : 0) + lift)
            .animation(.easeInOut(duration: 0.25), value: lift)
            .clipped()
    }

    @ViewBuilder private var media: some View {
        if model.previewURL != nil {
            VideoSurface(player: player)
        } else if let image = photo {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
                .accessibilityLabel(s.text("Media preview", "素材預覽"))
        }
    }

    /// The sharper full-screen copy once it is graded with the current settings, else the preview-size one.
    private var photo: CGImage? {
        if model.compare { return (maximized ? model.detailOriginal : nil) ?? model.previewOriginalImage }
        if maximized, let detail = model.detailGraded, detail.grade == model.grade { return detail.image }
        return model.previewGraded ?? model.previewOriginalImage
    }

    private func resetZoom() {
        zoom = 1
        pan = .zero
    }

    private func transform(_ centroid: CGPoint, _ panBy: CGSize, _ factor: CGFloat) {
        let next = FullScreenLayout.transformed(scale: zoom, pan: pan, size: previewSize, lift: lift,
                                             centroid: centroid, panBy: panBy, zoom: factor)
        zoom = next.scale
        pan = next.pan
    }

    // MARK: Overlays

    private var tags: some View {
        HStack(spacing: 6) {
            if let source = model.source { PreviewTag(text: source.video ? s.text("VIDEO", "影片") : s.text("PHOTO", "照片")) }
            PreviewTag(text: model.compare ? s.text("ORIGINAL", "原色") : s.text("RESTORED", "還原後"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// The file name and HDR format, kept behind a small button so they take no room on the editor.
    private var infoButton: some View {
        ZStack(alignment: .bottomTrailing) {
            if infoOpen, let source = model.source {
                Color.clear.contentShape(Rectangle()).onTapGesture { infoOpen = false }
                VStack(alignment: .leading, spacing: 4) {
                    MText(source.name, size: 13, weight: .medium, color: c.onSurface, maxLines: 3)
                    if source.isHdr {
                        MText("\(source.hdrName) · 10-bit · BT.2020 · " + s.text("HDR preserved", "保留 HDR"),
                              size: 12, color: c.primary, maxLines: 2)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: 300, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c.surface).shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2))
                .padding(.trailing, 8).padding(.bottom, 8 + 32 + 6)
            }
            Button { infoOpen.toggle() } label: {
                MIcon(.info, size: 20, color: .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .contentShape(Circle())
            }
            .buttonStyle(MaterialPress(shape: Circle(), color: .white))
            .accessibilityLabel(s.text("File details", "檔案資訊"))
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    /// `Surface(onClick, CircleShape, black 65%)`, 36dp, 8dp from the top-right corner.
    private var fullscreenButton: some View {
        Button { maximized.toggle() } label: {
            MIcon(maximized ? .fullscreenExit : .fullscreen, size: 22, color: .white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.65)))
                .contentShape(Circle())
        }
        .buttonStyle(MaterialPress(shape: Circle(), color: .white))
        .accessibilityLabel(maximized ? s.text("Exit full screen", "結束全螢幕") : s.text("Full screen", "全螢幕"))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// The clip controls (or Compare, for a photo) and Adjust over the full-screen media; the panel floats over it.
    private var maximizedOverlay: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                if clipControls, let source = model.source {
                    ClipControls(model: model, player: player, ui: ui, duration: source.durationMs, enabled: !exporting)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                HStack(spacing: 8) {
                    // A video's Compare is in its play row.
                    if !clipControls { CompareButton(model: model) }
                    M3Button(title: adjusting ? s.text("Hide", "收起") : s.text("Adjust", "調整"), icon: adjusting ? .expandMore : .tune,
                             iconSize: 16, iconSpacing: 6, style: .custom(container: Color.black.opacity(0.65), content: .white)) { adjusting.toggle() }
                        .accessibilityIdentifier("fullScreenAdjust")
                }
                if adjusting {
                    FullScreenAdjustments(model: model, enabled: !exporting, maxHeight: screenHeight * 0.4)
                } else {
                    Spacer().frame(height: 16)
                }
            }
            .background(GeometryReader { geo in
                Color.clear.onAppear { controlsHeight = geo.size.height }.onChange(of: geo.size.height) { controlsHeight = $0 }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewTag: View {
    let text: String
    var body: some View {
        MText(text, size: 10, color: .white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.65)))
    }
}

/// Intensity and advanced sliders over the full-screen preview, so corrections can be judged at full size.
struct FullScreenAdjustments: View {
    @ObservedObject var model: EditorModel
    let enabled: Bool
    let maxHeight: CGFloat
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s

    var body: some View {
        ScrollIfNeeded(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: 0) {
                if model.analysis != nil {
                    HStack(alignment: .center, spacing: 0) {
                        MText(s.text("Restore intensity", "還原強度"), size: 13, weight: .medium).frame(maxWidth: .infinity, alignment: .leading)
                        MText("\(Int((model.grade.strength * 100).rounded()))%", weight: .bold, color: c.primary).unweighted()
                        M3TextButton(title: s.text("Reset", "重設")) { model.reset() }.disabled(!enabled).unweighted()
                    }
                    M3Slider(value: model.grade.strength, range: 0...1, onChange: { v in var g = model.grade; g.strength = v; model.setGrade(g) },
                             accessibility: s.text("Restore intensity", "還原強度")).disabled(!enabled)
                }
                AdvancedSliders(model: model, enabled: enabled)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(c.surface.opacity(0.85)))
        .contentColor(c.onSurface)
        .padding(.horizontal, 12).padding(.bottom, 8)
        .accessibilityIdentifier("fullScreenAdjustments")
    }
}
