import Foundation
import MisoCore
import Testing

@Test func appCanUseGlobalSpeedOverDeviceSpeedUntilCleared() throws {
    var settings = Settings()
    var mouse = ProfileOverrides()
    mouse.verticalWheel.speed = 2
    mouse.reverseHorizontal = true
    settings.deviceProfiles["mouse"] = mouse

    var editor = ProfileOverrides()
    editor.verticalWheel.speed = 1
    editor.reverseHorizontal = false
    settings.appProfiles["editor"] = editor
    settings.global.verticalWheel.acceleration = 1

    settings = try roundTrip(settings)
    let effective = settings.profile(device: "mouse", app: "editor")
    #expect(effective.verticalWheel == AxisSettings(speed: 1, acceleration: 1))
    #expect(!effective.reverseHorizontal)

    settings.appProfiles["editor"]?.verticalWheel.speed = nil
    settings.appProfiles["editor"]?.reverseHorizontal = nil
    let inherited = settings.profile(device: "mouse", app: "editor")
    #expect(inherited.verticalWheel == AxisSettings(speed: 2, acceleration: 1))
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

@Test func legacyAppSnapshotKeepsLocalActionsAndLetsCopiedRowsInherit() throws {
    let legacyJSON = """
        {
          "enabled": true,
          "global": {
            "pointer": {"speed":1,"acceleration":0},
            "verticalWheel": {"speed":1,"acceleration":0},
            "horizontalWheel": {"speed":1,"acceleration":0},
            "reverseVertical":false,"reverseHorizontal":false,"swipeThreshold":50,
            "mappings":[
              {"id":"2DC29FEE-2416-4763-9FD7-F2B802BB9BBB","button":{"standard":{"_0":3}},
               "modifiers":0,"tap":{"back":{}},"swipes":[]}
            ]
          },
          "deviceProfiles": {
            "mouse":{"pointer":{},"verticalWheel":{},"horizontalWheel":{},"mappings":[
              {"id":"2DC29FEE-2416-4763-9FD7-F2B802BB9BBB","button":{"standard":{"_0":3}},
               "modifiers":0,"tap":{"showDesktop":{}},"swipes":[]}
            ]}
          },
          "appProfiles": {
            "editor":{"pointer":{},"verticalWheel":{"speed":2},"horizontalWheel":{},"mappings":[
              {"id":"2DC29FEE-2416-4763-9FD7-F2B802BB9BBB","button":{"standard":{"_0":3}},
               "modifiers":0,"tap":{"back":{}},"swipes":[]},
              {"id":"B770FDF5-E3E2-425B-A78A-0B58BE9D4AD0","button":{"standard":{"_0":4}},
               "modifiers":0,"tap":{"missionControl":{}},"swipes":[]}
            ]}
          }
        }
        """
    let migrated = try JSONDecoder().decode(Settings.self, from: Data(legacyJSON.utf8))
    let settings = try roundTrip(migrated)
    let effective = settings.profile(device: "mouse", app: "editor")

    #expect(effective.verticalWheel.speed == 2)
    #expect(effective.mapping(for: .standard(3), modifiers: [])?.tap == .showDesktop)
    #expect(effective.mapping(for: .standard(4), modifiers: [])?.tap == .missionControl)
    #expect(settings.profile(device: nil, app: "editor").mapping(for: .standard(3), modifiers: [])?.tap == .back)
}

private func roundTrip(_ settings: Settings) throws -> Settings {
    try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
}
