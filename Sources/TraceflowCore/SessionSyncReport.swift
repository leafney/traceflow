import Foundation

public enum SessionSyncReport {
    public static func message(readCount: Int, addedCount: Int, updatedCount: Int, saved: Bool) -> String {
        if saved {
            return "同步完成：新增 \(addedCount) 个，更新 \(updatedCount) 个，共读取 \(readCount) 个会话。新会话默认关闭，请展开项目并选择需要参与 HUD 的会话。"
        }
        return "已读取 \(readCount) 个会话，但保存失败。当前结果仅在本次运行中有效，请修复会话数据后点击“重试保存”。"
    }
}
