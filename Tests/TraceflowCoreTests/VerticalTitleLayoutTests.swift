import XCTest
@testable import TraceflowCore

final class VerticalTitleLayoutTests: XCTestCase {
    func testParsesChineseAndLatinMixedTitle() {
        XCTAssertEqual(
            VerticalTitleParser.segments(for: "hello world 小米"),
            [.latin("hello world"), .gap, .han("小"), .han("米")]
        )
    }

    func testPreservesLatinConnectorsAndInternalDot() {
        XCTAssertEqual(VerticalTitleParser.segments(for: "usb-hub_Codex-5.3"), [.latin("usb-hub_Codex-5.3")])
        XCTAssertEqual(VerticalTitleParser.segments(for: "example.com"), [.latin("example.com")])
        XCTAssertEqual(VerticalTitleParser.segments(for: "cafe\u{301}"), [.latin("cafe\u{301}")])
    }

    func testPreservesProjectAndSummaryMiddleDotAsVisibleVerticalSeparator() {
        XCTAssertEqual(
            VerticalTitleParser.segments(for: "traceflow · 测试一下选择"),
            [.latin("traceflow"), .gap, .han("·"), .han("测"), .han("试"), .han("一"), .han("下"), .han("选"), .han("择")]
        )
    }

    func testDropsChinesePunctuationWithoutGap() {
        XCTAssertEqual(
            VerticalTitleParser.segments(for: "小米，遥控器。设置"),
            [.han("小"), .han("米"), .han("遥"), .han("控"), .han("器"), .han("设"), .han("置")]
        )
        XCTAssertEqual(
            VerticalTitleParser.segments(for: "项目-设置"),
            [.han("项"), .han("目"), .han("设"), .han("置")]
        )
    }

    func testSeparatorsAndEmojiCreateOnlyRequiredGaps() {
        XCTAssertEqual(
            VerticalTitleParser.segments(for: "foo/bar:baz"),
            [.latin("foo"), .gap, .latin("bar"), .gap, .latin("baz")]
        )
        XCTAssertEqual(
            VerticalTitleParser.segments(for: "中文🙂标题"),
            [.han("中"), .han("文"), .han("标"), .han("题")]
        )
        XCTAssertEqual(
            VerticalTitleParser.segments(for: "foo🙂bar"),
            [.latin("foo"), .gap, .latin("bar")]
        )
    }

    func testTruncationUsesInjectedAdvancesAndKeepsEllipsisSeparate() {
        let advance: (VerticalTitleSegment) -> Double = { segment in
            switch segment {
            case .han: 10
            case .gap: 4
            case let .latin(text): Double(text.count * 5)
            }
        }
        XCTAssertEqual(
            VerticalTitleMeasurer.layout(segments: [.han("中"), .han("文")], maximumLength: 30, ellipsisAdvance: 10, advance: advance),
            VerticalTitleLayout(visibleSegments: [.han("中"), .han("文")], showsEllipsis: false)
        )
        XCTAssertEqual(
            VerticalTitleMeasurer.layout(segments: [.han("中"), .han("文"), .han("标"), .han("题")], maximumLength: 30, ellipsisAdvance: 10, advance: advance),
            VerticalTitleLayout(visibleSegments: [.han("中"), .han("文")], showsEllipsis: true)
        )
        XCTAssertEqual(
            VerticalTitleMeasurer.layout(segments: [.latin("abcdefg")], maximumLength: 30, ellipsisAdvance: 10, advance: advance),
            VerticalTitleLayout(visibleSegments: [.latin("abcd")], showsEllipsis: true)
        )
    }
}
