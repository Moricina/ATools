import Foundation
import os

/// 自动退出裁决结果
public enum AutoQuitDecision: String, Sendable {
    case quitScheduled = "已调度退出"
    case quitExecuted = "已执行退出"
    case aborted = "已放弃退出"
    case retrying = "复查防抖中"
    case ignored = "无需处理"
}

/// 单条决策记录（纯值类型，绝不持有 NSRunningApplication / AXUIElement / NSImage，避免内存泄漏）
public struct AutoQuitDecisionRecord: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let pid: pid_t
    public let bundleID: String
    public let appName: String
    public let axWindowCount: Int?
    public let wsWindowCount: Int?
    public let decision: AutoQuitDecision
    public let reasonCode: String
    public let detail: String

    public init(
        pid: pid_t,
        bundleID: String,
        appName: String,
        axWindowCount: Int?,
        wsWindowCount: Int?,
        decision: AutoQuitDecision,
        reasonCode: String,
        detail: String = ""
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.axWindowCount = axWindowCount
        self.wsWindowCount = wsWindowCount
        self.decision = decision
        self.reasonCode = reasonCode
        self.detail = detail
    }
}

/// 决策历史追踪器（内存常驻 50 条环形缓冲区，微秒级写入，零显存占用）
public final class AutoQuitDecisionTrace: @unchecked Sendable {
    public static let shared = AutoQuitDecisionTrace()

    private let maxCapacity = 50
    private var records: [AutoQuitDecisionRecord] = []
    private var lock = os_unfair_lock()

    private init() {}

    /// 压入一条新决策记录
    public func record(
        pid: pid_t,
        bundleID: String,
        appName: String,
        axWindowCount: Int?,
        wsWindowCount: Int?,
        decision: AutoQuitDecision,
        reasonCode: String,
        detail: String = ""
    ) {
        let entry = AutoQuitDecisionRecord(
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            axWindowCount: axWindowCount,
            wsWindowCount: wsWindowCount,
            decision: decision,
            reasonCode: reasonCode,
            detail: detail
        )

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        records.append(entry)
        if records.count > maxCapacity {
            records.removeFirst(records.count - maxCapacity)
        }
    }

    /// 获取最近记录快照（倒序，最新在最前）
    public func recentRecords() -> [AutoQuitDecisionRecord] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return records.reversed()
    }

    /// 清空记录
    public func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        records.removeAll()
    }

    /// 生成一键导出的诊断文本报告
    public func generateDiagnosticReport() -> String {
        let list = recentRecords()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var output = "=== ATools AutoQuit 诊断与决策历史报告 ===\n"
        output += "生成时间: \(formatter.string(from: Date()))\n"
        output += "记录条数: \(list.count)\n\n"

        if list.isEmpty {
            output += "(暂无退出判定记录)\n"
            return output
        }

        for (index, r) in list.enumerated() {
            output += "[\(index + 1)] \(formatter.string(from: r.timestamp)) | \(r.appName) (PID: \(r.pid), BID: \(r.bundleID))\n"
            output += "    - 裁决状态: \(r.decision.rawValue)\n"
            output += "    - 窗口确诊: AX=\(r.axWindowCount.map(String.init) ?? "nil"), WindowServer=\(r.wsWindowCount.map(String.init) ?? "nil")\n"
            output += "    - 裁决原因: \(r.reasonCode)\n"
            if !r.detail.isEmpty {
                output += "    - 附加详情: \(r.detail)\n"
            }
            output += "--------------------------------------------------\n"
        }
        return output
    }
}
