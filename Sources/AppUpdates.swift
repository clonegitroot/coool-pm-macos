import SwiftUI

#if canImport(Sparkle)
import Sparkle

@MainActor
final class AppUpdates {
    static let shared: AppUpdates? = {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return nil }
        return AppUpdates()
    }()

    let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.sendsSystemProfile = false
        controller.updater.automaticallyDownloadsUpdates = false
        controller.startUpdater()
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }
}

struct AppUpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if let updates = AppUpdates.shared {
                CheckForUpdatesButton(updates: updates)
            }
        }
    }
}

struct AppUpdateSettings: View {
    var body: some View {
        if let updates = AppUpdates.shared {
            UpdatePreferences(updates: updates)
        }
    }
}

private struct CheckForUpdatesButton: View {
    let updates: AppUpdates
    @State private var available = false

    var body: some View {
        Button("Check for Updates…") {
            updates.controller.checkForUpdates(nil)
        }
        .disabled(!available)
        .onReceive(updates.controller.updater.publisher(for: \.canCheckForUpdates)) { available = $0 }
    }
}

private struct UpdatePreferences: View {
    let updates: AppUpdates
    @State private var automaticChecks = false

    var body: some View {
        let updater = updates.controller.updater
        LabeledContent("Installed version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        Toggle("Check for updates automatically", isOn: Binding(
            get: { automaticChecks },
            set: { updater.automaticallyChecksForUpdates = $0 }
        ))
        .onReceive(updater.publisher(for: \.automaticallyChecksForUpdates)) { automaticChecks = $0 }
        Text("Update checks contact the Coool PM update server. Installation requires your confirmation.")
            .foregroundStyle(.secondary)
        CheckForUpdatesButton(updates: updates)
    }
}
#else
enum AppUpdates {
    static let shared: AppUpdates? = nil
}

struct AppUpdateSettings: View {
    var body: some View { EmptyView() }
}
#endif
