import SwiftUI

@main
struct AquaRestoreApp: App {
    @StateObject private var model = EditorModel()
    var body: some Scene {
        WindowGroup { RootView(model: model) }
    }
}

/// Language and appearance follow the system by default, and the choice is remembered.
struct RootView: View {
    @ObservedObject var model: EditorModel
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let chinese = model.language == "zh" || (model.language == "system" && (Locale.preferredLanguages.first ?? "").hasPrefix("zh"))
        let dark = model.theme == "dark" || (model.theme == "system" && systemScheme == .dark)
        let palette = dark ? Palette.darkScheme : Palette.lightScheme
        let forced: ColorScheme? = model.theme == "dark" ? .dark : (model.theme == "light" ? .light : nil)
        GeometryReader { geo in
            EditorView(model: model)
                .environment(\.screenHeight, geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
                .environment(\.compact, geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom < 500)
        }
        .environment(\.palette, palette)
        .environment(\.strings, Strings(chinese: chinese))
        // `Surface(color = background)`: content defaults to on-background in the body-large style.
        .contentColor(palette.onBackground)
        .textBase(.bodyLarge)
        .background(palette.background.ignoresSafeArea())
        .preferredColorScheme(forced)
    }
}
