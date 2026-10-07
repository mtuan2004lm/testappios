import SwiftUI

@main
struct WarehouseScannerApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSettings = false

    var body: some View {
        NavigationStack { SessionsView() }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .onAppear { if !store.hasServer { showSettings = true } }
    }
}
