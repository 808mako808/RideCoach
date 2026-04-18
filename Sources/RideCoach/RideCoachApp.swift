import SwiftUI

@main
struct RideCoachApp: App {
    @StateObject private var store = RideCoachStore()

    var body: some Scene {
        MenuBarExtra(AppInfo.fullName, systemImage: "bicycle") {
            MenuView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    store.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
