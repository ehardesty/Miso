import AppKit
import MisoCore
import MisoPlatform

final class InputService {
    private struct WheelKey: Hashable {
        let sender: UInt64
        let continuous: Bool
    }

    private struct Wheels {
        var vertical = WheelAxis()
        var horizontal = WheelAxis()
    }

    private struct ButtonKey: Hashable {
        let device: String
        let button: MouseButton
    }

    private enum Hold {
        case remap(UInt8)
        case consumed
        case waiting(ButtonMapping, Swipe, [CGEvent])
    }

    private enum ButtonRecording {
        case idle, listening
        case pressed(ButtonKey), cancelledPress(ButtonKey)

        var key: ButtonKey? {
            switch self {
            case let .pressed(key), let .cancelledPress(key): key
            case .idle, .listening: nil
            }
        }

        var isActive: Bool {
            switch self {
            case .listening, .pressed: true
            case .idle, .cancelledPress: false
            }
        }
    }

    private struct Subscription: OptionSet {
        let rawValue: UInt8
        static let buttons = Self(rawValue: 1)
        static let wheel = Self(rawValue: 2)
    }

    private let thread = EventThread()
    private var context = InputContext()
    private var tap: QuartzTap?
    private var subscription: Subscription = []
    private var motionTap: QuartzTap?
    private var motionEnabled = false
    private var profiles: [String: InputProfile] = [:]
    private var needs: Subscription = []
    private var mayNeedMotion = false
    private var lastStatus: InputStatus?
    private var wheels: [WheelKey: Wheels] = [:]
    private var holds: [ButtonKey: Hold] = [:]
    private var recording = ButtonRecording.idle
    private var allowed = false
    private var systemPaused = false
    private var wheelProbe: WheelProbe?

    var onStatus: ((InputStatus) -> Void)?
    var onButton: ((MouseButton) -> Void)?
    var onRecordingCancelled: (() -> Void)?

    private static let buttonTypes: [CGEventType] = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseUp, .rightMouseUp, .otherMouseUp
    ]
    private static let motionTypes: [CGEventType] = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
    ]

    func configure(_ context: InputContext, allowed: Bool) {
        thread.enqueue { [self] in
            let contextChanged = self.context != context
            if contextChanged {
                wheels.removeAll(keepingCapacity: true)
                let devices = context.nativeIDs.union(context.vendorIDs)
                let removed = self.context.nativeIDs.union(self.context.vendorIDs).subtracting(devices)
                for key in Array(holds.keys) where removed.contains(key.device) { cancel(key) }
                if let key = recording.key, removed.contains(key.device) { discardRecording() }
                self.context = context
                rebuildProfiles(devices: devices)
            }
            if self.allowed && !allowed { cancelInteractions() }
            let permissionsChanged = self.allowed != allowed
            self.allowed = allowed
            if contextChanged || permissionsChanged || lastStatus == nil || (tap == nil && !needs.isEmpty) {
                refreshTaps()
            }
        }
    }

    func setWheelProbe(_ probe: WheelProbe) {
        thread.enqueue { [self] in
            wheelProbe = probe
            if !subscription.contains(.wheel) { probe.record(.wheelInactive) }
        }
    }

    func removeWheelProbe(_ probe: WheelProbe) {
        thread.enqueue { [self] in
            if wheelProbe === probe { wheelProbe = nil }
        }
    }

    func resumeIfPaused() {
        thread.enqueue { [self] in
            guard systemPaused else { return }
            systemPaused = false
            refreshTaps()
        }
    }

    func shutdown(_ completion: @escaping () -> Void) {
        thread.enqueue { [self] in
            cancelInteractions()
            allowed = false
            dropTaps()
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func rebuildProfiles(devices: Set<String>) {
        profiles = Dictionary(uniqueKeysWithValues: devices.map { ($0, context.profile(device: $0)) })
        needs = []
        mayNeedMotion = false
        guard context.settings.enabled else { return }
        for id in context.nativeIDs {
            guard let profile = profiles[id] else { continue }
            if profile.changesWheel { needs.insert(.wheel) }
            if profile.mappings.contains(where: { mapping in
                if case .standard = mapping.button { return !mapping.button.isPrimary && mapping.isConfigured }
                return false
            }) {
                needs.insert(.buttons)
                mayNeedMotion = true
            }
        }
        if context.vendorIDs.contains(where: { id in
            profiles[id]?.mappings.contains(where: { !$0.swipes.isEmpty }) == true
        }) { mayNeedMotion = true }
    }

    func recordButton(_ enabled: Bool) {
        thread.enqueue { [self] in
            if !enabled {
                recording = recording.key.map(ButtonRecording.cancelledPress) ?? .idle
            } else if allowed, !systemPaused, recording.key == nil {
                recording = .listening
            } else {
                notifyRecordingCancelled()
            }
            refreshTaps()
        }
    }

    func handleVendor(_ event: VendorButtonEvent) {
        thread.enqueue { [self] in
            guard allowed, !systemPaused else { return }
            let key = ButtonKey(device: event.deviceID, button: event.button)
            let location = CGEvent(source: nil)?.location ?? .zero
            if event.pressed {
                _ = press(key, flags: [], location: location, native: nil)
            } else {
                _ = release(key, location: location, native: nil)
            }
            refreshTaps()
        }
    }

    func cancelVendor(deviceID: String) {
        thread.enqueue { [self] in
            for key in Array(holds.keys) where key.device == deviceID {
                if case .logitech = key.button { cancel(key) }
            }
            if let key = recording.key, key.device == deviceID, case .logitech = key.button {
                discardRecording()
            }
            refreshTaps()
        }
    }

    private func setStatus(_ status: InputStatus) {
        guard lastStatus != status else { return }
        lastStatus = status
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }

    private func refreshTaps() {
        guard allowed else {
            dropTaps()
            setStatus(context.settings.enabled ? .permissionRequired : .stopped)
            return
        }

        guard !systemPaused else {
            setStatus(context.settings.enabled
                ? .unavailable("macOS paused input capture. Check permissions to resume.")
                : .stopped)
            return
        }
        let hasNativeHold = holds.contains { key, _ in
            if case .standard = key.button { return true }
            return false
        }
        var desired = needs
        if recording.isActive || recording.key != nil || hasNativeHold { desired.insert(.buttons) }
        let observedWheel = subscription.contains(.wheel)
        var failed = false
        if desired.isEmpty {
            tap = nil
            subscription = []
        } else if tap == nil || subscription != desired {
            var types: [CGEventType] = []
            if desired.contains(.buttons) { types += Self.buttonTypes }
            if desired.contains(.wheel) { types.append(.scrollWheel) }
            if let replacement = QuartzTap(observing: types, callback: Self.callback, owner: callbackOwner) {
                tap = replacement
                subscription = desired
            } else {
                failed = true
            }
        }
        if observedWheel && !subscription.contains(.wheel) {
            wheelProbe?.record(.wheelInactive)
        }
        if mayNeedMotion || hasNativeHold || recording.isActive || recording.key != nil || !holds.isEmpty {
            if motionTap == nil {
                motionTap = QuartzTap(observing: Self.motionTypes, callback: Self.motionCallback, owner: callbackOwner)
                motionTap?.setEnabled(false)
                failed = failed || motionTap == nil
            }
            updateMotion()
        } else {
            motionTap = nil
            motionEnabled = false
        }
        if failed && recording.isActive { discardRecording() }
        setStatus(failed ? .unavailable("The macOS event tap could not start.")
            : context.settings.enabled ? .listening : .stopped)
    }

    private var callbackOwner: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func dropTaps() {
        tap = nil
        subscription = []
        motionTap = nil
        motionEnabled = false
    }

    private func updateMotion() {
        let needsMotion = recording.key.map { key in
            if case .standard = key.button { return true }
            return false
        } ?? false
        let enabled = needsMotion || holds.contains { key, hold in
            if case .standard = key.button { return true }
            if case .waiting = hold { return true }
            return false
        }
        guard motionEnabled != enabled else { return }
        motionEnabled = enabled
        motionTap?.setEnabled(enabled)
    }

    private func notifyRecordingCancelled() {
        DispatchQueue.main.async { [weak self] in self?.onRecordingCancelled?() }
    }

    private func discardRecording() {
        let wasActive = recording.isActive
        recording = .idle
        if wasActive { notifyRecordingCancelled() }
    }

    private func cancelInteractions() {
        for key in Array(holds.keys) { cancel(key) }
        discardRecording()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, owner in
        guard let owner else { return Unmanaged.passUnretained(event) }
        let service = Unmanaged<InputService>.fromOpaque(owner).takeUnretainedValue()
        return service.receive(type, event, fromMotionTap: false).map { Unmanaged.passUnretained($0) }
    }

    private static let motionCallback: CGEventTapCallBack = { _, type, event, owner in
        guard let owner else { return Unmanaged.passUnretained(event) }
        let service = Unmanaged<InputService>.fromOpaque(owner).takeUnretainedValue()
        return service.receive(type, event, fromMotionTap: true).map { Unmanaged.passUnretained($0) }
    }

    private func receive(_ type: CGEventType, _ event: CGEvent, fromMotionTap: Bool) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Disabling the idle motion tap can produce a disable notification.
            if fromMotionTap && !motionEnabled { return event }
            cancelInteractions()
            if type == .tapDisabledByUserInput {
                systemPaused = true
                thread.enqueue { [self] in
                    if systemPaused {
                        dropTaps()
                        refreshTaps()
                    }
                }
            } else if allowed && !fromMotionTap {
                tap?.setEnabled(true)
            }
            updateMotion()
            return event
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionDelivery.marker { return event }

        switch type {
        case .scrollWheel:
            transformWheel(event)
            return event
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard let key = buttonKey(event) else { return event }
            let result = press(key, flags: event.flags, location: event.location, native: event)
            updateMotion()
            return result
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard let key = buttonKey(event) else { return event }
            let result = release(key, location: event.location, native: event)
            thread.enqueue { [self] in refreshTaps() }
            return result
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return move(event)
        default:
            return event
        }
    }

    private func buttonKey(_ event: CGEvent) -> ButtonKey? {
        guard let number = UInt8(exactly: event.getIntegerValueField(.mouseEventButtonNumber)), number <= 31
        else { return nil }
        let button = MouseButton.standard(number)
        let sender = MTEventSender(event)
        if let device = context.mouseSenders[sender] { return ButtonKey(device: device, button: button) }
        if sender == 0 {
            // Some BLE side-button edges lack a sender. Attribute only when
            // the device is unambiguous, or continue an already-owned press.
            if let key = recording.key, key.button == button { return key }
            let matching = holds.keys.filter { $0.button == button }
            if matching.count == 1 { return matching[0] }
            if number >= 2, let mouse = soleMouse() { return ButtonKey(device: mouse, button: button) }
        }
        return nil
    }

    private func soleMouse() -> String? {
        guard let first = context.mouseSenders.values.first,
              context.mouseSenders.values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func press(_ key: ButtonKey, flags: CGEventFlags, location: CGPoint, native: CGEvent?) -> CGEvent? {
        if key.button.isPrimary { return native }
        if holds[key] != nil || recording.key == key { return nil }
        if case .listening = recording {
            recording = .pressed(key)
            return nil
        }
        if recording.isActive { return native }
        guard context.settings.enabled else { return native }
        guard let profile = profiles[key.device] else { return native }
        let modifiers = native == nil ? Modifiers() : Modifiers(flags: flags)
        guard let mapping = profile.mapping(for: key.button, modifiers: modifiers) else { return native }
        if !mapping.swipes.isEmpty {
            holds[key] = .waiting(mapping, Swipe(threshold: profile.swipeThreshold), native?.copy().map { [$0] } ?? [])
            return nil
        }

        if let action = mapping.tap {
            if case let .mouseButton(number) = action, let native, number <= 31 {
                ActionDelivery.rewrite(native, as: number)
                holds[key] = .remap(number)
                return native
            }
            ActionDelivery.perform(action, at: location)
        }
        holds[key] = .consumed
        return nil
    }

    private func release(_ key: ButtonKey, location: CGPoint, native: CGEvent?) -> CGEvent? {
        if recording.key == key {
            let captured = recording.isActive
            recording = .idle
            if captured {
                // Keep Logitech diversion armed until the captured press has released.
                DispatchQueue.main.async { [weak self] in self?.onButton?(key.button) }
            }
            return nil
        }
        guard let hold = holds.removeValue(forKey: key) else { return native }
        switch hold {
        case let .remap(number):
            if let native { ActionDelivery.rewrite(native, as: number) }
            return native
        case .consumed:
            return nil
        case let .waiting(mapping, _, events):
            if let action = mapping.tap {
                ActionDelivery.perform(action, at: location)
            } else if let native, let up = native.copy() {
                replay(events + [up])
            }
            return nil
        }
    }

    private func move(_ event: CGEvent) -> CGEvent? {
        let sender = MTEventSender(event)
        let device = context.mouseSenders[sender] ?? (sender == 0 ? soleMouse() : nil)
        guard let device else { return event }

        let nativeKey: ButtonKey? = event.type == .mouseMoved ? nil : buttonKey(event)
        if let nativeKey, nativeKey == recording.key { return nil }
        if let nativeKey, case let .remap(number)? = holds[nativeKey] {
            ActionDelivery.rewrite(event, as: number)
            return event
        }

        let key: ButtonKey
        if let nativeKey, holds[nativeKey] != nil {
            key = nativeKey
        } else {
            let candidates = holds.compactMap { key, hold -> ButtonKey? in
                guard key.device == device, case .logitech = key.button, case .waiting = hold else { return nil }
                return key
            }
            guard candidates.count == 1 else { return event }
            key = candidates[0]
        }
        guard case let .waiting(mapping, originalSwipe, originalEvents)? = holds[key] else {
            return nativeKey == key ? nil : event
        }

        var swipe = originalSwipe
        let x = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let y = Double(event.getIntegerValueField(.mouseEventDeltaY))
        if let action = swipe.move(x: x, y: y, actions: mapping.swipes) {
            holds[key] = .consumed
            ActionDelivery.perform(action, at: event.location)
            return nativeKey == key ? nil : event
        }

        var events = originalEvents
        if nativeKey == key, mapping.tap == nil, let copy = event.copy() {
            if events.count >= 64 {
                holds[key] = nil
                replay(events + [copy])
                return nil
            }
            events.append(copy)
        }
        holds[key] = .waiting(mapping, swipe, events)
        return nativeKey == key ? nil : event
    }

    private func cancel(_ key: ButtonKey) {
        guard let hold = holds.removeValue(forKey: key) else { return }
        if case let .remap(number) = hold,
           let event = ActionDelivery.mouseEvent(number, pressed: false, at: CGEvent(source: nil)?.location ?? .zero) {
            ActionDelivery.post(event)
        }
    }

    private func replay(_ events: [CGEvent]) {
        for event in events { ActionDelivery.post(event) }
    }

    private func transformWheel(_ event: CGEvent) {
        guard context.settings.enabled else { return }
        guard event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else {
            wheelProbe?.record(.gesture)
            return
        }
        var rawVertical = 0.0
        var rawHorizontal = 0.0
        var eventTime: UInt64 = 0
        let sender = MTReadScrollDevice(event, &rawVertical, &rawHorizontal, &eventTime)
        guard let device = context.mouseSenders[sender], let profile = profiles[device] else {
            wheelProbe?.record(.unknownMouse)
            return
        }
        let changesWheel = profile.changesWheel
        guard changesWheel || wheelProbe != nil else { return }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let timestamp = eventTime == 0 ? DispatchTime.now().uptimeNanoseconds : eventTime
        let key = WheelKey(sender: sender, continuous: continuous)
        var state = wheels[key] ?? Wheels()
        if changesWheel {
            Self.transformAxis(
                event, axis: &state.vertical, settings: profile.verticalWheel,
                reversed: profile.reverseVertical, continuous: continuous, rawUnits: rawVertical, timestamp: timestamp,
                fields: QuartzWheelAxis.vertical.fields
            )
            Self.transformAxis(
                event, axis: &state.horizontal, settings: profile.horizontalWheel,
                reversed: profile.reverseHorizontal, continuous: continuous, rawUnits: rawHorizontal,
                timestamp: timestamp,
                fields: QuartzWheelAxis.horizontal.fields
            )
            wheels[key] = state
        }
        wheelProbe?.record(
            event, device: device, app: context.app, profile: profile, continuous: continuous,
            raw: (rawVertical, rawHorizontal),
            rates: (state.vertical.stepsPerSecond, state.horizontal.stepsPerSecond), timestamp: timestamp
        )
    }

    private static func transformAxis(
        _ event: CGEvent, axis: inout WheelAxis, settings: AxisSettings, reversed: Bool, continuous: Bool,
        rawUnits: Double, timestamp: UInt64,
        fields: (lines: CGEventField, fixed: CGEventField, points: CGEventField)
    ) {
        guard settings.changesWheel || reversed else { return }
        let old = WheelDelta(
            lines: event.getIntegerValueField(fields.lines),
            fixed: event.getDoubleValueField(fields.fixed),
            points: event.getDoubleValueField(fields.points)
        )
        let value = axis.transform(
            old, settings: settings, reversed: reversed, continuous: continuous,
            timestamp: timestamp, rawUnits: rawUnits
        )
        guard value != old else { return }
        // The least precise field is written first. Writing it last can
        // re-derive the finer fields from quantized line deltas.
        event.setIntegerValueField(fields.lines, value: value.lines)
        event.setDoubleValueField(fields.points, value: value.points)
        event.setDoubleValueField(fields.fixed, value: value.fixed)
    }
}
