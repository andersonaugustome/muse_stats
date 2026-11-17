import SwiftUI

@main
struct MuseStatsApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 680)

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Label("Muse Stats", systemImage: "waveform.path.ecg")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot = SharedStore.load()
    @Published var isRefreshing = false

    init() {
        Task { await refresh() }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await self.refresh() }
        }
    }

    func refresh() async {
        isRefreshing = true
        snapshot = await UsageService.load()
        SharedStore.save(snapshot)
        isRefreshing = false
    }
}
