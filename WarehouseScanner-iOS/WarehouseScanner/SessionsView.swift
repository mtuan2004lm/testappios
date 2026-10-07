import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var store: AppStore
    @State private var sessions: [ReceivingSession] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showSettings = false

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(Color.accent)
            }
            Section("Phiên đang mở trên web") {
                if sessions.isEmpty && !loading {
                    Text("Chưa có phiên nào đang mở. Hãy tạo phiên trên web (nút \"Bắt đầu phiên mới\"), rồi kéo xuống hoặc bấm ↻ để làm mới.").foregroundStyle(.secondary)
                }
                ForEach(sessions) { s in
                    NavigationLink(value: s) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.title).font(.headline)
                                Text(s.carrierName).font(.subheadline).foregroundStyle(Color.accent)
                                Spacer()
                                Text("\(s.scannedCount) / \(s.totalExpectedPackages)").font(.title3.monospacedDigit().bold())
                            }
                            Text([s.licensePlate, s.driverName, s.gateCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay { if loading && sessions.isEmpty { ProgressView() } }
        .navigationTitle("Phiên nhận hàng")
        .navigationDestination(for: ReceivingSession.self) { AutoScanView(session: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
        }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .task { await store.refresh(); await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard store.hasServer else { return }
        loading = true
        defer { loading = false }
        do { sessions = try await store.api.openSessions(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
