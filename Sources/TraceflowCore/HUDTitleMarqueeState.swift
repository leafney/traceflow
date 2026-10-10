import Foundation

/// Only visible time advances a session. Sampling never mutates its clock.
public struct HUDTitleMarqueeState {
    public static let speed = 20.0
    public static let gap = 24.0
    public static let viewport = Double(HUDMetrics.mediumTextLength)

    public struct Record: Equatable {
        public var title: String
        public var phase: Double = 0
        public var textLength: Double
        public var startedAt: Double?
        public var cycleLength: Double { textLength + HUDTitleMarqueeState.gap }
        public var overflows: Bool { textLength.isFinite && textLength > HUDTitleMarqueeState.viewport }
    }

    public struct Sample: Equatable {
        public let phase: Double
        public let offset: Double
    }

    public private(set) var records: [String: Record] = [:]
    public private(set) var activeSessionID: String?
    public init() {}

    public func sample(_ id: String, now: Double) -> Sample {
        guard let record = records[id] else { return Sample(phase: 0, offset: 0) }
        var phase = record.phase
        if let start = record.startedAt, now.isFinite, start.isFinite, record.overflows {
            let progress = phase + max(0, now - start) * Self.speed / record.cycleLength
            if progress.isFinite { phase = progress.truncatingRemainder(dividingBy: 1) }
        }
        return Sample(phase: phase, offset: record.overflows ? -phase * record.cycleLength : 0)
    }

    public mutating func pauseActive(now: Double) {
        guard let id = activeSessionID else { return }
        let phase = sample(id, now: now).phase
        records[id]?.phase = phase
        records[id]?.startedAt = nil
        activeSessionID = nil
    }

    public mutating func configure(_ id: String, title: String, textLength: Double, now: Double) {
        let length = textLength.isFinite && textLength >= 0 ? textLength : 0
        if let old = records[id], old.title == title, old.textLength == length { return }
        if activeSessionID == id { pauseActive(now: now) }
        let phase = records[id]?.title == title ? records[id]!.phase : 0
        records[id] = Record(title: title, phase: phase, textLength: length)
    }

    public mutating func activate(_ id: String, now: Double) {
        guard now.isFinite else { pauseActive(now: now); return }
        if activeSessionID == id { return }
        pauseActive(now: now)
        guard records[id]?.overflows == true else { return }
        records[id]?.startedAt = now
        activeSessionID = id
    }

    public mutating func synchronizeTitles(_ titles: [String: String], now: Double) {
        for id in Array(records.keys) {
            guard let title = titles[id] else {
                if activeSessionID == id { pauseActive(now: now) }
                records.removeValue(forKey: id)
                continue
            }
            if records[id]?.title != title {
                if activeSessionID == id { pauseActive(now: now) }
                records[id]?.title = title
                records[id]?.phase = 0
            }
        }
    }
}
