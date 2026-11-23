import Foundation
import MisoCore
import Testing

@Test func appCanUseGlobalSpeedOverDeviceSpeedUntilCleared() throws {
    var settings = Settings()
    var mouse = ProfileOverrides()
    mouse.verticalWheel.boostSpeed = 2
    mouse.reverseHorizontal = true
    settings.deviceProfiles["mouse"] = mouse

    var editor = ProfileOverrides()
    editor.verticalWheel.boostSpeed = 1
    editor.reverseHorizontal = false
    settings.appProfiles["editor"] = editor
    settings.global.verticalWheel.mode = .boost
    settings.global.verticalWheel.boost = 1

    settings = try roundTrip(settings)
    let effective = settings.profile(device: "mouse", app: "editor")
    #expect(effective.verticalWheel == AxisSettings(mode: .boost, boost: 1))
    #expect(!effective.reverseHorizontal)

    settings.appProfiles["editor"]?.verticalWheel.boostSpeed = nil
    settings.appProfiles["editor"]?.reverseHorizontal = nil
    let inherited = settings.profile(device: "mouse", app: "editor")
    #expect(inherited.verticalWheel == AxisSettings(mode: .boost, speed: 2, boost: 1))
    #expect(inherited.reverseHorizontal)
}

@Test func appButtonEditsOverrideOnlyTheConfiguredTrigger() throws {
    var settings = Settings()
    let back = ButtonMapping(button: .standard(3), tap: .back)
    let shiftedBack = ButtonMapping(button: .standard(3), modifiers: .shift, tap: .showDesktop)
    let gesture = ButtonMapping(button: .logitech(0x00C3), swipes: [.up: .missionControl])
    settings.global.mappings = [back, shiftedBack]
    var mouse = ProfileOverrides()
    mouse.setDeviceButtonMappings([back, shiftedBack, gesture], inheriting: settings.global.mappings)
    settings.deviceProfiles["mouse"] = mouse

    var editor = ProfileOverrides()
    editor.appButtonMappings = [
        ButtonMapping(button: back.button, tap: .doNothing),
        ButtonMapping(button: gesture.button)
    ]
    settings.appProfiles["editor"] = editor

    settings = try roundTrip(settings)
    let effective = settings.profile(device: "mouse", app: "editor")
    #expect(effective.mapping(for: back.button, modifiers: [])?.tap == .doNothing)
    #expect(effective.mapping(for: back.button, modifiers: .shift)?.tap == .showDesktop)
    #expect(effective.mapping(for: gesture.button, modifiers: [])?.swipes[.up] == .missionControl)

    settings.appProfiles["editor"]?.appButtonMappings.removeFirst()
    let inherited = settings.profile(device: "mouse", app: "editor")
    #expect(inherited.mapping(for: back.button, modifiers: [])?.tap == .back)
}

@Test func wheelRampSurvivesRelaunchAndInheritsByAxis() throws {
    var settings = Settings()
    let mouseRamp = WheelRamp(startRate: 35, fullRate: 70, curve: .gradual)
    let appRamp = WheelRamp(startRate: 40, fullRate: 80, curve: .quick)
    settings.global.verticalWheel.mode = .boost
    settings.global.verticalWheel.boost = 2
    settings.deviceProfiles["mouse", default: ProfileOverrides()].verticalWheel.wheelRamp = mouseRamp
    settings.appProfiles["editor", default: ProfileOverrides()].verticalWheel.wheelRamp = appRamp

    settings = try roundTrip(settings)
    let editorProfile = settings.profile(device: "mouse", app: "editor")
    #expect(editorProfile.verticalWheel == AxisSettings(mode: .boost, boost: 2, wheelRamp: appRamp))
    #expect(editorProfile.horizontalWheel == AxisSettings())

    settings.appProfiles["editor"]?.verticalWheel.wheelRamp = nil
    #expect(settings.profile(device: "mouse", app: "editor").verticalWheel.wheelRamp == mouseRamp)
}

@Test func switchingModesRestoresSavedTuning() throws {
    var settings = Settings()
    settings.global.pointer[keyPath: AxisSettings.speedField(for: .linear)] = 0.8
    settings.global.pointer[keyPath: AxisSettings.speedField(for: .boost)] = 1.4
    settings.global.pointer.boost = 0.9
    settings.global.verticalWheel[keyPath: AxisSettings.speedField(for: .linear)] = 1.5
    settings.global.verticalWheel[keyPath: AxisSettings.speedField(for: .boost)] = 0.75
    settings.global.verticalWheel.boost = 7

    settings = try roundTrip(settings)
    #expect(settings.global.pointer.activePointer == AxisSettings())
    #expect(!settings.global.changesWheel)

    settings.global.pointer.mode = .boost
    settings.global.verticalWheel.mode = .boost
    #expect(settings.global.pointer.activePointer == AxisSettings(mode: .boost, speed: 1.4, boost: 0.9))
    #expect(settings.global.verticalWheel.speed == 0.75)
    #expect(settings.global.verticalWheel.wheelAccelerationAmount == 7)

    settings.global.pointer.mode = .linear
    settings.global.verticalWheel.mode = .linear
    #expect(settings.global.pointer.speed == 0.8)
    #expect(settings.global.verticalWheel.speed == 1.5)
}

@Test func appTuningAppliesOnlyToMiceUsingThatMode() throws {
    var settings = Settings()
    settings.global.verticalWheel.systemSpeed = 1.2
    settings.deviceProfiles["mouse", default: ProfileOverrides()].verticalWheel.mode = .boost
    settings.deviceProfiles["mouse"]?.verticalWheel.boostSpeed = 0.8
    settings.appProfiles["editor", default: ProfileOverrides()]
        .verticalWheel[keyPath: ProfileOverrides.Axis.speedField(for: .system)] = 2
    settings.appProfiles["editor"]?.verticalWheel.boost = 3

    settings = try roundTrip(settings)
    let native = settings.profile(device: "otherMouse", app: "editor").verticalWheel
    let custom = settings.profile(device: "mouse", app: "editor").verticalWheel
    #expect(native.mode == .system && native.speed == 2 && native.acceleration == 0)
    #expect(custom.mode == .boost && custom.speed == 0.8 && custom.acceleration == 3)
    #expect(settings.profile(device: "mouse", app: nil).verticalWheel.wheelAccelerationAmount == 1)

    settings.appProfiles["editor"]?.verticalWheel.mode = .system
    #expect(settings.profile(device: "mouse", app: "editor").verticalWheel.speed == 2)
    #expect(settings.profile(device: "mouse", app: nil).verticalWheel.speed == 0.8)
}

private func roundTrip(_ settings: Settings) throws -> Settings {
    try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
}
