import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Everything that needs UIKit lives here, so the rest of the app only uses SwiftUI and AVFoundation.

#if canImport(UIKit)
/// Hosts an `AVPlayerLayer`. The player's video composition decides what each frame looks like.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer?

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

/// Touch handling with Compose's semantics: `onPress` fires on touch-down (when `pressImmediately`), a drag
/// starts only once the finger moves horizontally (vertical movement is left to the scroll view around it),
/// and `onRelease` reports whether the touch became a drag. A tap is a release without a drag.
struct TouchArea: UIViewRepresentable {
    var onPress: ((CGPoint) -> Void)? = nil
    var onDragStart: ((CGPoint) -> Void)? = nil
    var onDrag: ((CGPoint) -> Void)? = nil
    var onRelease: ((CGPoint, Bool) -> Void)? = nil
    /// Called with whether a drag was in progress (a scroll taking over a touch is not a drag).
    var onCancel: ((Bool) -> Void)? = nil
    var pressImmediately = false

    final class TouchView: UIView, UIGestureRecognizerDelegate {
        var area: TouchArea
        private var tracking = false
        private var dragging = false
        private var start = CGPoint.zero
        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false
            pan.maximumNumberOfTouches = 1
            return pan
        }()

        init(_ area: TouchArea) {
            self.area = area
            super.init(frame: .zero)
            backgroundColor = .clear
            isMultipleTouchEnabled = false
            addGestureRecognizer(pan)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            tracking = true
            dragging = false
            start = touch.location(in: self)
            if area.pressImmediately { area.onPress?(start) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard tracking, let touch = touches.first else { return }
            finish(touch.location(in: self))
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            // A drag in progress is finished by the pan recognizer; otherwise the scroll view took the touch.
            if dragging { return }
            cancel(dragged: false)
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: self)
            switch gesture.state {
            case .began:
                if !tracking { tracking = true; start = point }
                dragging = true
                area.onDragStart?(start)
                area.onDrag?(point)
            case .changed:
                area.onDrag?(point)
            case .ended:
                if tracking { finish(point) }
            case .cancelled, .failed:
                cancel(dragged: dragging)
            default:
                break
            }
        }

        private func finish(_ point: CGPoint) {
            tracking = false
            let dragged = dragging
            dragging = false
            area.onRelease?(point, dragged)
        }

        private func cancel(dragged: Bool) {
            guard tracking else { return }
            tracking = false
            dragging = false
            area.onCancel?(dragged)
        }

        /// Only horizontal drags; vertical ones belong to the scroll view.
        override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === pan else { return super.gestureRecognizerShouldBegin(gesture) }
            let velocity = pan.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y)
        }
    }

    func makeUIView(context: Context) -> TouchView { TouchView(self) }
    func updateUIView(_ view: TouchView, context: Context) { view.area = self }
}

enum Platform {
    @MainActor static func openPhotos() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
    @MainActor static func keepScreenAwake(_ on: Bool) { UIApplication.shared.isIdleTimerDisabled = on }
    @MainActor static func copy(_ text: String) { UIPasteboard.general.string = text }
    static var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }
}

extension View {
    /// Full-screen viewer: hide the status bar and home indicator.
    func hideSystemBars(_ hidden: Bool) -> some View {
        statusBarHidden(hidden).persistentSystemOverlays(hidden ? .hidden : .automatic)
    }
}
#else
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { (view.layer as? AVPlayerLayer)?.player = player }
}

struct TouchArea: View {
    var onPress: ((CGPoint) -> Void)? = nil
    var onDragStart: ((CGPoint) -> Void)? = nil
    var onDrag: ((CGPoint) -> Void)? = nil
    var onRelease: ((CGPoint, Bool) -> Void)? = nil
    var onCancel: ((Bool) -> Void)? = nil
    var pressImmediately = false
    @State private var began = false
    @State private var dragging = false
    var body: some View {
        Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if !began { began = true; if pressImmediately { onPress?(drag.startLocation) } }
                if !dragging && abs(drag.translation.width) > 8 && abs(drag.translation.width) > abs(drag.translation.height) {
                    dragging = true; onDragStart?(drag.startLocation)
                }
                if dragging { onDrag?(drag.location) }
            }
            .onEnded { drag in onRelease?(drag.location, dragging); began = false; dragging = false })
    }
}

enum Platform {
    @MainActor static func openPhotos() {}
    @MainActor static func keepScreenAwake(_ on: Bool) {}
    @MainActor static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    static var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }
}

extension View {
    func hideSystemBars(_ hidden: Bool) -> some View { self }
}
#endif
