import Foundation
import Testing
@testable import KeyboardHajimiGrooveCore

@Test func defaultThemeLoadsLocalShortcutDrops() throws {
    let loaded = try ThemeLoader.load(
        argument: nil,
        currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )

    #expect(loaded.theme.name == "shortcut-local-drops")
    #expect(loaded.theme.shortcutBindings.contains { $0.id == "command-c-copy" })
    #expect(loaded.theme.sampleClips.contains { $0.id == "drop-copy" })
}

@Test func shortcutBindingCanReferenceSampleClip() throws {
    let json = """
    {
      "name": "shortcut-test",
      "shortcutBindings": [
        {
          "id": "cmd-c",
          "title": "Command+C Copy",
          "keyCode": 8,
          "modifiers": ["command"],
          "sampleClipID": "copy-drop",
          "sampleVolume": 0.8
        }
      ],
      "sampleClips": [
        { "id": "copy-drop", "title": "Copy Drop", "filePath": "/tmp/copy.m4a", "duration": 3.2 }
      ]
    }
    """

    let theme = try JSONDecoder().decode(MusicTheme.self, from: Data(json.utf8))
    let binding = try #require(theme.shortcutBindings.first)
    let sample = try #require(theme.sampleClip(id: binding.sampleClipID, volume: binding.sampleVolume))

    #expect(binding.modifiers == [.command])
    #expect(sample.clip.id == "copy-drop")
    #expect(sample.volume == 0.8)
}

@Test func keyEventAnalyzerSummarizesFrequencyAndIntervals() {
    var analyzer = KeyEventAnalyzer()

    analyzer.record(shortcutEvent(name: "Command+C Copy", timestamp: 10.0))
    analyzer.record(shortcutEvent(name: "Command+C Copy", timestamp: 10.5))
    analyzer.record(shortcutEvent(name: "Command+V Paste", timestamp: 11.0))

    let summary = analyzer.summary(top: 2)
    let copyStats = summary.topKeys.first { $0.keyName == "Command+C Copy" }

    #expect(summary.totalEvents == 3)
    #expect(summary.averageGlobalInterval == 0.5)
    #expect(summary.eventsPerSecond == 3.0)
    #expect(copyStats?.count == 2)
    #expect(copyStats?.averageInterval == 0.5)
}

@Test func keyEventAnalyzerIgnoresLongGapsBetweenSegments() {
    var analyzer = KeyEventAnalyzer(maxLearningGap: 2.0)

    analyzer.record(shortcutEvent(name: "Command+C Copy", timestamp: 10.0))
    analyzer.record(shortcutEvent(name: "Command+C Copy", timestamp: 10.5))
    analyzer.record(shortcutEvent(name: "Command+C Copy", timestamp: 70.5))

    let summary = analyzer.summary(top: 1)
    let copyStats = summary.topKeys.first { $0.keyName == "Command+C Copy" }

    #expect(summary.totalEvents == 3)
    #expect(summary.segmentCount == 2)
    #expect(summary.ignoredGapCount == 1)
    #expect(summary.observedDuration == 0.5)
    #expect(summary.averageGlobalInterval == 0.5)
    #expect(copyStats?.count == 3)
    #expect(copyStats?.averageInterval == 0.5)
    #expect(copyStats?.maximumInterval == 0.5)
}

@Test func beatBinderQuantizesToSixteenthSteps() {
    let clock = BeatBinder(bpm: 120, origin: 10)

    #expect(clock.bind(timestamp: 10).label == "1.1.1")
    #expect(clock.bind(timestamp: 10.125).label == "1.1.2")
    #expect(clock.bind(timestamp: 12).label == "2.1.1")
}

private func shortcutEvent(name: String, timestamp: TimeInterval) -> ShortcutMusicEvent {
    ShortcutMusicEvent(
        keyCode: 8,
        keyName: name,
        shortcutID: "shortcut",
        timestamp: timestamp
    )
}
