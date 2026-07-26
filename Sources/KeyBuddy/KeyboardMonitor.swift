import AppKit
import CoreGraphics

/// 全局键盘监听：检测独立按松 Shift 键触发切换
final class KeyboardMonitor {

    private var shiftDown = false
    private var otherKeyPressed = false
    private var stateLock = os_unfair_lock()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var owningRunLoop: CFRunLoop?

    private let onShiftTrigger: () -> Void

    init(onShiftTrigger: @escaping () -> Void) {
        self.onShiftTrigger = onShiftTrigger
    }

    deinit { stop() }

    // MARK: - Start / Stop

    func start() -> Bool {
        var mask: UInt64 = 0
        mask |= 1 << CGEventType.keyDown.rawValue
        mask |= 1 << CGEventType.keyUp.rawValue
        mask |= 1 << CGEventType.flagsChanged.rawValue
        mask |= 1 << CGEventType.leftMouseDown.rawValue
        mask |= 1 << CGEventType.rightMouseDown.rawValue
        mask |= 1 << CGEventType.otherMouseDown.rawValue
        mask |= 1 << CGEventType.leftMouseDragged.rawValue
        mask |= 1 << CGEventType.rightMouseDragged.rawValue
        mask |= 1 << CGEventType.otherMouseDragged.rawValue
        mask |= 1 << CGEventType.scrollWheel.rawValue

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, cgEvent: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        owningRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(owningRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let rl = owningRunLoop, let source = runLoopSource {
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        owningRunLoop = nil

        os_unfair_lock_lock(&stateLock)
        shiftDown = false
        otherKeyPressed = false
        os_unfair_lock_unlock(&stateLock)
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, cgEvent: CGEvent) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }

        switch type {

        case .flagsChanged:
            let flags = cgEvent.flags
            let shiftOn = flags.contains(.maskShift)
            let otherModifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn])

            if shiftOn {
                if !shiftDown {
                    shiftDown = true
                    otherKeyPressed = false
                }
                if !otherModifiers.isEmpty {
                    otherKeyPressed = true
                }
            } else {
                if shiftDown {
                    if !otherKeyPressed && otherModifiers.isEmpty {
                        let trigger = onShiftTrigger
                        os_unfair_lock_unlock(&stateLock)
                        trigger()
                        os_unfair_lock_lock(&stateLock)
                    }
                    shiftDown = false
                }
            }

        case .keyDown, .keyUp:
            if shiftDown {
                otherKeyPressed = true
            }

        default:
            if shiftDown {
                otherKeyPressed = true
            }
        }
    }
}
