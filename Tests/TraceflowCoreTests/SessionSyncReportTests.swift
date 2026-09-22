import XCTest
@testable import TraceflowCore

final class SessionSyncReportTests: XCTestCase {
    func testSavedSyncReportsCompletion() {
        let message = SessionSyncReport.message(readCount: 5, addedCount: 2, updatedCount: 3, saved: true)
        XCTAssertTrue(message.hasPrefix("同步完成"))
        XCTAssertTrue(message.contains("新增 2 个"))
    }

    func testUnsavedSyncNeverReportsCompletion() {
        let message = SessionSyncReport.message(readCount: 5, addedCount: 2, updatedCount: 3, saved: false)
        XCTAssertFalse(message.contains("同步完成"))
        XCTAssertTrue(message.contains("保存失败"))
        XCTAssertTrue(message.contains("重试保存"))
    }
}
