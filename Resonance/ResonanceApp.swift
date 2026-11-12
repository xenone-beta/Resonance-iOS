import SwiftUI

@main
struct ResonanceApp: App {
    @StateObject private var settings = Settings()
    @StateObject private var library = Library()
    @StateObject private var userData = UserData()
    @StateObject private var player = PlayerModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(userData)
                .environmentObject(player)
                .environment(\.locale, settings.locale)
                .preferredColorScheme(settings.colorScheme)
                .task {
                    player.library = library
                    await library.rescan()
                }
        }
    }
}
