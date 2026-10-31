import Foundation
import AppKit
import os

public struct MTPoint: Sendable {
    public var x: Float
    public var y: Float
    public init(x: Float = 0, y: Float = 0) {
        self.x = x
        self.y = y
    }
}

public struct MTVector: Sendable {
    public var position: MTPoint
    public var velocity: MTPoint
    public init(position: MTPoint = MTPoint(), velocity: MTPoint = MTPoint()) {
        self.position = position
        self.velocity = velocity
    }
}

/// MultitouchSupport 触控板单指精确二进制布局（每指严格 96 字节）
public struct MTContact: Sendable {
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
private typealias MTDeviceIsRunningFunc = @convention(c) (UnsafeMutableRawPointer) -> Bool
private typealias MTDeviceStartFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
private typealias MTDeviceStopFunc = @convention(c) (UnsafeMutableRawPointer) -> Int32

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
    private var mtDeviceIsRunning: MTDeviceIsRunningFunc?
    private var mtDeviceStart: MTDeviceStartFunc?
    private var mtDeviceStop: MTDeviceStopFunc?

    /// 持有底层 CFArray 引用，防止 MTDeviceRef 在局部变量作用域结束时被提前过早释放
    private var activeDeviceList: CFArray?
    private var activeDevices: [UnsafeMutableRawPointer] = []
    private var isListening: Bool = false
    private var isStopping: Bool = false
    private var activeCallbackCount: Int = 0
    private var lock = os_unfair_lock()

    private var sleepWakeObservers: [NSObjectProtocol] = []
    private var wakeReinitWorkItem: DispatchWorkItem?

    // 手势识别周期状态
    private struct TouchCycleState {
        var initialTimestamp: Double = 0
        var lastFrameTimestamp: Double = 0
        var initialPositions: [Int32: (x: Float, y: Float)] = [:]
        var maxDisplacement: Float = 0
        var maxFingerCount: Int = 0
        var avgDeltaY: Float = 0
        var avgDeltaX: Float = 0
        var isTracking: Bool = false
        var triggeredThisCycle: Bool = false
    }

    private var cycleState = TouchCycleState()
    /// Y-08: 触控周期代次计数器，防止上一周期延迟排队的 DispatchWorkItem 误终结已开始的新手势周期
    private var touchCycleGeneration: UInt64 = 0
    private var activeGesture: ShelfTrackpadGesture = .none
    private var lastTriggerTimestamp: Double = 0
    private var pendingEndWorkItem: DispatchWorkItem?

    private init() {
        setupSleepWakeObservers()
    }

    deinit {
        wakeReinitWorkItem?.cancel()
        for token in sleepWakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        sleepWakeObservers.removeAll()
        stopListening()
        // Y-09: 单例驻留生命周期内不直接 dlclose 仍在排空的动态库，若真销毁仅在无活跃回调时关闭
        os_unfair_lock_lock(&lock)
        let inFlight = activeCallbackCount
        let handle = dylibHandle
        dylibHandle = nil
        os_unfair_lock_unlock(&lock)
        if inFlight == 0, let handle = handle {
            dlclose(handle)
        }
    }

    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepWakeObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            runtimeLog("[TrackpadGesture] System will sleep, safely pausing touch devices...")
            self?.wakeReinitWorkItem?.cancel()
            self?.wakeReinitWorkItem = nil
            self?.stopListening()
        })

        sleepWakeObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let config = ConfigManager.shared.config
            guard config.enableShelfPanel && config.shelfTrackpadGesture != .none else { return }
            runtimeLog("[TrackpadGesture] System woke from sleep, scheduling stabilized touch reinitialization...")
            self.wakeReinitWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                runtimeLog("[TrackpadGesture] Hardware bus stabilized, re-listening devices...")
                self.startListeningIfEnabled()
            }
            self.wakeReinitWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        })
    }

    private func loadMultitouchFrameworkLocked() -> Bool {
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
        if let symRunning = dlsym(handle, "MTDeviceIsRunning") {
            self.mtDeviceIsRunning = unsafeBitCast(symRunning, to: MTDeviceIsRunningFunc.self)
        }
        return true
    }

    public func startListeningIfEnabled() {
        let config = ConfigManager.shared.config
        guard config.enableShelfPanel && config.shelfTrackpadGesture != .none else {
            os_unfair_lock_lock(&lock)
            activeGesture = .none
            os_unfair_lock_unlock(&lock)
            stopListening()
            return
        }
        os_unfair_lock_lock(&lock)
        activeGesture = config.shelfTrackpadGesture
        os_unfair_lock_unlock(&lock)
        startListening()
    }

    public func updateConfiguration(_ gesture: ShelfTrackpadGesture) {
        let enabled = ConfigManager.shared.config.enableShelfPanel
        os_unfair_lock_lock(&lock)
        activeGesture = enabled ? gesture : .none
        os_unfair_lock_unlock(&lock)
        if gesture == .none || !enabled {
            stopListening()
        } else {
            startListening()
        }
    }

    /// Y-09: 将私有框架 C API (MTDeviceCreateList / MTDeviceStart) 移出 lock 临界区，杜绝与底层回调线程发生互锁死锁
    public func startListening() {
        os_unfair_lock_lock(&lock)
        if isListening {
            os_unfair_lock_unlock(&lock)
            return
        }
        guard loadMultitouchFrameworkLocked(),
              let createList = mtDeviceCreateList,
              let registerCb = mtRegisterCallback,
              let startDev = mtDeviceStart else {
            os_unfair_lock_unlock(&lock)
            return
        }
        isStopping = false
        os_unfair_lock_unlock(&lock)

        guard let list = createList()?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(list)
        var startedDevices: [UnsafeMutableRawPointer] = []

        for i in 0..<count {
            if let rawDev = CFArrayGetValueAtIndex(list, i) {
                let dev = UnsafeMutableRawPointer(mutating: rawDev)
                registerCb(dev, multitouchCallbackTrampoline)
                _ = startDev(dev, 0)
                startedDevices.append(dev)
            }
        }

        os_unfair_lock_lock(&lock)
        self.activeDeviceList = list
        self.activeDevices = startedDevices
        self.isListening = !startedDevices.isEmpty
        os_unfair_lock_unlock(&lock)

        runtimeLog("[TrackpadGesture] Started listening on \(startedDevices.count) touch device(s)")
    }

    /// Y-09: 先在锁内标记 isStopping 并取出设备快照，随后在锁外执行 MTUnregisterContactFrameCallback 与 MTDeviceStop
    public func stopListening() {
        os_unfair_lock_lock(&lock)
        isStopping = true
        touchCycleGeneration &+= 1
        pendingEndWorkItem?.cancel()
        pendingEndWorkItem = nil

        guard isListening || !activeDevices.isEmpty else {
            activeDeviceList = nil
            os_unfair_lock_unlock(&lock)
            return
        }

        let devicesToStop = activeDevices
        let staleList = activeDeviceList
        let unregisterCb = mtUnregisterCallback
        let stopDev = mtDeviceStop
        let isRunningFn = mtDeviceIsRunning

        activeDevices.removeAll()
        activeDeviceList = nil
        isListening = false
        cycleState = TouchCycleState()
        os_unfair_lock_unlock(&lock)

        if let unregisterCb = unregisterCb, let stopDev = stopDev {
            for dev in devicesToStop {
                unregisterCb(dev, multitouchCallbackTrampoline)
                if let isRunning = isRunningFn {
                    if isRunning(dev) {
                        _ = stopDev(dev)
                    }
                } else {
                    _ = stopDev(dev)
                }
            }
        }

        if let staleList = staleList {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0) {
                _ = staleList
            }
        }
        runtimeLog("[TrackpadGesture] Stopped listening and released all touch devices")
    }

    public func reinitializeDevices() {
        stopListening()
        startListeningIfEnabled()
    }

    @inline(__always)
    private func isFingerTouching(_ state: Int32) -> Bool {
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
        if isStopping {
            os_unfair_lock_unlock(&lock)
            return
        }
        activeCallbackCount += 1
        defer {
            activeCallbackCount -= 1
            os_unfair_lock_unlock(&lock)
        }

        let configuredGesture = activeGesture
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
            touchCycleGeneration &+= 1
            cycleState = TouchCycleState(
                initialTimestamp: timestamp,
                lastFrameTimestamp: timestamp,
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
            cycleState.lastFrameTimestamp = timestamp
            cycleState.maxFingerCount = max(cycleState.maxFingerCount, touchingCount)

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

        // Y-08: 捕获当前触控代次 capturedGeneration 并检查 workItem.isCancelled，杜绝旧定时器误杀新手势周期
        let capturedGeneration = touchCycleGeneration
        var workItemRef: DispatchWorkItem?
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let item = workItemRef, item.isCancelled { return }
            os_unfair_lock_lock(&self.lock)
            defer { os_unfair_lock_unlock(&self.lock) }
            guard !self.isStopping, self.touchCycleGeneration == capturedGeneration else { return }
            let endTs = max(self.cycleState.lastFrameTimestamp, self.cycleState.initialTimestamp + 0.05)
            self.evaluateTouchCycleEnd(timestamp: endTs, gesture: configuredGesture)
        }
        workItemRef = work
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
        guard timestamp - lastTriggerTimestamp > 0.45 else { return }
        lastTriggerTimestamp = timestamp
        cycleState.triggeredThisCycle = true

        DispatchQueue.main.async {
            runtimeLog("[TrackpadGesture] Gesture triggered: \(ConfigManager.shared.config.shelfTrackpadGesture.rawValue)")
            HotkeyManager.shared.resetCandidateState()
            PanelCoordinator.shared.togglePanel(.shelf)
        }
    }
}
