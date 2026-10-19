import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var store: AppStore
    @State private var sessions: [ReceivingSession] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showSettings = false
    @State private var showNew = false
    @State private var created: ReceivingSession?
    @State private var openCreated = false

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(Color.accent)
            }
            Section(tr("Phiên đang mở trên web")) {
                if sessions.isEmpty && !loading {
                    Text(tr("Chưa có phiên nào đang mở. Hãy tạo phiên trên web (nút \"Bắt đầu phiên mới\"), rồi kéo xuống hoặc bấm ↻ để làm mới.")).foregroundStyle(.secondary)
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
        .navigationTitle(tr("Phiên nhận hàng"))
        .navigationDestination(for: ReceivingSession.self) { SessionDetailView(session: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
            ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel(tr("Bắt đầu phiên mới")) }
        }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showNew, onDismiss: {
            if created != nil { openCreated = true }       // tạo xong → vào quét ngay (giống web)
        }) {
            NavigationStack { NewSessionView { s in created = s } }
        }
        .navigationDestination(isPresented: $openCreated) {
            if let s = created { SessionDetailView(session: s) }
        }
        .onChange(of: openCreated) { open in if !open { created = nil; Task { await load() } } }
        .task { await store.refresh(); await load(); _ = await PhotoOutbox.flush(api: store.api) }   // gửi bù ảnh label còn sót
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
