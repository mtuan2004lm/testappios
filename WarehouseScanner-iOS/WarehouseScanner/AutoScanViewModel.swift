import SwiftUI
import AudioToolbox

/// Một dòng trong lịch sử quét.
struct ScanEntry: Identifiable {
    enum Status { case sent, noWarehouseCode, noBarcode, duplicate, rejected }
    let id = UUID()
    let barcode: String
    var warehouseText: String?
    var group: String?
    var status: Status
    var note: String?
    let time = Date()
}

/// Kết quả hiển thị lớn trên màn hình: nhãn này thuộc kho / nhóm khách hàng nào.
struct LastResult: Equatable {
    let barcode: String
    let group: String?          // kho / nhóm khách hàng (nil nếu bỏ qua)
    let warehouseText: String?  // mã kho đọc được trên nhãn
    let message: String?
    var businessType: String? = nil   // KINH_DOANH | KHONG_KINH_DOANH (từ server)
    var duplicate: Bool = false // true: nhãn đã quét trước đó trong phiên -> MÃ TRÙNG
    var failed: Bool = false    // true: đọc được mã kho nhưng không đọc được mã vạch -> FAIL
    var unknown: Bool = false   // true: mã không có trong Danh sách mặt hàng -> "Không xác định"
}

/// QUÉT TỰ ĐỘNG: mỗi nhãn chỉ cần đưa vào khung một lần.
/// App lấy cùng lúc mã vạch + dòng mã kho (OCR) trong cùng một "cửa sổ" ~3,5 giây rồi tự gửi về web.
/// Nhãn nào không đọc đủ (thiếu mã kho) thì bỏ qua, không hỏi gì, không chặn quét nhãn tiếp theo.
/// App không phân loại kinh doanh / không kinh doanh: chỉ hiện nhãn thuộc kho nào.
@MainActor
final class AutoScanViewModel: ObservableObject {
    @Published var sent = 0
    @Published var failed = 0
    @Published var skipped = 0
    @Published var queued = 0                 // đang chờ gửi lại do mất mạng
    @Published var reading = false
    @Published var progress: Double = 0       // 0...1 của cửa sổ đọc
    @Published var entries: [ScanEntry] = []
    @Published var last: LastResult?
    @Published var lastItem: ScannedItem?     // kiện gửi thành công gần nhất (để gắn ảnh hỏng nếu cần)
    @Published var banner: String?

    let session: ReceivingSession
    var api: APIClient?
    var matcher = RuleMatcher(rules: [])

    /// Thời gian tối đa gom đủ barcode + mã kho cho một nhãn (mục tiêu ~2 giây).
    let window: TimeInterval = 2.0

    private struct Pending {
        var barcode: String?
        var extras: [String] = []            // các mã vạch khác cùng đọc được trên tem (tối đa 3 mã tracking / tem)
        var warehouse: (text: String, group: String)?
        let start: Date
    }
    private var pending: Pending?
    private var recentMatch: (text: String, group: String, at: Date)?
    private var done = Set<String>()                      // mã đã gửi (hoặc đang gửi) -> không gửi lại
    private var skippedAt: [String: Date] = [:]           // mã đã bị bỏ qua, để không đếm lặp
    private var cooldown: [String: Date] = [:]
    private var lastSeen: [String: Date] = [:]           // lần cuối thấy mỗi mã vạch (để phân biệt "vẫn nằm trong khung" với "quét lại")
    private var lastDupAt: [String: Date] = [:]          // lần cuối báo MÃ TRÙNG cho mã này
    private var suppressTextUntil = Date.distantPast     // nhãn đã gửi vẫn đang trong khung -> không coi chữ mã kho là nhãn mới
    private var failCooldown: [String: Date] = [:]        // mã kho đã báo FAIL -> không báo lặp khi nhãn vẫn nằm trong khung
    private var retryList: [(code: String, text: String, group: String)] = []
    private var timerTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    init(session: ReceivingSession) { self.session = session }

    func stop() {
        timerTask?.cancel()
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: Đầu vào từ camera

    func handle(barcodes: [String]) {
        let now = Date()
        for raw in barcodes {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            let prevSeen = lastSeen[code]
            lastSeen[code] = now
            if done.contains(code) {
                // Nhãn đã gửi rồi. Nếu nó vẫn nằm trong khung thì im lặng; nếu đã rời khung rồi quét lại -> MÃ TRÙNG (không phải FAIL)
                suppressTextUntil = now.addingTimeInterval(2)
                if pending != nil, pending?.barcode == nil { clearPending() }      // chữ mã kho của nhãn này, không phải nhãn mới
                if let p = prevSeen, now.timeIntervalSince(p) > 1.5,
                   lastDupAt[code].map({ now.timeIntervalSince($0) > 4 }) ?? true {
                    lastDupAt[code] = now
                    Task { await send(code: code, text: code, group: "") }          // server trả 409 -> hiện MÃ TRÙNG, web tăng bộ đếm
                }
                continue
            }
            if let f = failCooldown[code], now.timeIntervalSince(f) < 8 { continue }   // vừa báo FAIL, đừng báo lặp
            if let t = cooldown[code], now.timeIntervalSince(t) < 1.5 { continue }

            if pending == nil {
                begin(Pending(barcode: code, warehouse: nil, start: now))
            } else if pending?.barcode == nil {
                pending?.barcode = code
            } else if pending?.barcode != code {
                // Mã khác trong cùng khung hình = mã tracking khác trên cùng tem: gom lại, chỉ cần 1 mã có trong danh sách là nhận
                if let p = pending, !p.extras.contains(code), p.extras.count < 4,
                   barcodes.contains(p.barcode ?? "") { pending?.extras.append(code) }
                continue
            }
            // Các mã khác đang nằm cùng khung hình với mã này
            if var p = pending, p.barcode == code {
                for other in barcodes {
                    let o = other.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !o.isEmpty, o != code, !done.contains(o), !p.extras.contains(o), p.extras.count < 4 { p.extras.append(o) }
                }
                pending = p
            }
            // Mã kho có thể đã đọc được vài khung hình trước khi thấy mã vạch
            if pending?.warehouse == nil, let r = recentMatch, now.timeIntervalSince(r.at) < 1.5 {
                pending?.warehouse = (text: r.text, group: r.group)
            }
            tryComplete()
            return
        }
    }

    func handle(lines: [String]) {
        guard let hit = matcher.firstMatch(inLines: lines) else { return }
        let now = Date()
        if now < suppressTextUntil { return }                                      // nhãn đã gửi vẫn trong khung
        if let t = failCooldown[hit.text], now.timeIntervalSince(t) < 8 { return }   // nhãn vừa báo FAIL, đừng báo lặp
        let m = (text: hit.text, group: hit.rule.customerGroup)
        recentMatch = (text: m.text, group: m.group, at: now)
        if pending == nil {
            begin(Pending(barcode: nil, warehouse: m, start: now))
        } else if pending?.warehouse == nil {
            pending?.warehouse = m
        }
        tryComplete()
    }

    // MARK: Cửa sổ đọc một nhãn

    private func begin(_ p: Pending) {
        pending = p
        reading = true
        progress = 0
        timerTask?.cancel()
        let start = p.start
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.progress = min(elapsed / self.window, 1)
                if elapsed >= self.window { self.expire(); return }
            }
        }
    }

    private func clearPending() {
        timerTask?.cancel()
        pending = nil
        reading = false
        progress = 0
        recentMatch = nil
    }

    private func tryComplete() {
        guard let p = pending, let code = p.barcode, let w = p.warehouse else { return }
        clearPending()
        submit(code: code, text: w.text, group: w.group, extras: p.extras)
    }

    /// Hết thời gian mà vẫn thiếu một trong hai -> bỏ qua, không hỏi gì.
    private func expire() {
        let p = pending
        clearPending()
        // Đọc được mã kho nhưng không có mã vạch -> FAIL (báo lên web, không tạo kiện)
        if p?.barcode == nil, let w = p?.warehouse {
            reportFail(text: w.text, group: w.group)
            return
        }
        guard let code = p?.barcode, p?.warehouse == nil else { return }
        cooldown[code] = Date()
        let now = Date()
        if let t = skippedAt[code], now.timeIntervalSince(t) < 60 { return }   // đã đếm rồi
        skippedAt[code] = now
        skipped += 1
        entries.insert(ScanEntry(barcode: code, status: .noWarehouseCode, note: "Không đọc được mã kho"), at: 0)
        last = LastResult(barcode: code, group: nil, warehouseText: nil, message: "Không đọc được mã kho")
    }

    private func reportFail(text: String, group: String) {
        failCooldown[text] = Date()
        failed += 1
        entries.insert(ScanEntry(barcode: "—", warehouseText: text, group: group, status: .noBarcode, note: "Không đọc được mã vạch"), at: 0)
        last = LastResult(barcode: "", group: group, warehouseText: text, message: "Không đọc được mã vạch", failed: true)
        Haptics.warning()
        AudioServicesPlaySystemSound(1053)
        Task { try? await api?.scanFail(sessionId: session.id, detectedText: text) }   // báo FAIL lên web (nếu mất mạng thì bỏ qua)
    }

    // MARK: Gửi về web

    private func submit(code: String, text: String, group: String, extras: [String] = []) {
        done.insert(code)                      // chặn gửi lặp ngay lập tức
        cooldown[code] = Date()
        for x in extras { done.insert(x); cooldown[x] = Date() }
        Task { await send(code: code, text: text, group: group, extras: extras) }
    }

    private func send(code: String, text: String, group: String, extras: [String] = []) async {
        guard let api else { return }
        do {
            let data = try await api.scan(sessionId: session.id, barcode: code, detectedText: text, altBarcodes: extras)
            if skippedAt[code] != nil { skippedAt[code] = nil; skipped = max(skipped - 1, 0) }   // trước đó bỏ qua, giờ đã đọc được
            sent += 1
            lastItem = data.item
            let g = data.item.customerGroup ?? group
            let shown = data.item.barcode   // mã trên tem đã khớp danh sách (có thể là một trong các mã khác)
            entries.insert(ScanEntry(barcode: shown, warehouseText: text, group: g, status: .sent), at: 0)
            last = LastResult(barcode: shown, group: g, warehouseText: data.item.detectedWarehouseCode ?? text, message: nil, businessType: data.item.businessType, unknown: data.item.exceptionStatus == "UNKNOWN")
            Haptics.success()
            AudioServicesPlaySystemSound(1057)
        } catch let e as APIError {
            if e.isDuplicate {
                skipped += 1
                entries.insert(ScanEntry(barcode: code, warehouseText: text == code ? nil : text, status: .duplicate, note: "Đã quét trước đó"), at: 0)
                last = LastResult(barcode: code, group: nil, warehouseText: nil, message: "Mã đã quét trong phiên", duplicate: true)
                Haptics.warning()
                AudioServicesPlaySystemSound(1053)
            } else if e.code == "TRACKING_NOT_FOUND" {
                // Không mã nào trên tem có trong Danh sách mặt hàng: web ghi FAIL, không tính là đã quét
                done.remove(code)
                for x in extras { done.remove(x); failCooldown[x] = Date() }
                failCooldown[code] = Date()
                failed += 1
                entries.insert(ScanEntry(barcode: code, warehouseText: text, group: group, status: .rejected, note: "Không có trong danh sách mặt hàng"), at: 0)
                last = LastResult(barcode: code, group: group, warehouseText: text, message: "Mã không có trong danh sách mặt hàng", failed: true)
                Haptics.warning()
                AudioServicesPlaySystemSound(1053)
            } else if e.isNetwork {
                enqueue(code: code, text: text, group: group)
            } else {
                done.remove(code)
                skipped += 1
                entries.insert(ScanEntry(barcode: code, warehouseText: text, status: .rejected, note: e.message), at: 0)
                last = LastResult(barcode: code, group: nil, warehouseText: text, message: e.message)
            }
        } catch {
            enqueue(code: code, text: text, group: group)
        }
    }

    /// Mất mạng: giữ lại và tự gửi lại mỗi 4 giây, không làm mất kiện nào.
    private func enqueue(code: String, text: String, group: String) {
        retryList.append((code: code, text: text, group: group))
        queued = retryList.count
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self else { return }
                if self.retryList.isEmpty { self.queued = 0; self.retryTask = nil; return }
                let batch = self.retryList
                self.retryList = []
                for item in batch { await self.send(code: item.code, text: item.text, group: item.group) }
                self.queued = self.retryList.count
            }
        }
    }

    // MARK: Ảnh hàng hỏng (tuỳ chọn, gắn vào kiện vừa gửi)

    func uploadDamagePhoto(_ image: UIImage, for item: ScannedItem) async {
        guard let api, let jpeg = image.resized(maxSide: 1600).jpegData(compressionQuality: 0.7) else { return }
        do {
            _ = try await api.uploadDamagePhoto(itemId: item.id, jpeg: jpeg)
            banner = "Đã gửi ảnh hỏng cho \(item.barcode)"
        } catch {
            banner = "Gửi ảnh thất bại: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        banner = nil
    }
}
