import SwiftUI

@main
struct HVMeldeApp: App {
    @StateObject private var store = AppDataStore()
    @AppStorage(AppLanguagePreference.storageKey) private var appLanguageRawValue = AppLanguagePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, appLanguage.locale)
        }
    }

    private var appLanguage: AppLanguagePreference {
        AppLanguagePreference(rawValue: appLanguageRawValue) ?? .system
    }
}
