import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.10:3000", text: $store.serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { testing = true; await store.refresh(); testing = false }
                } label: {
                    HStack { Text("Kiểm tra kết nối & tải quy tắc"); if testing { Spacer(); ProgressView() } }
                }
                if let msg = store.connectionMessage {
                    Label(msg, systemImage: store.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.isConnected ? Color.okGreen : Color.accent)
                        .font(.footnote)
                }
            } header: { Text("Địa chỉ server (web Warehouse Tina)") }
              footer: { Text("Điện thoại và máy chạy server phải cùng Wi-Fi. Dùng địa chỉ IP của máy tính (terminal server in ra dòng \"Dien thoai dung dia chi\"), không dùng localhost.") }

            Section("Quy tắc mã kho đang dùng (\(store.rules.count))") {
                ForEach(store.rules) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.customerGroup).font(.headline)
                        Text(r.patternRegex).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        .task { if store.hasServer { await store.refresh() } }
    }
}
