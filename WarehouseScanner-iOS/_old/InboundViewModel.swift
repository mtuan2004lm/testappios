import SwiftUI
import AudioToolbox

/// MODULE 1 - Nhập kho: camera chạy liên tục, mỗi mã vạch thấy được là gửi nền lên server ngay,
/// không chờ kết quả mới quét tiếp (quét nhiều kiện liên tiếp không bị khựng).
@MainActor
final class InboundViewModel: ObservableObject {
    @Published var notice: ScanNotice?
    @Published var scanned: Int
    @Published var total: Int
    @Published var logs: [ScanLog] = []
    @Published var inFlight = 0                  // số mã đang chờ server trả lời
    @Published var lastItem: ScannedItem?        // kiện quét thành công gần nhất -> nút "Báo hỏng" gắn ảnh vào kiện này
    @Published var banner: String?               // thông báo ngắn (vd: đã gửi ảnh)

    let session: ReceivingSession
    var api: APIClient?

    private var recent: [String: Date] = [:]     // chống đọc lặp khi vẫn đang giữ nhãn trước camera
    private let repeatWindow: TimeInterval = 3
    private var noticeTask: Task<Void, Never>?

    init(session: ReceivingSession) {
        self.session = session
        scanned = session.scannedCount
        total = session.totalExpectedPackages
    }

    /// Gọi mỗi khi camera thấy mã vạch.
    func handle(_ codes: [String]) {
        let now = Date()
        for raw in codes {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            if let t = recent[code], now.timeIntervalSince(t) < repeatWindow { continue }
            recent[code] = now
            if recent.count > 300 { recent = recent.filter { now.timeIntervalSince($0.value) < 60 } }

            Haptics.tick()
            AudioServicesPlaySystemSound(1057)   // tiếng "tick" ngắn báo đã bắt được mã
            inFlight += 1
            Task { await send(code) }            // gửi nền, không chặn camera
        }
    }

    private func send(_ code: String) async {
        defer { inFlight -= 1 }
        guard let api else { return }
        do {
            let data: ScanData
            do { data = try await api.scan(sessionId: session.id, barcode: code) }
            catch let e as APIError where e.isNetwork {
                try? await Task.sleep(nanoseconds: 800_000_000)   // mạng chập chờn: thử lại 1 lần
                data = try await api.scan(sessionId: session.id, barcode: code)
            }
            scanned = data.scannedCount
            total = data.totalExpectedPackages
            lastItem = data.item
            let group = data.item.customerGroup
            if data.item.exceptionStatus == "UNKNOWN" {
                present(.init(kind: .unknown, barcode: code, title: "ĐÃ NHẬN", detail: data.warning), group: group)
                Haptics.warning()
            } else if data.item.businessType == "KINH_DOANH" {
                present(.init(kind: .business, barcode: code, title: "HÀNG KINH DOANH", detail: group, itemId: data.item.id), group: group)
                Haptics.warning()
            } else {
                present(.init(kind: .success, barcode: code, title: "ĐÃ KIỂM TRA ✓", detail: group), group: group)
                Haptics.success()
            }
        } catch let e as APIError {
            if e.isDuplicate {
                present(.init(kind: .duplicate, barcode: code, title: "MÃ TRÙNG", detail: "Đã quét trong phiên này"), group: nil)
                Haptics.warning()
            } else {
                present(.init(kind: .error, barcode: code, title: "LỖI", detail: e.message), group: nil)
                recent[code] = nil               // cho phép quét lại ngay
                Haptics.error()
            }
        } catch {
            present(.init(kind: .error, barcode: code, title: "LỖI", detail: error.localizedDescription), group: nil)
            recent[code] = nil
        }
    }

    private func present(_ n: ScanNotice, group: String?) {
        notice = n
        logs.insert(ScanLog(barcode: n.barcode, group: group, kind: n.kind, time: Date()), at: 0)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    /// Hàng kinh doanh không đủ điều kiện nhập khẩu -> chuyển thành không kinh doanh.
    func demoteToNonBusiness(_ n: ScanNotice) async {
        guard let api, let id = n.itemId else { return }
        do {
            _ = try await api.toggleBusinessType(itemId: id)
            notice = .init(kind: .success, barcode: n.barcode, title: "ĐÃ CHUYỂN: KHÔNG KINH DOANH", detail: n.detail)
            Haptics.success()
        } catch { banner = error.localizedDescription }
    }

    /// Gắn ảnh hàng hỏng vào đúng kiện `item` (kiện được chọn ngay lúc bấm nút).
    func uploadDamagePhoto(_ image: UIImage, for item: ScannedItem) async {
        guard let api, let jpeg = image.resized(maxSide: 1600).jpegData(compressionQuality: 0.7) else { return }
        do {
            _ = try await api.uploadDamagePhoto(itemId: item.id, jpeg: jpeg)
            banner = "Đã gửi ảnh hỏng cho \(item.barcode)"
            Haptics.success()
        } catch {
            banner = "Gửi ảnh thất bại: \(error.localizedDescription)"
            Haptics.error()
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        banner = nil
    }
}

extension UIImage {
    /// Thu nhỏ để ảnh gửi nhanh (ảnh gốc iPhone vài MB).
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
