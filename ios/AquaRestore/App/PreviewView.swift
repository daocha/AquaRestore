import SwiftUI

/// The Android `Preview` composable: pinned to the top of the editor, with the media, its tags, the
/// full-screen button and "Hold to compare"; in full screen it fills the screen with compare and Adjust on top.
struct PreviewView: View {
    @ObservedObject var model: EditorModel
    let exporting: Bool
    @Binding var maximized: Bool
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    @Environment(\.screenHeight) private var screenHeight
    @State private var adjusting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.black
                media
                tags
                fullscreenButton
                if maximized { maximizedOverlay }
            }
            .frame(height: maximized ? nil : min(max(screenHeight * 0.24, 72), 250))
            .frame(maxWidth: .infinity, maxHeight: maximized ? .infinity : nil)
            .clipShape(RoundedRectangle(cornerRadius: maximized ? 0 : 20, style: .continuous))
            .accessibilityIdentifier("mediaPreview")
            if !maximized {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let source = model.source {
                            MText(source.name, size: 12, color: c.onSurfaceVariant, maxLines: 1)
                            if source.isHdr {
                                MText("\(source.hdrName) · 10-bit · BT.2020 · " + s.text("HDR preserved", "保留 HDR"),
                                      size: 11, color: c.primary, maxLines: 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(width: 8)
                    CompareButton(model: model, overlay: false).unweighted()
                }
            }
        }
        .onDisappear { model.setCompare(false) }
    }

    @ViewBuilder private var media: some View {
        if model.previewURL != nil {
            VideoSurface(player: model.player)
        } else if let image = model.compare ? model.previewOriginalImage : (model.previewGraded ?? model.previewOriginalImage) {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
                .accessibilityLabel(s.text("Media preview", "素材預覽"))
        }
    }

    private var tags: some View {
        HStack(spacing: 6) {
            PreviewTag(text: model.compare ? s.text("ORIGINAL", "原色") : s.text("RESTORED", "還原後"))
            if let source = model.source { PreviewTag(text: source.video ? s.text("VIDEO", "影片") : s.text("PHOTO", "照片")) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
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

    /// Compare and Adjust over the full-screen video, above the player's time bar; the panel floats over the video.
    private var maximizedOverlay: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                CompareButton(model: model, overlay: true)
                M3Button(title: adjusting ? s.text("Hide", "收起") : s.text("Adjust", "調整"), icon: adjusting ? .expandMore : .tune,
                         iconSize: 16, iconSpacing: 6, style: .custom(container: Color.black.opacity(0.65), content: .white)) { adjusting.toggle() }
                    .accessibilityIdentifier("fullScreenAdjust")
            }
            if adjusting {
                FullScreenAdjustments(model: model, enabled: !exporting, maxHeight: screenHeight * 0.4)
            } else {
                Spacer().frame(height: 80)
            }
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

/// "Hold to compare": the original shows while the button is pressed and returns on release or cancel.
/// Outlined below the preview, filled black 65% over the full-screen video.
struct CompareButton: View {
    @ObservedObject var model: EditorModel
    let overlay: Bool
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s

    var body: some View {
        let content = overlay ? Color.white : c.primary
        let shape = Capsule()
        HStack(spacing: 0) {
            MIcon(.compare, size: 16, color: content).padding(.trailing, 6)
            Text(s.text("Hold to compare", "按住對比原片")).sp(nil, nil, lineHeight: 20).lineLimit(1).foregroundColor(content)
        }
        .textBase(.labelLarge)
        .padding(.horizontal, 24)
        .frame(height: 40)
        .background {
            if overlay { shape.fill(Color.black.opacity(0.65)) } else { shape.strokeBorder(c.outlineVariant, lineWidth: 1) }
        }
        .overlay(shape.fill(content.opacity(model.compare ? 0.1 : 0)).allowsHitTesting(false))
        .overlay(TouchArea(
            onPress: { _ in model.setCompare(true) },
            onRelease: { _, _ in model.setCompare(false) },
            onCancel: { _ in model.setCompare(false) },
            pressImmediately: true))
        .clipShape(shape)
        .frame(minHeight: 48)
        .accessibilityElement()
        .accessibilityLabel(s.text("Hold to compare", "按住對比原片"))
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
                    M3Slider(value: model.grade.strength, range: 0...2, onChange: { v in var g = model.grade; g.strength = v; model.setGrade(g) },
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
