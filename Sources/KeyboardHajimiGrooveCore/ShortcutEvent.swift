import Foundation

public struct ShortcutMusicEvent: Equatable, Sendable {
    public let keyCode: UInt16
    public let keyName: String
    public let shortcutID: String
    public let sampleClip: SampleClip?
    public let sampleVolume: Float
    public let timestamp: TimeInterval

    public init(
        keyCode: UInt16,
        keyName: String,
        shortcutID: String,
        sampleClip: SampleClip? = nil,
        sampleVolume: Float = 1,
        timestamp: TimeInterval
    ) {
        self.keyCode = keyCode
        self.keyName = keyName
        self.shortcutID = shortcutID
        self.sampleClip = sampleClip
        self.sampleVolume = sampleVolume
        self.timestamp = timestamp
    }
}

public struct BeatPosition: Equatable, Sendable {
    public let bar: Int
    public let beat: Int
    public let step: Int

    public var label: String {
        "\(bar + 1).\(beat + 1).\(step + 1)"
    }
}

public struct BeatBinder: Sendable {
    public let bpm: Double
    public let stepsPerBeat: Int
    private let origin: TimeInterval

    public init(bpm: Double, stepsPerBeat: Int = 4, origin: TimeInterval = 0) {
        self.bpm = bpm
        self.stepsPerBeat = stepsPerBeat
        self.origin = origin
    }

    public func bind(timestamp: TimeInterval) -> BeatPosition {
        let secondsPerStep = 60.0 / bpm / Double(stepsPerBeat)
        let elapsed = max(0, timestamp - origin)
        let absoluteStep = Int((elapsed / secondsPerStep).rounded(.down))
        let stepsPerBar = stepsPerBeat * 4
        let stepInBar = absoluteStep % stepsPerBar

        return BeatPosition(
            bar: absoluteStep / stepsPerBar,
            beat: stepInBar / stepsPerBeat,
            step: stepInBar % stepsPerBeat
        )
    }
}
