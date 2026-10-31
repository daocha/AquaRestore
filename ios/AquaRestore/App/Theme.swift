import SwiftUI

// Material 3 (Compose Material3 1.4.0) recreated in SwiftUI: the color roles, type scale, and the exact
// component specs the Android app gets from Compose, so both apps look and behave alike.

/// The Android app's color scheme, including the baseline roles it does not override.
struct Palette {
    let dark: Bool
    let primary: Color, onPrimary: Color, background: Color, onBackground: Color, surface: Color, surfaceVariant: Color
    let onSurface: Color, onSurfaceVariant: Color
    let primaryContainer: Color, onPrimaryContainer: Color, secondaryContainer: Color, onSecondaryContainer: Color
    let tertiary: Color, outline: Color, outlineVariant: Color, error: Color, errorContainer: Color, dialog: Color

    static let aqua = Color(hex: 0x45DDC2)
    static let night = Color(hex: 0x09191F)

    static let darkScheme = Palette(dark: true, primary: aqua, onPrimary: night, background: night, onBackground: Color(hex: 0xE6E0E9),
        surface: Color(hex: 0x10252D), surfaceVariant: Color(hex: 0x1B333C), onSurface: Color(hex: 0xE3F1F2), onSurfaceVariant: Color(hex: 0x9EB6BC),
        primaryContainer: Color(hex: 0x4F378B), onPrimaryContainer: Color(hex: 0xEADDFF),
        secondaryContainer: Color(hex: 0x4A4458), onSecondaryContainer: Color(hex: 0xE8DEF8),
        tertiary: Color(hex: 0xEFB8C8), outline: Color(hex: 0x938F99), outlineVariant: Color(hex: 0x49454F),
        error: Color(hex: 0xF2B8B5), errorContainer: Color(hex: 0x8C1D18), dialog: Color(hex: 0x2B2930))
    static let lightScheme = Palette(dark: false, primary: Color(hex: 0x007D70), onPrimary: .white, background: Color(hex: 0xF2F7F6),
        onBackground: Color(hex: 0x1D1B20), surface: .white, surfaceVariant: Color(hex: 0xE2EEEB), onSurface: Color(hex: 0x102D35),
        onSurfaceVariant: Color(hex: 0x526E73),
        primaryContainer: Color(hex: 0xEADDFF), onPrimaryContainer: Color(hex: 0x21005D),
        secondaryContainer: Color(hex: 0xE8DEF8), onSecondaryContainer: Color(hex: 0x1D192B),
        tertiary: Color(hex: 0x7D5260), outline: Color(hex: 0x79747E), outlineVariant: Color(hex: 0xCAC4D0),
        error: Color(hex: 0xB3261E), errorContainer: Color(hex: 0xF9DEDC), dialog: Color(hex: 0xECE6F0))

    /// Content of disabled components.
    var disabledContent: Color { onSurface.opacity(0.38) }
    /// Containers and outlines of disabled components.
    var disabledContainer: Color { onSurface.opacity(0.12) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: alpha)
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.darkScheme }
private struct ContentColorKey: EnvironmentKey { static let defaultValue = Palette.darkScheme.onBackground }
private struct TextBaseKey: EnvironmentKey { static let defaultValue = TypeScale.bodyLarge }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    /// Compose's LocalContentColor: what text and icons without an explicit color use.
    var contentColor: Color {
        get { self[ContentColorKey.self] }
        set { self[ContentColorKey.self] = newValue }
    }
    /// Compose's LocalTextStyle: the style that text without explicit values inherits.
    var textBase: TypeScale {
        get { self[TextBaseKey.self] }
        set { self[TextBaseKey.self] = newValue }
    }
}

extension View {
    /// A Compose Row child without a weight: measured at its natural width before the weighted children.
    func unweighted() -> some View { fixedSize(horizontal: true, vertical: false).layoutPriority(1) }

    /// Sets the content color (and the matching foreground style) for everything inside, like a Compose Surface.
    func contentColor(_ color: Color) -> some View { environment(\.contentColor, color).foregroundColor(color) }
    func textBase(_ scale: TypeScale) -> some View { environment(\.textBase, scale) }
}

// MARK: - Typography

/// The Material 3 baseline type scale. Compose applies the style's line height to every line, even when
/// only the font size is overridden, so a 12sp label in body text still takes a 24sp line.
struct TypeScale: Equatable {
    var size: CGFloat
    var lineHeight: CGFloat
    var tracking: CGFloat
    var weight: Font.Weight = .regular

    static let bodyLarge = TypeScale(size: 16, lineHeight: 24, tracking: 0.5)
    static let bodyMedium = TypeScale(size: 14, lineHeight: 20, tracking: 0.25)
    static let labelLarge = TypeScale(size: 14, lineHeight: 20, tracking: 0.1, weight: .medium)
    static let titleLarge = TypeScale(size: 22, lineHeight: 28, tracking: 0)
    static let headlineSmall = TypeScale(size: 24, lineHeight: 32, tracking: 0)
}

/// SF Pro's natural line height relative to its size (ascender + descender + leading).
private let naturalLineHeight: CGFloat = 1.193

private struct TextStyleModifier: ViewModifier {
    @Environment(\.textBase) private var base
    let size: CGFloat?
    let weight: Font.Weight?
    let lineHeight: CGFloat?
    func body(content: Content) -> some View {
        let size = size ?? base.size
        let lineHeight = lineHeight ?? base.lineHeight
        // Spread the extra line height evenly above and below, like Compose's centered line height style.
        let extra = max(0, lineHeight - size * naturalLineHeight)
        content
            .font(.system(size: size, weight: weight ?? base.weight))
            .tracking(base.tracking)
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}

extension View {
    /// Text size (sp), weight and line height on top of the inherited Material text style.
    func sp(_ size: CGFloat? = nil, _ weight: Font.Weight? = nil, lineHeight: CGFloat? = nil) -> some View {
        modifier(TextStyleModifier(size: size, weight: weight, lineHeight: lineHeight))
    }
}

/// Compose `Text`: inherits the content color and text style unless given its own.
struct MText: View {
    @Environment(\.contentColor) private var inherited
    let text: String
    var size: CGFloat? = nil
    var weight: Font.Weight? = nil
    var color: Color? = nil
    var lineHeight: CGFloat? = nil
    var maxLines: Int? = nil
    var align: TextAlignment = .leading

    init(_ text: String, size: CGFloat? = nil, weight: Font.Weight? = nil, color: Color? = nil, lineHeight: CGFloat? = nil,
         maxLines: Int? = nil, align: TextAlignment = .leading) {
        self.text = text; self.size = size; self.weight = weight; self.color = color; self.lineHeight = lineHeight
        self.maxLines = maxLines; self.align = align
    }

    var body: some View {
        Text(text)
            .sp(size, weight, lineHeight: lineHeight)
            .foregroundColor(color ?? inherited)
            .lineLimit(maxLines)
            .truncationMode(.tail)
            .multilineTextAlignment(align)
            .fixedSize(horizontal: false, vertical: maxLines == nil)
    }
}

// MARK: - Surfaces

/// `Surface(shape = RoundedCornerShape(22.dp), color = surface)` holding a padded column, as in the Android app.
struct Panel<Content: View>: View {
    @Environment(\.palette) private var c
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(c.surface))
            .contentColor(c.onSurface)
            .textBase(.bodyLarge)
    }
}

/// Material's pressed state: a 10% layer of the content color over the pressed component.
struct MaterialPress<S: Shape>: ButtonStyle {
    let shape: S
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(shape.fill(color.opacity(configuration.isPressed ? 0.1 : 0)).allowsHitTesting(false))
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.25), value: configuration.isPressed)
    }
}

/// A `Row(Modifier.clickable { ... })` panel header that toggles a section, ending in the expand chevron.
struct ExpandHeader<Content: View>: View {
    @Environment(\.contentColor) private var color
    let expanded: Bool
    let toggle: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            content
            MIcon(expanded ? .expandLess : .expandMore, size: 24, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 1)) { toggle() } }
        .accessibilityAddTraits(.isButton)
    }
}

/// Compose's `AnimatedVisibility` defaults: fade together with an expand from the top.
extension AnyTransition {
    static var expandVertically: AnyTransition {
        .opacity.combined(with: .modifier(active: ClipReveal(fraction: 0), identity: ClipReveal(fraction: 1)))
    }
}

private struct ClipReveal: ViewModifier {
    let fraction: CGFloat
    func body(content: Content) -> some View {
        content.mask(GeometryReader { geo in
            Rectangle().frame(height: geo.size.height * fraction).frame(maxHeight: .infinity, alignment: .top)
        })
    }
}

// MARK: - Buttons

/// Material 3 buttons. Visually 40dp tall; like Compose they reserve a 48dp touch target in the layout.
struct M3Button: View {
    enum Style { case filled, outlined, custom(container: Color, content: Color) }

    @Environment(\.palette) private var c
    @Environment(\.isEnabled) private var enabled
    let title: String
    var icon: MaterialIcon? = nil
    var iconSize: CGFloat = 24
    var iconSpacing: CGFloat = 8
    var style: Style = .filled
    var height: CGFloat = 40
    var corner: CGFloat? = nil
    var fontSize: CGFloat? = nil
    var spinner = false
    var fullWidth = false
    let action: () -> Void

    private var colors: (container: Color, content: Color, border: Color?) {
        switch style {
        case .filled: return enabled ? (c.primary, c.onPrimary, nil) : (c.disabledContainer, c.disabledContent, nil)
        case .outlined: return (.clear, enabled ? c.primary : c.disabledContent, enabled ? c.outlineVariant : c.disabledContainer)
        case .custom(let container, let content): return enabled ? (container, content, nil) : (c.disabledContainer, c.disabledContent, nil)
        }
    }

    var body: some View {
        let colors = colors
        let shape = RoundedRectangle(cornerRadius: corner ?? height / 2, style: .continuous)
        Button(action: action) {
            HStack(spacing: 0) {
                if spinner { CircularProgress(size: 16, stroke: 2, color: c.primary).padding(.trailing, iconSpacing) }
                else if let icon { MIcon(icon, size: iconSize, color: colors.content).padding(.trailing, iconSpacing) }
                Text(title).sp(fontSize, nil, lineHeight: TypeScale.labelLarge.lineHeight).lineLimit(1)
                    .foregroundColor(colors.content)
            }
            .textBase(.labelLarge)
            .padding(.horizontal, 24)
            .frame(minWidth: 58)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(shape.fill(colors.container))
            .overlay { if let border = colors.border { shape.strokeBorder(border, lineWidth: 1) } }
            .contentShape(shape)
        }
        .buttonStyle(MaterialPress(shape: shape, color: colors.content))
        .frame(minHeight: 48)
    }
}

/// Material 3 text button: primary label, 12dp padding, 40dp tall within a 48dp touch target.
struct M3TextButton: View {
    @Environment(\.palette) private var c
    @Environment(\.isEnabled) private var enabled
    let title: String
    var fontSize: CGFloat? = nil
    var padding: CGFloat = 12
    var icon: MaterialIcon? = nil
    var iconTrailing = false
    let action: () -> Void
    var body: some View {
        let color = enabled ? c.primary : c.disabledContent
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon, !iconTrailing { MIcon(icon, size: 18, color: color) }
                Text(title).sp(fontSize, nil, lineHeight: TypeScale.labelLarge.lineHeight).lineLimit(1).foregroundColor(color)
                if let icon, iconTrailing { MIcon(icon, size: 18, color: color) }
            }
            .textBase(.labelLarge)
            .padding(.horizontal, padding)
            .frame(minWidth: 58)
            .frame(height: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(MaterialPress(shape: Capsule(), color: color))
        .frame(minHeight: 48)
    }
}

/// Material 3 icon button (40dp, in a 48dp touch target); `filled` is FilledIconButton.
struct M3IconButton: View {
    @Environment(\.palette) private var c
    @Environment(\.isEnabled) private var enabled
    @Environment(\.contentColor) private var inherited
    let icon: MaterialIcon
    let label: String
    var filled = false
    var color: Color? = nil
    let action: () -> Void
    var body: some View {
        let content = filled ? (enabled ? c.onPrimary : c.disabledContent) : (enabled ? (color ?? inherited) : c.disabledContent)
        Button(action: action) {
            ZStack {
                if filled { Circle().fill(enabled ? c.primary : c.disabledContainer) }
                MIcon(icon, size: 24, color: content)
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(MaterialPress(shape: Circle(), color: content))
        .frame(width: 48, height: 48)
        .accessibilityLabel(label)
    }
}

/// Material 3 filter chip without a leading icon: 32dp tall in a 48dp touch target, 16dp side padding,
/// outline-variant border when unselected, secondary container when selected.
struct FilterChip: View {
    @Environment(\.palette) private var c
    @Environment(\.isEnabled) private var enabled
    let label: String
    let selected: Bool
    var fontSize: CGFloat? = nil
    let action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let content = enabled ? (selected ? c.onSecondaryContainer : c.onSurfaceVariant) : c.disabledContent
        Button(action: action) {
            Text(label).sp(fontSize, nil, lineHeight: TypeScale.labelLarge.lineHeight).lineLimit(1)
                .foregroundColor(content)
                .textBase(.labelLarge)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background {
                    if selected { shape.fill(enabled ? c.secondaryContainer : c.disabledContainer) }
                    else { shape.strokeBorder(enabled ? c.outlineVariant : c.disabledContainer, lineWidth: 1) }
                }
                .contentShape(shape)
        }
        .buttonStyle(MaterialPress(shape: shape, color: content))
        .frame(height: 48)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Left-to-right wrapping row, like Compose's FlowRow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), frames)
    }
}

/// The Android `Choices` helper: a FlowRow of filter chips with 12sp labels.
struct Choices<T: Hashable>: View {
    let items: [(T, String)]
    let selected: T
    let select: (T) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                FilterChip(label: items[i].1, selected: selected == items[i].0, fontSize: 12) { select(items[i].0) }
            }
        }
    }
}

// MARK: - Progress indicators

/// Material 3 (1.4) linear progress indicator: 4dp round-capped line, a 4dp gap before the track, and a
/// stop dot at the end when determinate. Indeterminate uses Compose's two-line keyframes.
struct LinearProgress: View {
    @Environment(\.palette) private var c
    let value: Double?

    var body: some View {
        if let value {
            Canvas { ctx, size in draw(&ctx, size, segments: [(0, min(max(value, 0), 1))], determinate: true) }
                .frame(height: 4)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.75) * 1000
                    func line(_ delay: Double, _ duration: Double) -> Double {
                        let p = min(max((t - delay) / duration, 0), 1)
                        return LinearProgress.emphasizedAccelerate(p)
                    }
                    let firstHead = line(0, 1000), firstTail = line(250, 1000)
                    let secondHead = line(650, 850), secondTail = line(900, 850)
                    drawIndeterminate(&ctx, size, firstHead, firstTail, secondHead, secondTail)
                }
            }
            .frame(height: 4)
        }
    }

    /// Material's emphasized-accelerate easing, cubic-bezier(0.3, 0, 0.8, 0.15).
    static func emphasizedAccelerate(_ x: Double) -> Double { cubicBezier(x, 0.3, 0, 0.8, 0.15) }

    static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            let bx = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t
            if bx < x { lo = t } else { hi = t }
        }
        return 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t
    }

    private func line(_ ctx: inout GraphicsContext, _ size: CGSize, _ start: Double, _ end: Double, _ color: Color) {
        guard end - start > 0 else { return }
        let cap = size.height / 2
        let a = min(max(CGFloat(start) * size.width, cap), size.width - cap)
        let b = min(max(CGFloat(end) * size.width, cap), size.width - cap)
        var path = Path()
        path.move(to: CGPoint(x: a, y: cap)); path.addLine(to: CGPoint(x: b, y: cap))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: size.height, lineCap: .round))
    }

    private func gapFraction(_ size: CGSize) -> Double { Double((4 + size.height) / max(size.width, 1)) }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, segments: [(Double, Double)], determinate: Bool) {
        let progress = segments[0].1
        let gap = gapFraction(size)
        let trackStart = progress + min(progress, gap)
        if trackStart <= 1 { line(&ctx, size, trackStart, 1, c.secondaryContainer) }
        line(&ctx, size, 0, progress, c.primary)
        // Stop indicator: a 4dp dot at the end of the track.
        let r = min(4, size.height) / 2
        ctx.fill(Path(ellipseIn: CGRect(x: size.width - 2 * r, y: size.height / 2 - r, width: 2 * r, height: 2 * r)), with: .color(c.primary))
    }

    private func drawIndeterminate(_ ctx: inout GraphicsContext, _ size: CGSize, _ firstHead: Double, _ firstTail: Double,
                                   _ secondHead: Double, _ secondTail: Double) {
        let gap = gapFraction(size)
        if firstHead < 1 - gap { line(&ctx, size, firstHead > 0 ? firstHead + gap : 0, 1, c.secondaryContainer) }
        if firstHead - firstTail > 0 { line(&ctx, size, firstTail, firstHead, c.primary) }
        if firstTail > gap {
            let start = secondHead > 0 ? secondHead + gap : 0
            let end = firstTail < 1 ? firstTail - gap : 1
            line(&ctx, size, start, end, c.secondaryContainer)
        }
        if secondHead - secondTail > 0 { line(&ctx, size, secondTail, secondHead, c.primary) }
        if secondTail > gap { line(&ctx, size, 0, secondTail < 1 ? secondTail - gap : 1, c.secondaryContainer) }
    }
}

/// The Android `Progress` helper: the bar, plus the percentage underneath when known.
struct Progress: View {
    @Environment(\.palette) private var c
    let value: Int?
    var body: some View {
        if let value {
            VStack(alignment: .leading, spacing: 0) {
                LinearProgress(value: Double(value) / 100)
                MText("\(value)%", size: 13, color: c.primary)
            }
        } else {
            LinearProgress(value: nil)
        }
    }
}

/// Indeterminate circular indicator: a rotating arc that grows and shrinks.
struct CircularProgress: View {
    var size: CGFloat = 40
    var stroke: CGFloat = 4
    var color: Color
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle = t.truncatingRemainder(dividingBy: 1.333) / 1.333
            let grow = cycle < 0.5 ? cycle * 2 : 1 - (cycle - 0.5) * 2
            let sweep = 0.03 + 0.72 * LinearProgress.cubicBezier(grow, 0.4, 0, 0.2, 1)
            let rotation = (t.truncatingRemainder(dividingBy: 1.568) / 1.568) * 360
            Circle().trim(from: 0, to: sweep)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(rotation + (cycle >= 0.5 ? (cycle - 0.5) * 2 * 260 : 0)))
                .padding(stroke / 2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Slider

/// Material 3 (1.4) slider: a 16dp rounded track split by a 4 x 44dp handle with 6dp gaps on each side,
/// a 4dp stop dot at the end, and a 48dp touch height. Touching the track jumps the value there; horizontal
/// drags follow the finger while vertical drags scroll the page. The handle narrows to 2dp while pressed.
struct M3Slider: View {
    @Environment(\.palette) private var c
    @Environment(\.isEnabled) private var enabled
    let value: Float
    let range: ClosedRange<Float>
    let onChange: (Float) -> Void
    var accessibility = ""
    @State private var pressed = false

    var body: some View {
        GeometryReader { geo in
            let handle: CGFloat = pressed ? 2 : 4
            let trackWidth = max(geo.size.width - 4, 1)
            let fraction = CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / max(range.upperBound - range.lowerBound, .ulpOfOne))
            Canvas { ctx, size in
                let midY = size.height / 2
                let active = enabled ? c.primary : c.disabledContent
                let inactive = enabled ? c.secondaryContainer : c.disabledContainer
                let corner: CGFloat = 8, inside: CGFloat = 2, gap = handle / 2 + 6
                let valueX = trackWidth * fraction
                func track(_ x0: CGFloat, _ x1: CGFloat, leading: CGFloat, trailing: CGFloat, _ color: Color) {
                    let rect = CGRect(x: 2 + x0, y: midY - 8, width: x1 - x0, height: 16)
                    ctx.fill(Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: leading, bottomLeading: leading,
                                                                                     bottomTrailing: trailing, topTrailing: trailing)),
                             with: .color(color))
                }
                if valueX + gap < trackWidth - gap - corner {
                    track(valueX + gap, trackWidth, leading: inside, trailing: corner, inactive)
                    let dot = CGRect(x: 2 + trackWidth - corner - 2, y: midY - 2, width: 4, height: 4)
                    ctx.fill(Path(ellipseIn: dot), with: .color(active))
                }
                if valueX - gap > corner { track(0, valueX - gap, leading: corner, trailing: inside, active) }
                let thumb = CGRect(x: 2 + valueX - handle / 2, y: midY - 22, width: handle, height: 44)
                ctx.fill(Path(roundedRect: thumb, cornerRadius: handle / 2), with: .color(active))
            }
            .overlay(TouchArea(
                onPress: { p in guard enabled else { return }; pressed = true; set(p.x, trackWidth) },
                onDrag: { p in guard enabled else { return }; set(p.x, trackWidth) },
                onRelease: { _, _ in pressed = false },
                onCancel: { _ in pressed = false },
                pressImmediately: true))
        }
        .frame(height: 48)
        .animation(.easeOut(duration: 0.15), value: pressed)
        .accessibilityElement()
        .accessibilityLabel(accessibility)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            onChange(min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound))
        }
    }

    private func set(_ x: CGFloat, _ trackWidth: CGFloat) {
        let f = Float(min(max((x - 2) / trackWidth, 0), 1))
        onChange(range.lowerBound + f * (range.upperBound - range.lowerBound))
    }
}

// MARK: - Dialog

/// Material 3 AlertDialog: surface-container-high card with 28dp corners and 24dp padding, a headline-small
/// title, body-medium supporting text in on-surface-variant, and right-aligned buttons, over a dimmed window.
struct M3Dialog<Body: View, Buttons: View>: View {
    @Environment(\.palette) private var c
    let title: String
    let dismiss: () -> Void
    @ViewBuilder var content: Body
    @ViewBuilder var buttons: Buttons

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: dismiss)
                VStack(alignment: .leading, spacing: 0) {
                    MText(title, color: c.onSurface).textBase(.headlineSmall).padding(.bottom, 16)
                    content
                        .contentColor(c.onSurfaceVariant)
                        .textBase(.bodyMedium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FlowLayout(spacing: 8) { buttons }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 24 - 4)
                }
                .padding(24)
                .frame(width: min(560, max(280, geo.size.width - 48)))
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(c.dialog))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity)
    }
}

/// Scrolls only when the content is taller than `maxHeight`; a ScrollView alone would always take all of it.
struct ScrollIfNeeded<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var measured: CGFloat = 0

    var body: some View {
        ScrollView {
            content.background(GeometryReader { geo in Color.clear.preference(key: HeightKey.self, value: geo.size.height) })
        }
        .onPreferenceChange(HeightKey.self) { measured = $0 }
        .frame(height: measured == 0 ? maxHeight : min(measured, maxHeight))
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
