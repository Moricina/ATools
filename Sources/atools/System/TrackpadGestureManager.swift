import Foundation
import AppKit
import os

public struct MTPoint {
    public var x: Float
    public var y: Float
    public init(x: Float = 0, y: Float = 0) {
        self.x = x
        self.y = y
    }
}

public struct MTVector {
    public var position: MTPoint
    public var velocity: MTPoint
    public init(position: MTPoint = MTPoint(), velocity: MTPoint = MTPoint()) {
        self.position = position
        self.velocity = velocity
    }
}

/// MultitouchSupport 触控板单指精确二进制布局（每指严格 96 字节）
public struct MTContact {
    public var frame: Int32        // +0
    public var pad: Int32          // +4
    public var timestamp: Double   // +8
    public var pathIndex: Int32    // +16
    public var state: Int32        // +20 (0=none, 1=start, 2=hover, 3=make, 4=touch, 5=press, 6=tap, 7=lift)
    public var fingerID: Int32     // +24
    public var handID: Int32       // +28
    public var x: Float            // +32 (归一化 X: 0.0~1.0)
    public var y: Float            // +36 (归一化 Y: 0.0~1.0)
    public var vx: Float           // +40
    public var vy: Float           // +44
    public var size: Float         // +48
    public var pressure: Float     // +52
    public var angle: Float        // +56
    public var majorAxis: Float    // +60
    public var minorAxis: Float    // +64
    public var density: Float      // +68
    public var abs_x: Float        // +72
    public var abs_vx: Float       // +76
    public var abs_vy: Float       // +80
    public var reserved0: Int32    // +84
    public var reserved1: Int32    // +88
    public var zPressure: Float    // +92
}

private typealias MTContactCallbackFunction = @convention(c) (
    UnsafeMutableRawPointer?, // device
    UnsafeMutableRawPointer?, // contactList
    Int32,                    // numContacts
    Double,                   // timestamp
    Int32                     // frame
) -> Int32

private typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterContactFrameCallbackFunc = @convention(c) (UnsafeMutableRawPointer, MTContactCallbackFunction) -> Void
private typealias MTUnregisterContactFrameCallbackFunc = @convention(c) (UnsafeMutableRawPointer, MTContactCallbackFunction) -> Void
private typealias MTDeviceStartFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias MTDeviceStopFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

/// 静态 C 回调跳板（Trampoline），将 MultitouchSupport 内核分发线程数据派发至单例处理
private func multitouchCallbackTrampoline(
    device: UnsafeMutableRawPointer?,
    contactList: UnsafeMutableRawPointer?,
    numContacts: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    TrackpadGestureManager.shared.handleContactFrame(
        contactList: contactList,
        numContacts: Int(numContacts),
        timestamp: timestamp,
        frame: frame
    )
    return 0
}

public final class TrackpadGestureManager {
    public static let shared = TrackpadGestureManager()

    private var dylibHandle: UnsafeMutableRawPointer?
    private var mtDeviceCreateList: MTDeviceCreateListFunc?
    private var mtRegisterCallback: MTRegisterContactFrameCallbackFunc?
    private var mtUnregisterCallback: MTUnregisterContactFrameCallbackFunc?
    private var mtDeviceStart: MTDeviceStartFunc?
    private var mtDeviceStop: MTDeviceStopFunc?

    private var activeDevices: [UnsafeMutableRawPointer] = []
    private var isListening: Bool = false
    private var lock = os_unfair_lock()

    // 手势识别周期状态
    private struct TouchCycleState {
        var initialTimestamp: Double = 0
        var initialPositions: [Int32: (x: Float, y: Float)] = [:]
        var maxDisplacement: Float = 0
        var maxFingerCount: Int = 0
        var avgDeltaY: Float = 0
        var avgDeltaX: Float = 0
        var isTracking: Bool = false
        var triggeredThisCycle: Bool = false
    }

    private var cycleState = TouchCycleState()
    private var lastTriggerTimestamp: Double = 0
    private var pendingEndWorkItem: DispatchWorkItem?

    private init() {
        setupSleepWakeObservers()
    }

    deinit {
        stopListening()
        if let handle = dylibHandle {
            dlclose(handle)
        }
    }

    private func setupSleepWakeObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            runtimeLog("[TrackpadGesture] System woke from sleep, reinitializing devices...")
            self?.reinitializeDevices()
        }
    }

    private func loadMultitouchFramework() -> Bool {
        if dylibHandle != nil { return true }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else {
            runtimeLog("[TrackpadGesture] Failed to dlopen MultitouchSupport: \(String(cString: dlerror()))")
            return false
        }
        self.dylibHandle = handle

        guard let symCreate = dlsym(handle, "MTDeviceCreateList"),
              let symRegister = dlsym(handle, "MTRegisterContactFrameCallback"),
              let symUnregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let symStart = dlsym(handle, "MTDeviceStart"),
              let symStop = dlsym(handle, "MTDeviceStop") else {
            runtimeLog("[TrackpadGesture] Failed to locate MultitouchSupport symbols")
            return false
        }

        self.mtDeviceCreateList = unsafeBitCast(symCreate, to: MTDeviceCreateListFunc.self)
        self.mtRegisterCallback = unsafeBitCast(symRegister, to: MTRegisterContactFrameCallbackFunc.self)
        self.mtUnregisterCallback = unsafeBitCast(symUnregister, to: MTUnregisterContactFrameCallbackFunc.self)
        self.mtDeviceStart = unsafeBitCast(symStart, to: MTDeviceStartFunc.self)
        self.mtDeviceStop = unsafeBitCast(symStop, to: MTDeviceStopFunc.self)
        return true
    }

    public func startListeningIfEnabled() {
        let config = ConfigManager.shared.config
        guard config.enableShelfPanel && config.shelfTrackpadGesture != .none else {
            stopListening()
            return
        }
        startListening()
    }

    public func updateConfiguration(_ gesture: ShelfTrackpadGesture) {
        if gesture == .none || !ConfigManager.shared.config.enableShelfPanel {
            stopListening()
        } else {
            startListening()
        }
    }

    public func startListening() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard !isListening else { return }
        guard loadMultitouchFramework(),
              let createList = mtDeviceCreateList,
              let registerCb = mtRegisterCallback,
              let startDev = mtDeviceStart else { return }

        guard let list = createList()?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(list)
        activeDevices.removeAll()

        for i in 0..<count {
            if let rawDev = CFArrayGetValueAtIndex(list, i) {
                let dev = UnsafeMutableRawPointer(mutating: rawDev)
                registerCb(dev, multitouchCallbackTrampoline)
                startDev(dev, 0)
                activeDevices.append(dev)
            }
        }

        isListening = !activeDevices.isEmpty
        runtimeLog("[TrackpadGesture] Started listening on \(activeDevices.count) touch device(s)")
    }

    public func stopListening() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        pendingEndWorkItem?.cancel()
        pendingEndWorkItem = nil

        guard isListening || !activeDevices.isEmpty else { return }
        guard let unregisterCb = mtUnregisterCallback,
              let stopDev = mtDeviceStop else {
            activeDevices.removeAll()
            isListening = false
            return
        }

        for dev in activeDevices {
            stopDev(dev, 0)
            unregisterCb(dev, multitouchCallbackTrampoline)
        }
        activeDevices.removeAll()
        isListening = false
        cycleState = TouchCycleState()
        runtimeLog("[TrackpadGesture] Stopped listening and released all touch devices")
    }

    public func reinitializeDevices() {
        stopListening()
        startListeningIfEnabled()
    }

    @inline(__always)
    private func isFingerTouching(_ state: Int32) -> Bool {
        // 3=make, 4=touch, 5=press, 6=tap
        return state >= 3 && state <= 6
    }

    // MARK: - 高频接触帧处理与微型状态机
    func handleContactFrame(
        contactList: UnsafeMutableRawPointer?,
        numContacts: Int,
        timestamp: Double,
        frame: Int32
    ) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let configuredGesture = ConfigManager.shared.config.shelfTrackpadGesture
        guard configuredGesture != .none else { return }

        pendingEndWorkItem?.cancel()
        pendingEndWorkItem = nil

        guard let contactList = contactList, numContacts > 0 else {
            evaluateTouchCycleEnd(timestamp: timestamp, gesture: configuredGesture)
            return
        }

        let contacts = contactList.assumingMemoryBound(to: MTContact.self)
        var touchingCount = 0
        var hasLiftState = false

        for i in 0..<numContacts {
            let st = contacts[i].state
            if isFingerTouching(st) {
                touchingCount += 1
            } else if st == 7 {
                hasLiftState = true
            }
        }

        if touchingCount == 0 {
            evaluateTouchCycleEnd(timestamp: timestamp, gesture: configuredGesture)
            return
        }

        if !cycleState.isTracking {
            // 开始新的触控追踪周期
            cycleState = TouchCycleState(
                initialTimestamp: timestamp,
                initialPositions: [:],
                maxDisplacement: 0,
                maxFingerCount: touchingCount,
                avgDeltaY: 0,
                avgDeltaX: 0,
                isTracking: true,
                triggeredThisCycle: false
            )
            for i in 0..<numContacts {
                let c = contacts[i]
                if isFingerTouching(c.state) {
                    cycleState.initialPositions[c.pathIndex] = (c.x, c.y)
                }
            }
        } else {
            cycleState.maxFingerCount = max(cycleState.maxFingerCount, touchingCount)

            // 计算位移与方向
            var totalDeltaX: Float = 0
            var totalDeltaY: Float = 0
            var matchedFingers = 0

            for i in 0..<numContacts {
                let c = contacts[i]
                if let initPos = cycleState.initialPositions[c.pathIndex] {
                    let dx = c.x - initPos.x
                    let dy = c.y - initPos.y
                    let dist = sqrt(dx * dx + dy * dy)
                    cycleState.maxDisplacement = max(cycleState.maxDisplacement, dist)
                    totalDeltaX += dx
                    totalDeltaY += dy
                    matchedFingers += 1
                } else if isFingerTouching(c.state) {
                    cycleState.initialPositions[c.pathIndex] = (c.x, c.y)
                }
            }

            if matchedFingers > 0 {
                cycleState.avgDeltaX = totalDeltaX / Float(matchedFingers)
                cycleState.avgDeltaY = totalDeltaY / Float(matchedFingers)
            }

            // 针对三指下滑：在滑移过程中一旦满足位移阈值即触发，获得丝滑响应
            if configuredGesture == .threeFingerSwipeDown && !cycleState.triggeredThisCycle {
                let elapsed = timestamp - cycleState.initialTimestamp
                if cycleState.maxFingerCount == 3 && elapsed <= 0.45 {
                    if cycleState.avgDeltaY <= -0.10 && abs(cycleState.avgDeltaX) <= 0.15 {
                        triggerGestureAction(timestamp: timestamp)
                    }
                }
            }

            if hasLiftState {
                evaluateTouchCycleEnd(timestamp: timestamp, gesture: configuredGesture)
                return
            }
        }

        // 定时兜底：若手指离开后硬件不再下发新帧，通过 70ms 延迟安全完成轻点判定
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.lock)
            defer { os_unfair_lock_unlock(&self.lock) }
            self.evaluateTouchCycleEnd(timestamp: self.cycleState.initialTimestamp + 0.10, gesture: configuredGesture)
        }
        pendingEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: work)
    }

    private func evaluateTouchCycleEnd(timestamp: Double, gesture: ShelfTrackpadGesture) {
        guard cycleState.isTracking else { return }
        defer {
            cycleState.isTracking = false
        }

        if cycleState.triggeredThisCycle {
            return
        }

        let elapsed = timestamp - cycleState.initialTimestamp
        guard elapsed >= 0.02 && elapsed <= 0.38 else { return }

        switch gesture {
        case .fourFingerTap:
            if cycleState.maxFingerCount == 4 && cycleState.maxDisplacement <= 0.08 {
                triggerGestureAction(timestamp: timestamp)
            }
        case .threeFingerTap:
            if cycleState.maxFingerCount == 3 && cycleState.maxDisplacement <= 0.07 {
                triggerGestureAction(timestamp: timestamp)
            }
        case .threeFingerSwipeDown:
            if cycleState.maxFingerCount == 3 && cycleState.avgDeltaY <= -0.10 && abs(cycleState.avgDeltaX) <= 0.15 {
                triggerGestureAction(timestamp: timestamp)
            }
        case .none:
            break
        }
    }

    private func triggerGestureAction(timestamp: Double) {
        // 0.45s 防抖与冷却时间
        guard timestamp - lastTriggerTimestamp > 0.45 else { return }
        lastTriggerTimestamp = timestamp
        cycleState.triggeredThisCycle = true

        DispatchQueue.main.async {
            runtimeLog("[TrackpadGesture] Gesture triggered: \(ConfigManager.shared.config.shelfTrackpadGesture.rawValue)")
            // 重置快捷键候选态，避免用户手势时无意碰到修饰键导致候选挂起
            HotkeyManager.shared.resetCandidateState()
            // 切换应用抽屉
            PanelCoordinator.shared.togglePanel(.shelf)
        }
    }
}
