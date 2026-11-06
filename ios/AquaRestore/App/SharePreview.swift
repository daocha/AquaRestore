import SwiftUI
import AVKit

struct SharePreview: View {
    let items: [ShareMedia]
    @Environment(\.strings) private var s
    @State private var page = 0
    @State private var working = false
    @State private var notice: String?
    @State private var saved: Set<UUID> = []
    @State private var sharing: ShareMedia?

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Group {
                        if item.video { LoopingComparison(url: item.url, active: page == index) }
                        else if let image = UIImage(contentsOfFile: item.url.path) { Image(uiImage: image).resizable().scaledToFit() }
                    }.tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 250).disabled(working)
            ComparisonActions(working: working, download: { save(share: false) }, share: { save(share: true) })
            if let notice { MText(notice, size: 12) }
        }
        .sheet(item: $sharing, onDismiss: { Exports.shared.resultActionBusy = false }) { item in
            ActivityShare(items: [item.url])
        }
    }
    private func save(share: Bool) {
        let item = items[page]
        working = true; notice = nil; Exports.shared.resultActionBusy = true
        Task {
            do {
                if !saved.contains(item.id) {
                    try await PhotoSaver.save(item.url, video: item.video, name: "AquaRestore_Comparison.\(item.url.pathExtension)")
                    saved.insert(item.id)
                }
                if share { sharing = item }
                else { notice = s.text("Saved to your Photos library", "已儲存至相簿"); Exports.shared.resultActionBusy = false }
            } catch { notice = s.text("Could not save. Please try again.", "無法儲存，請再試一次。"); Exports.shared.resultActionBusy = false }
            working = false
        }
    }
}

private struct LoopingComparison: View {
    let url: URL
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    var body: some View {
        ComparisonPlayer(player: player)
            .onAppear {
                player.isMuted = true
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
                if active { player.play() }
            }
            .onChange(of: active) { if $0 { player.play() } else { player.pause() } }
            .onChange(of: scenePhase) { if $0 == .active && active { player.play() } else { player.pause() } }
            .onDisappear { player.pause(); looper = nil; player.removeAllItems() }
    }
}
/// A bare player layer. AVPlayerViewController inside the paging TabView can go blank when the view updates, as it does
/// when the collage arrives while the video is already playing; a layer keeps drawing its player through any update.
private struct ComparisonPlayer: UIViewRepresentable {
    let player: AVPlayer
    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> LayerView {
        let view = LayerView(); view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect; view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
struct ActivityShare: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ComparisonActions: View {
    let working: Bool
    let download: () -> Void
    let share: () -> Void
    @Environment(\.strings) private var s
    var body: some View {
        HStack {
            M3TextButton(title: s.text("Download", "下載"), action: download)
                .fixedSize(horizontal: true, vertical: false).disabled(working)
            M3Button(title: s.text("Share", "分享"), action: share)
                .fixedSize(horizontal: true, vertical: false).disabled(working)
            CircularProgress(size: 16, stroke: 2, color: .gray).opacity(working ? 1 : 0).frame(width: 20)
        }
    }
}
