import XCTest
@testable import TraceflowCore

final class SessionMarkerColorTests: XCTestCase {
    func testNormalizationAndBoundedFallback() throws {
        XCTAssertEqual(SessionMarkerColor.normalized(" #aB12ef\n"), "#AB12EF")
        for invalid in ["red", "#fff", "#12345678", "#GG0000"] { XCTAssertNil(SessionMarkerColor.normalized(invalid)) }
        XCTAssertEqual(try SessionMarkerColor.allocate(occupied: []), "#477EE8")
        let occupied = Set(SessionMarkerColor.candidates)
        XCTAssertEqual(try SessionMarkerColor.allocate(occupied: occupied), "#000000")
        XCTAssertEqual(try SessionMarkerColor.firstUnused(occupied: ["#000000"], upperBound: 1), "#000001")
        XCTAssertThrowsError(try SessionMarkerColor.firstUnused(occupied: ["#000000", "#000001"], upperBound: 1))
    }

    func testBatchRetainsDuplicateManualColorsAndAssignsStableUniqueColors() throws {
        let date = Date(timeIntervalSince1970: 100)
        let records = (0..<12).map { index in
            PersistedSession(sessionID: "s\(index)", markerColorHex: index < 2 ? "#123456" : nil,
                             discoveredAt: date, lastUpdatedAt: date, rotationIndex: index)
        }
        let assigned = try SessionMarkerColor.fillingMissing(in: records.reversed())
        XCTAssertEqual(assigned.filter { $0.markerColorHex == "#123456" }.count, 2)
        XCTAssertEqual(Set(assigned.compactMap(\.markerColorHex)).count, 11)
        XCTAssertFalse(assigned.contains { $0.markerColorHex == SessionMarkerColor.placeholder })
        XCTAssertEqual(try SessionMarkerColor.fillingMissing(in: assigned), assigned)
        let normalOrder = try SessionMarkerColor.fillingMissing(in: records)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: assigned.map { ($0.id, $0.markerColorHex) }),
                       Dictionary(uniqueKeysWithValues: normalOrder.map { ($0.id, $0.markerColorHex) }))
        for record in assigned { XCTAssertEqual(record.lastUpdatedAt, date) }
    }

    func testIncrementalBatchExactlyMatchesOriginalScoringAndTieOrder() throws {
        // Independent old rule, retaining its full recomputation per choice.
        let candidateRGB = SessionMarkerColor.candidates.map { SessionMarkerColor.rgb($0)! }
        func reference(_ occupied: Set<String>) throws -> String {
            if occupied.isEmpty { return "#477EE8" }
            let channels = occupied.compactMap(SessionMarkerColor.rgb)
            var best: String?, bestScore = -Double.infinity
            for (index, candidate) in SessionMarkerColor.candidates.enumerated()
                where candidate != SessionMarkerColor.placeholder && !occupied.contains(candidate) {
                let c = candidateRGB[index]
                let score = channels.map { other in
                    0.30 * pow(Double(c.red - other.red), 2)
                        + 0.59 * pow(Double(c.green - other.green), 2)
                        + 0.11 * pow(Double(c.blue - other.blue), 2)
                }.min() ?? 0
                if score > bestScore { best = candidate; bestScore = score }
            }
            return try best ?? SessionMarkerColor.firstUnused(occupied: occupied)
        }
        let date = Date(timeIntervalSince1970: 100)
        let initialSets: [[String]] = [[], ["#477EE8"], ["#123456", "#123456", "#aabbcc", "#808080"],
                                     SessionMarkerColor.candidates]
        for initial in initialSets {
            var records = initial.enumerated().map { index, color in
                PersistedSession(sessionID: "manual-\(index)", markerColorHex: color,
                                 discoveredAt: date, lastUpdatedAt: date, rotationIndex: index)
            }
            // Tied rotation indices exercise the ID tie breaker, not array order.
            records += (0..<25).map { index in
                PersistedSession(sessionID: "missing-\(index)", discoveredAt: date,
                                 lastUpdatedAt: date, rotationIndex: initial.count + index / 2)
            }
            records.reverse()
            var expected = records
            var occupied = Set(initial.compactMap(SessionMarkerColor.normalized))
            for index in expected.indices.sorted(by: {
                expected[$0].rotationIndex == expected[$1].rotationIndex
                    ? expected[$0].id < expected[$1].id : expected[$0].rotationIndex < expected[$1].rotationIndex
            }) {
                if let color = SessionMarkerColor.normalized(expected[index].markerColorHex) {
                    expected[index].markerColorHex = color
                } else {
                    let color = try reference(occupied)
                    expected[index].markerColorHex = color
                    occupied.insert(color)
                }
            }
            XCTAssertEqual(try SessionMarkerColor.fillingMissing(in: records), expected)
        }
    }

    func testLegacyAndInvalidColorFieldsDecodeWithoutMaskingOtherCorruption() throws {
        let date = Date(timeIntervalSince1970: 100)
        let record = PersistedSession(sessionID: "old", customTitle: "保留标题", discoveredAt: date, lastUpdatedAt: date, rotationIndex: 2)
        let data = try JSONEncoder().encode(record)
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for invalid: Any in [NSNull(), 123, true, "bad"] {
            var object = base
            object["markerColorHex"] = invalid
            let decoded = try JSONDecoder().decode(PersistedSession.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded, record)
        }
        XCTAssertEqual(try JSONDecoder().decode(PersistedSession.self, from: data), record)
        var corrupted = base
        corrupted["rotationIndex"] = "bad"
        XCTAssertThrowsError(try JSONDecoder().decode(PersistedSession.self, from: JSONSerialization.data(withJSONObject: corrupted)))
    }
}
