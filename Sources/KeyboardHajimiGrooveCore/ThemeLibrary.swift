import Foundation

public enum ThemeLibrary {
    public static let defaultThemePath = "Themes/shortcut-local-drops.json"
    public static let builtIns: [String: MusicTheme] = [:]

    public static var builtInNames: [String] {
        builtIns.keys.sorted()
    }
}
