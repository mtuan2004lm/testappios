import Foundation

// MARK: - Mô hình dữ liệu khớp với API của web (snake_case -> camelCase tự động)

/// id của kiện là BIGSERIAL nên server trả về chuỗi ("21"); chấp nhận cả số lẫn chuỗi.
struct FlexID: Codable, Hashable {
    let value: String
    init(_ value: String) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = String(i) }
        else { value = try c.decode(String.self) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

struct WarehouseRule: Codable, Identifiable, Hashable {
    let id: Int
    let customerGroup: String
    let patternRegex: String
    let businessType: String          // KINH_DOANH | KHONG_KINH_DOANH
    let requiresImportCheck: Bool
    let isActive: Bool
    var isBusiness: Bool { businessType == "KINH_DOANH" }
}

struct ReceivingSession: Codable, Identifiable, Hashable {
    let id: Int
    let carrierName: String
    let driverName: String?
    let licensePlate: String?
    let gateCode: String?
    let status: String                // OPEN | CLOSED
    let totalExpectedPackages: Int
    let scannedCount: Int
    var title: String { "Phiên #" + String(format: "%04d", id) }
}

struct ScannedItem: Codable, Identifiable, Hashable {
    let id: FlexID
    let sessionId: Int
    let barcode: String
    let detectedWarehouseCode: String?
    let customerGroup: String?
    let businessType: String?
    let exceptionStatus: String
}

struct Pagination: Codable { let page: Int; let limit: Int; let total: Int; let totalPages: Int }
struct ListResponse<T: Decodable>: Decodable { let data: [T]; let pagination: Pagination? }
struct ObjectResponse<T: Decodable>: Decodable { let data: T }

struct ScanData: Decodable {
    let item: ScannedItem
    let scannedCount: Int
    let totalExpectedPackages: Int
    let inRegistry: Bool
    let requiresImportCheck: Bool
    let warning: String?
}

struct ClassifyData: Decodable {
    let item: ScannedItem
    let matched: Bool
    let requiresImportCheck: Bool?
    let warning: String?
}

struct PhotoData: Decodable { let item: ScannedItem; let photoUrl: String }

// MARK: - Lỗi

struct APIError: LocalizedError {
    let status: Int          // 0 = lỗi mạng
    let code: String?
    let message: String
    var errorDescription: String? { message }
    var isDuplicate: Bool { code == "DUPLICATE_BARCODE" }
    var isNetwork: Bool { status == 0 }
}
