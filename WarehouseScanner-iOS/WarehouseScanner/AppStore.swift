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

    var api: APIClient { APIClient(baseURL: serverURL) }
    var hasServer: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
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
