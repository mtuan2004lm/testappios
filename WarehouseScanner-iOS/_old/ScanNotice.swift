import Foundation

/// Thông báo kết quả hiển thị trên màn hình quét.
struct ScanNotice: Equatable, Identifiable {
    enum Kind { case success, business, unknown, duplicate, error }
    let id = UUID()
    let kind: Kind
    let barcode: String
    let title: String
    let detail: String?
    var itemId: FlexID? = nil      // để nút "không đủ điều kiện nhập khẩu" biết đổi kiện nào
}

struct ScanLog: Identifiable {
    let id = UUID()
    let barcode: String
    let group: String?
    let kind: ScanNotice.Kind
    let time: Date
}
