import Foundation

public enum KeyModifier: String, Codable, Hashable, Sendable {
    case command
    case shift
    case option
    case control
    case fn
}

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let keyCode: UInt16
    public let modifiers: [KeyModifier]
    public let sampleClipID: String
    public let sampleVolume: Float

    public init(
        id: String,
        title: String,
        keyCode: UInt16,
        modifiers: [KeyModifier],
        sampleClipID: String,
        sampleVolume: Float = 1
    ) {
        self.id = id
        self.title = title
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.sampleClipID = sampleClipID
        self.sampleVolume = max(0, min(1, sampleVolume))
    }
}

public struct SampleClip: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let filePath: String
    public let startTime: Double
    public let duration: Double?
    public let volume: Float

    public init(
        id: String,
        title: String,
        artist: String = "",
        filePath: String,
        startTime: Double = 0,
        duration: Double? = nil,
        volume: Float = 1
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.filePath = filePath
        self.startTime = max(0, startTime)
        self.duration = duration
        self.volume = max(0, min(1, volume))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case filePath
        case startTime
        case duration
        case volume
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            artist: try container.decodeIfPresent(String.self, forKey: .artist) ?? "",
            filePath: try container.decode(String.self, forKey: .filePath),
            startTime: try container.decodeIfPresent(Double.self, forKey: .startTime) ?? 0,
            duration: try container.decodeIfPresent(Double.self, forKey: .duration),
            volume: try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        )
    }
}

public struct MusicTheme: Codable, Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let shortcutBindings: [ShortcutBinding]
    public let sampleClips: [SampleClip]

    public init(
        name: String,
        displayName: String? = nil,
        description: String = "",
        shortcutBindings: [ShortcutBinding],
        sampleClips: [SampleClip]
    ) {
        self.name = name
        self.displayName = displayName ?? name
        self.description = description
        self.shortcutBindings = shortcutBindings
        self.sampleClips = sampleClips
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case description
        case shortcutBindings
        case sampleClips
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
            shortcutBindings: try container.decode([ShortcutBinding].self, forKey: .shortcutBindings),
            sampleClips: try container.decode([SampleClip].self, forKey: .sampleClips)
        )
    }

    public func sampleClip(id: String, volume: Float = 1) -> (clip: SampleClip, volume: Float)? {
        guard let clip = sampleClips.first(where: { $0.id == id }) else {
            return nil
        }

        return (clip, max(0, min(1, clip.volume * volume)))
    }
}
