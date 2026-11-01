import Foundation
import IOKit
import LazyClickCore

/// The ONLY file that touches Apple's private MultitouchSupport.framework.
///
/// * Loaded at runtime with dlopen/dlsym; if the framework or any symbol is missing the adapter reports
///   `.unavailable` and the app keeps working as a (disabled) menu bar item.
/// * Signatures used (C):
///     CFArrayRef MTDeviceCreateList(void);
///     void  MTRegisterContactFrameCallback(MTDeviceRef, int (*)(MTDeviceRef, void *touches, int n, double ts, int frame));
///     void  MTUnregisterContactFrameCallback(MTDeviceRef, same);
///     int   MTDeviceStart(MTDeviceRef, int);   int MTDeviceStop(MTDeviceRef);
///     bool  MTDeviceIsBuiltIn(MTDeviceRef);
///     int   MTDeviceGetFamilyID(MTDeviceRef, int *);
///     int   MTDeviceGetSensorSurfaceDimensions(MTDeviceRef, int *w, int *h);   // 1/100 mm
/// * Touch records are decoded by `RawFrameParser` (fixed 96-byte layout, validated per frame).
/// * Only Magic Mouse devices are started; built-in trackpads and Magic Trackpads are never touched.
final class MultitouchAdapter {
    enum Availability: Equatable { case ready, unavailable(String) }

    typealias DeviceRef = UnsafeMutableRawPointer
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (DeviceRef, FrameCallback) -> Void
    private typealias StartFn = @convention(c) (DeviceRef, Int32) -> Int32
    private typealias StopFn = @convention(c) (DeviceRef) -> Int32
    private typealias BoolFn = @convention(c) (DeviceRef) -> Bool
    private typealias FamilyFn = @convention(c) (DeviceRef, UnsafeMutablePointer<Int32>) -> Int32
    private typealias DimsFn = @convention(c) (DeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private(set) var availability: Availability
    private var handle: UnsafeMutableRawPointer?
    private var createList: CreateListFn?
    private var register: RegisterFn?
    private var unregister: RegisterFn?
    private var start: StartFn?
    private var stop: StopFn?
    private var isBuiltIn: BoolFn?
    private var familyID: FamilyFn?
    private var dims: DimsFn?

    private var deviceList: CFArray?
    private var running: [DeviceRef] = []
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var refreshWork: DispatchWorkItem?

    /// Invoked on the main thread whenever the set of running Magic Mice changes.
    var onDeviceCountChanged: ((Int) -> Void)?
    /// Invoked on the main thread right before running devices are torn down and rebuilt, so the
    /// consumer can release any held synthetic button (touch state is lost across the rebuild).
    var onDevicesStopping: (() -> Void)?
    private(set) var wanted = false

    var deviceCount: Int { running.count }

    init() {
        availability = .unavailable("not loaded")
        guard let h = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            availability = .unavailable("MultitouchSupport.framework could not be loaded")
            return
        }
        handle = h
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        createList = sym("MTDeviceCreateList", CreateListFn.self)
        register = sym("MTRegisterContactFrameCallback", RegisterFn.self)
        unregister = sym("MTUnregisterContactFrameCallback", RegisterFn.self)
        start = sym("MTDeviceStart", StartFn.self)
        stop = sym("MTDeviceStop", StopFn.self)
        isBuiltIn = sym("MTDeviceIsBuiltIn", BoolFn.self)
        familyID = sym("MTDeviceGetFamilyID", FamilyFn.self)
        dims = sym("MTDeviceGetSensorSurfaceDimensions", DimsFn.self)

        let missing = [("MTDeviceCreateList", createList != nil), ("MTRegisterContactFrameCallback", register != nil),
                       ("MTUnregisterContactFrameCallback", unregister != nil), ("MTDeviceStart", start != nil),
                       ("MTDeviceStop", stop != nil), ("MTDeviceIsBuiltIn", isBuiltIn != nil)]
            .filter { !$0.1 }.map { $0.0 }
        if missing.isEmpty {
            availability = .ready
        } else {
            availability = .unavailable("Missing private symbols: " + missing.joined(separator: ", "))
        }
    }

    // MARK: - Lifecycle

    /// Start listening. Idempotent. Also arms IOKit notifications so hot-plug is event driven.
    func startMonitoring() {
        let alreadyRunning = wanted && !running.isEmpty
        wanted = true
        guard availability == .ready else { return }
        armHotplugNotifications()
        if !alreadyRunning { refreshDevices() } // never rebuild a live session just because state was re-applied
    }

    /// Stop everything and unregister callbacks.
    func stopMonitoring() {
        wanted = false
        refreshWork?.cancel()
        refreshWork = nil
        stopDevices()
        disarmHotplugNotifications()
        notify()
    }

    /// Stop devices but keep hot-plug notifications (used around sleep).
    func pauseDevices() {
        refreshWork?.cancel()
        stopDevices()
        notify()
    }

    func scheduleRefresh(after delay: TimeInterval = 0.3) {
        guard wanted, availability == .ready else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshDevices() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Device handling

    private func refreshDevices() {
        guard wanted, availability == .ready, let createList, let register, let start else { return }
        let before = running.count
        if before > 0 { onDevicesStopping?() }
        stopDevices()

        guard let list = createList()?.takeRetainedValue() else {
            if before != 0 { notify() }
            return
        }
        deviceList = list
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            guard isMagicMouse(dev) else { continue }
            register(dev, magicMouseFrameCallback)
            _ = start(dev, 0)
            running.append(dev)
        }
        notify()
    }

    private func stopDevices() {
        for dev in running {
            unregister?(dev, magicMouseFrameCallback)
            _ = stop?(dev)
        }
        running.removeAll()
        deviceList = nil // releases the devices
    }

    private func isMagicMouse(_ dev: DeviceRef) -> Bool {
        if let isBuiltIn, isBuiltIn(dev) { return false }
        var family: Int32 = 0
        if let familyID, familyID(dev, &family) == 0, family == 112 || family == 113 { return true }
        // Fallback: Magic Mouse sensor is narrow and tall (~52 x 91 mm); trackpads are far larger.
        if let dims {
            var w: Int32 = 0, h: Int32 = 0
            if dims(dev, &w, &h) == 0, w > 0, h > 0, w < 7000, h < 12000, w < h { return true }
        }
        return false
    }

    private func notify() {
        let n = running.count
        if Thread.isMainThread { onDeviceCountChanged?(n) } else { DispatchQueue.main.async { self.onDeviceCountChanged?(n) } }
    }

    /// Debug aid for `--probe`: describes every device MultitouchSupport reports.
    func describeDevices() -> [String] {
        guard availability == .ready, let createList else { return ["unavailable"] }
        guard let list = createList()?.takeRetainedValue() else { return ["no device list"] }
        var out: [String] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var fam: Int32 = -1, w: Int32 = 0, h: Int32 = 0
            _ = familyID?(dev, &fam)
            _ = dims?(dev, &w, &h)
            out.append("device[\(i)] builtIn=\(isBuiltIn?(dev) ?? false) family=\(fam) surface=\(w)x\(h) magicMouse=\(isMagicMouse(dev))")
        }
        return out
    }

    // MARK: - IOKit hot-plug (event driven; no polling)

    private func armHotplugNotifications() {
        guard notifyPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            // Drain the iterator to re-arm the notification.
            while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }
            guard let refcon else { return }
            Unmanaged<MultitouchAdapter>.fromOpaque(refcon).takeUnretainedValue().scheduleRefresh()
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var it: io_iterator_t = 0
            let kr = IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), cb, ctx, &it)
            if kr == KERN_SUCCESS {
                iterators.append(it)
                while case let obj = IOIteratorNext(it), obj != 0 { IOObjectRelease(obj) } // arm
            }
        }
    }

    private func disarmHotplugNotifications() {
        for it in iterators { IOObjectRelease(it) }
        iterators.removeAll()
        if let port = notifyPort {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
    }

    // MARK: - Frame sink

    /// Set before `startMonitoring()`. Read from the private touch thread.
    nonisolated(unsafe) static var frameHandler: ((UnsafeRawPointer?, Int, Double) -> Void)?
}

/// C callback registered with MultitouchSupport. Must be a plain function; does no allocation.
private func magicMouseFrameCallback(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?,
                                     _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    MultitouchAdapter.frameHandler?(UnsafeRawPointer(touches), Int(count), timestamp)
    return 0
}
