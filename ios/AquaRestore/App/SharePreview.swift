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
            HStack {
                M3TextButton(title: s.text("Download", "下載")) { save(share: false) }.disabled(working)
                M3Button(title: s.text("Share", "分享"), spinner: working) { save(share: true) }.disabled(working)
            }
            if let notice { MText(notice, size: 12) }
        }
        .sheet(item: $sharing, onDismiss: { Exports.shared.resultActionBusy = false }) { item in
            ActivityShare(url: item.url)
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
private struct ComparisonPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let view = AVPlayerViewController(); view.player = player; view.showsPlaybackControls = false
        return view
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
private struct ActivityShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
