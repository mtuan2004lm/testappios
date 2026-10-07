import Foundation

/// Gọi REST API của web "Warehouse Tina" (Express). Mọi lệnh gọi đều có timeout ngắn để đảm bảo xử lý trong 3-5 giây.
struct APIClient {
    let baseURL: String   // vd: http://192.168.1.10:3000

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable { let code: String?; let message: String? }
        let error: Inner?
    }

    private func makeURL(_ path: String) throws -> URL {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path) else {
            throw APIError(status: 0, code: "BAD_URL", message: "Địa chỉ server không hợp lệ")
        }
        return url
    }

    private func perform<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil,
                                       raw: Data? = nil, contentType: String? = nil,
                                       timeout: TimeInterval = 6) async throws -> T {
        var req = URLRequest(url: try makeURL(path), timeoutInterval: timeout)
        req.httpMethod = method
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let raw {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = raw
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            // Hiện địa chỉ đang dùng + mã lỗi thật để biết nguyên nhân:
            //  -1009 không có mạng / bị chặn quyền Mạng cục bộ · -1004 không kết nối được tới máy chủ · -1001 quá thời gian
            //  -1003 không tìm thấy tên máy · -1022 bị chặn http (ATS) · -1200/-1202 lỗi chứng chỉ https
            let ns = error as NSError
            throw APIError(status: 0, code: "NETWORK",
                           message: "Không kết nối được tới \(baseURL)\nLỗi: \(error.localizedDescription) (mã \(ns.code))")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let env = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            throw APIError(status: status, code: env?.error?.code, message: env?.error?.message ?? "Lỗi server (\(status))")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    // MARK: Endpoints

    func health() async throws -> Bool {
        struct H: Decodable { let ok: Bool }
        let h: H = try await perform("GET", "/api/health", timeout: 4)
        return h.ok
    }

    func rules() async throws -> [WarehouseRule] {
        let r: ListResponse<WarehouseRule> = try await perform("GET", "/api/v1/warehouse/rules")
        return r.data
    }

    func openSessions() async throws -> [ReceivingSession] {
        let r: ListResponse<ReceivingSession> = try await perform("GET", "/api/v1/receiving/sessions?status=OPEN&limit=50")
        return r.data
    }

    /// Gửi một nhãn (mã vạch + mã kho đọc được) lên phiên.
    func scan(sessionId: Int, barcode: String, detectedText: String) async throws -> ScanData {
        let r: ObjectResponse<ScanData> = try await perform("POST", "/api/v1/receiving/sessions/\(sessionId)/scan",
                                                            json: ["barcode": barcode, "detected_text": detectedText], timeout: 5)
        return r.data
    }

    /// Module 2: gửi mã kho đọc được từ nhãn để gán nhóm khách hàng.
    func classify(sessionId: Int, barcode: String, detectedText: String) async throws -> ClassifyData {
        let r: ObjectResponse<ClassifyData> = try await perform("POST", "/api/v1/receiving/sessions/\(sessionId)/classify",
                                                                json: ["barcode": barcode, "detected_text": detectedText], timeout: 5)
        return r.data
    }

    /// Đổi KINH_DOANH <-> KHONG_KINH_DOANH (khi hàng không đủ điều kiện nhập khẩu).
    func toggleBusinessType(itemId: FlexID) async throws -> ScannedItem {
        let r: ObjectResponse<ScannedItem> = try await perform("PATCH", "/api/v1/scanned-items/\(itemId.value)/toggle-business-type")
        return r.data
    }

    /// Gắn ảnh hàng hỏng vào kiện (server tự đánh dấu DAMAGED).
    func uploadDamagePhoto(itemId: FlexID, jpeg: Data) async throws -> PhotoData {
        let r: ObjectResponse<PhotoData> = try await perform("POST", "/api/v1/scanned-items/\(itemId.value)/damage-photo",
                                                             raw: jpeg, contentType: "image/jpeg", timeout: 20)
        return r.data
    }
}
