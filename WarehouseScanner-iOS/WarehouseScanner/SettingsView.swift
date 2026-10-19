import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false
    @AppStorage(AutoScanViewModel.autoShotKey) private var autoShot = true

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
                    HStack { Text(tr("Kiểm tra kết nối & tải quy tắc")); if testing { Spacer(); ProgressView() } }
                }
                if let msg = store.connectionMessage {
                    Label(msg, systemImage: store.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.isConnected ? Color.okGreen : Color.accent)
                        .font(.footnote)
                }
            } header: { Text(tr("Địa chỉ server (web Warehouse Tina)")) }
              footer: { Text(tr("Điện thoại và máy chạy server phải cùng Wi-Fi. Dùng địa chỉ IP của máy tính (terminal server in ra dòng \"Dien thoai dung dia chi\"), không dùng localhost.")) }

            Section {
                Toggle(tr("Tự chụp ảnh label khi quét"), isOn: $autoShot)
            } footer: { Text(tr("Mỗi lần quét, app lưu khung hình camera và gửi lên kiện (hiện ở mục Ảnh label trên web để nhân viên VN kiểm tra).")) }

            Section {
                Picker("Ngôn ngữ / Language", selection: $lang.code) {
                    Text("Tiếng Việt").tag("vi")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            } header: { Text("Ngôn ngữ / Language") }

            Section {
                LabeledContent(tr("Tài khoản"), value: auth.userEmail)
                Button(tr("Đăng xuất"), role: .destructive) { dismiss(); auth.signOut() }
            }

            Section { LabeledContent(tr("Bản app"), value: AppStore.buildTag) }

            Section(tr("Quy tắc mã kho đang dùng ({0})", store.rules.count)) {
                ForEach(store.rules) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.customerGroup).font(.headline)
                        Text(r.patternRegex).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(tr("Cài đặt"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        .task { if store.hasServer { await store.refresh() } }
    }
}
