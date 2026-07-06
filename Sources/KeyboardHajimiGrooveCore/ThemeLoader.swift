import Foundation

public struct LoadedTheme: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case builtIn(String)
        case file(URL)
    }

    public let theme: MusicTheme
    public let source: Source
}

public enum ThemeLoader {
    public static func load(
        argument: String?,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> LoadedTheme {
        let argument = (argument?.isEmpty == false) ? argument! : ThemeLibrary.defaultThemePath

        if let builtIn = ThemeLibrary.builtIns[argument] {
            return LoadedTheme(theme: builtIn, source: .builtIn(argument))
        }

        let url = URL(fileURLWithPath: argument, relativeTo: currentDirectory).standardizedFileURL
        let data = try Data(contentsOf: url)
        let theme = try JSONDecoder().decode(MusicTheme.self, from: data)
        return LoadedTheme(theme: theme, source: .file(url))
    }
}
