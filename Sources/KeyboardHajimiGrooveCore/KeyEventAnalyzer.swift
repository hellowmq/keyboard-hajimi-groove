import Foundation

public struct KeyTimingStats: Equatable, Sendable {
    public let keyName: String
    public let count: Int
    public let averageInterval: TimeInterval?
    public let minimumInterval: TimeInterval?
    public let maximumInterval: TimeInterval?
}

public struct KeyTimingSummary: Equatable, Sendable {
    public let totalEvents: Int
    public let observedDuration: TimeInterval
    public let segmentCount: Int
    public let ignoredGapCount: Int
    public let maxLearningGap: TimeInterval
    public let eventsPerSecond: Double
    public let averageGlobalInterval: TimeInterval?
    public let topKeys: [KeyTimingStats]
}

private struct KeyTimingAccumulator {
    var count = 0
    var lastTimestamp: TimeInterval?
    var intervalSum: TimeInterval = 0
    var intervalCount = 0
    var minimumInterval: TimeInterval?
    var maximumInterval: TimeInterval?

    mutating func record(timestamp: TimeInterval, maxLearningGap: TimeInterval) {
        if let lastTimestamp {
            let interval = max(0, timestamp - lastTimestamp)

            if interval <= maxLearningGap {
                intervalSum += interval
                intervalCount += 1
                minimumInterval = min(minimumInterval ?? interval, interval)
                maximumInterval = max(maximumInterval ?? interval, interval)
            }
        }

        count += 1
        lastTimestamp = timestamp
    }

    func stats(keyName: String) -> KeyTimingStats {
        KeyTimingStats(
            keyName: keyName,
            count: count,
            averageInterval: intervalCount > 0 ? intervalSum / Double(intervalCount) : nil,
            minimumInterval: minimumInterval,
            maximumInterval: maximumInterval
        )
    }
}

public struct KeyEventAnalyzer {
    public let maxLearningGap: TimeInterval
    private var keyStats: [String: KeyTimingAccumulator] = [:]
    private var lastTimestamp: TimeInterval?
    private var activeDuration: TimeInterval = 0
    private var globalIntervalSum: TimeInterval = 0
    private var globalIntervalCount = 0
    private var segmentCount = 0
    private var ignoredGapCount = 0
    private var totalEvents = 0

    public init(maxLearningGap: TimeInterval = 2.0) {
        self.maxLearningGap = max(0.1, maxLearningGap)
    }

    public mutating func record(_ event: ShortcutMusicEvent) {
        if let lastTimestamp {
            let interval = max(0, event.timestamp - lastTimestamp)

            if interval <= maxLearningGap {
                activeDuration += interval
                globalIntervalSum += interval
                globalIntervalCount += 1
            } else {
                segmentCount += 1
                ignoredGapCount += 1
            }
        } else {
            segmentCount = 1
        }

        var accumulator = keyStats[event.keyName] ?? KeyTimingAccumulator()
        accumulator.record(timestamp: event.timestamp, maxLearningGap: maxLearningGap)
        keyStats[event.keyName] = accumulator

        lastTimestamp = event.timestamp
        totalEvents += 1
    }

    public mutating func reset() {
        self = KeyEventAnalyzer(maxLearningGap: maxLearningGap)
    }

    public func summary(top limit: Int = 8) -> KeyTimingSummary {
        let eventsPerSecond = activeDuration > 0 ? Double(totalEvents) / activeDuration : 0
        let topKeys = keyStats
            .map { keyName, accumulator in accumulator.stats(keyName: keyName) }
            .sorted {
                if $0.count == $1.count {
                    return $0.keyName < $1.keyName
                }

                return $0.count > $1.count
            }
            .prefix(max(0, limit))

        return KeyTimingSummary(
            totalEvents: totalEvents,
            observedDuration: activeDuration,
            segmentCount: segmentCount,
            ignoredGapCount: ignoredGapCount,
            maxLearningGap: maxLearningGap,
            eventsPerSecond: eventsPerSecond,
            averageGlobalInterval: globalIntervalCount > 0 ? globalIntervalSum / Double(globalIntervalCount) : nil,
            topKeys: Array(topKeys)
        )
    }
}
