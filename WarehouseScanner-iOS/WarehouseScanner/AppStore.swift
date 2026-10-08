import Foundation
import SwiftUI

/// Trạng thái dùng chung: địa chỉ server, bộ quy tắc mã kho (lưu cache để dùng khi mất mạng).
@MainActor
final class AppStore: ObservableObject {
    @Published var serverURL: String { didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") } }
    @Published private(set) var rules: [WarehouseRule] = []
    @Published private(set) var matcher = RuleMatcher(rules: [])
    @Published var connectionMessage: String?
    @Published var isConnected = false

    /// Địa chỉ dùng sẵn khi app mới cài (chưa có gì được lưu). Dùng tên máy Mac (.local) nên không đổi khi IP thay đổi.
    /// Muốn đổi: sửa dòng này rồi Run lại, hoặc nhập trong ⚙️ (địa chỉ nhập tay được ưu tiên và được nhớ).
    /// Dấu bản build, hiện trong ⚙️ để biết iPhone đang chạy bản nào (đổi mỗi lần sửa logic quét).
    static let buildTag = "2026-10-08 · nhóm KH / mã kho / loại hình"

    static let defaultServerURL = "http://MacBook-Air-cua-Minh.local:3000"

    var api: APIClient { APIClient(baseURL: serverURL) }
    var hasServer: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        let saved = UserDefaults.standard.string(forKey: "serverURL")?.trimmingCharacters(in: .whitespaces) ?? ""
        serverURL = saved.isEmpty ? AppStore.defaultServerURL : saved
        if let data = UserDefaults.standard.data(forKey: "cachedRules"),
           let cached = try? JSONDecoder().decode([WarehouseRule].self, from: data) {
            apply(cached)
        }
    }

    private func apply(_ r: [WarehouseRule]) {
        rules = r
        matcher = RuleMatcher(rules: r)
    }

    /// Kiểm tra kết nối rồi tải bộ quy tắc mới nhất từ web.
    func refresh() async {
        guard hasServer else { connectionMessage = "Chưa nhập địa chỉ server"; isConnected = false; return }
        do {
            _ = try await api.health()
            let fresh = try await api.rules()
            apply(fresh)
            if let data = try? JSONEncoder().encode(fresh) { UserDefaults.standard.set(data, forKey: "cachedRules") }
            isConnected = true
            connectionMessage = "Đã kết nối · \(fresh.count) quy tắc mã kho"
        } catch {
            isConnected = false
            connectionMessage = error.localizedDescription + (rules.isEmpty ? "" : " (đang dùng \(rules.count) quy tắc đã lưu)")
        }
    }
}
