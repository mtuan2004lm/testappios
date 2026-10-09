import SwiftUI
import AudioToolbox

/// Một dòng trong lịch sử quét.
struct ScanEntry: Identifiable {
    enum Status { case sent, noWarehouseCode, noBarcode, duplicate, rejected, tracked, noName }
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
    var track: Int? = nil       // 1...3: tracking chưa có thông tin ("ting"), chờ tracking tiếp theo hoặc END CODE
    var noName: Bool = false    // true: quét END CODE -> kiện NO NAME (tracking đầu làm tracking gốc)
    var endBlocked: Bool = false // true: đã đủ 3 tracking không có thông tin mà vẫn quét tiếp -> bị chặn
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
    @Published var pendingTracks = 0          // số tracking chưa có thông tin của tem đang quét (0...3)
    @Published var endRequired = false        // true: bắt buộc quét QR END CODE (pop-up chặn)

    let session: ReceivingSession
    var api: APIClient?
    var matcher = RuleMatcher(rules: [])

    /// Thời gian tối đa gom đủ barcode + mã kho cho một nhãn (mục tiêu ~2 giây).
    let window: TimeInterval = 1.5

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
    private var endCodeAt: Date?
    private var lastLabel: (text: String, group: String)?     // mã kho của tem đang quét (dùng cho các tracking tiếp theo của cùng tem)
    private var timerTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    init(session: ReceivingSession) { self.session = session }

    func stop() {
        timerTask?.cancel()
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: Đầu vào từ camera

    /// QR "END CODE" (mã cố định dùng chung): kết thúc tem khi cả 3 tracking đều không có thông tin.
    static func isEndCode(_ s: String) -> Bool {
        let n = s.uppercased().filter { !" _-".contains($0) }
        return n == "ENDCODE"
    }

    func handle(barcodes: [String]) {
        let now = Date()
        for raw in barcodes {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            if Self.isEndCode(code) {
                if let t = endCodeAt, now.timeIntervalSince(t) < 3 { continue }
                endCodeAt = now
                clearPending()
                Task { await send(code: "END CODE", text: lastLabel?.text ?? "", group: "") }   // không cần đọc mã kho
                continue
            }
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
                    if !o.isEmpty, o != code, !Self.isEndCode(o), !done.contains(o), !p.extras.contains(o), p.extras.count < 4 { p.extras.append(o) }
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
        lastLabel = m
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
        // Có mã vạch nhưng chưa đọc được mã kho: vẫn gửi tracking (không bỏ sót ting / yes); mã kho lấy của tem đang quét nếu có
        guard let p, let code = p.barcode, p.warehouse == nil else { return }
        let text = pendingTracks > 0 ? (lastLabel?.text ?? "") : ""
        submit(code: code, text: text, group: lastLabel?.group ?? "", extras: p.extras)
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

    /// Gửi MỘT tracking. `extras` = các mã khác cùng thấy trên tem: nếu tracking này "ting" (chưa có thông tin) thì gửi tiếp
    /// mã kế tiếp theo thứ tự (tracking 2, 3); nếu đã "yes" hoặc NO NAME thì bỏ qua các mã còn lại (cùng một kiện).
    private func send(code: String, text: String, group: String, extras: [String] = []) async {
        guard let api else { return }
        do {
            let data = try await api.scan(sessionId: session.id, barcode: code, detectedText: text)
            if skippedAt[code] != nil { skippedAt[code] = nil; skipped = max(skipped - 1, 0) }
            let status = data.status ?? "SUCCESS"
            if status == "TRACK" {
                // Tracking chưa có thông tin: "ting", ghi lại, chờ tracking tiếp theo hoặc END CODE
                let seq = data.seq ?? (pendingTracks + 1)
                pendingTracks = seq
                let needEnd = data.needEndCode == true
                if needEnd { endRequired = true }
                let msg = needEnd ? "Đủ 3 tracking — quét QR END CODE" : "Tracking \(seq)/3 chưa có thông tin"
                entries.insert(ScanEntry(barcode: code, warehouseText: (text.isEmpty || text == code) ? nil : text, status: .tracked, note: msg), at: 0)
                last = LastResult(barcode: code, group: nil, warehouseText: nil, message: msg, track: seq)
                Haptics.warning()
                AudioServicesPlaySystemSound(1103)   // "ting"
                if let next = extras.first { await send(code: next, text: text, group: group, extras: Array(extras.dropFirst())) }
                return
            }
            guard let item = data.item else { return }
            let noName = status == "NO_NAME"
            pendingTracks = 0
            endRequired = false
            sent += 1
            lastItem = item
            let g = item.customerGroup ?? group
            let shown = item.barcode
            entries.insert(ScanEntry(barcode: shown, warehouseText: text, group: g, status: noName ? .noName : .sent, note: noName ? "NO NAME" : nil), at: 0)
            last = LastResult(barcode: shown, group: g, warehouseText: item.detectedWarehouseCode ?? (text.isEmpty ? nil : text), message: nil, businessType: item.businessType, unknown: item.exceptionStatus == "UNKNOWN", noName: noName)
            if noName { Haptics.warning(); AudioServicesPlaySystemSound(1103) }
            else { Haptics.success(); AudioServicesPlaySystemSound(1057) }   // "yes"
        } catch let e as APIError {
            if e.isEndCodeRequired {
                // Đã đủ 3 tracking không có thông tin mà quét tiếp -> pop-up chặn, bắt buộc quét QR END CODE
                done.remove(code)
                for x in extras { done.remove(x) }
                endRequired = true
                pendingTracks = 3
                last = LastResult(barcode: code, group: nil, warehouseText: nil, message: "Bắt buộc quét QR END CODE", endBlocked: true)
                Haptics.warning()
                AudioServicesPlaySystemSound(1053)
                return
            }
            if e.code == "NO_PENDING_TRACKS" {
                banner = "Chưa có tracking nào đang chờ — không cần END CODE"
                endRequired = false; pendingTracks = 0       // server không còn tem nào đang chờ -> gỡ pop-up chặn
                Task { try? await Task.sleep(nanoseconds: 3_000_000_000); banner = nil }
                return
            }
            if e.isDuplicate {
                skipped += 1
                entries.insert(ScanEntry(barcode: code, warehouseText: text == code ? nil : text, status: .duplicate, note: "Đã quét trước đó"), at: 0)
                last = LastResult(barcode: code, group: nil, warehouseText: nil, message: "Mã đã quét trong phiên", duplicate: true)
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

    // MARK: Ảnh label (gắn vào kiện vừa gửi; nhân viên VN kiểm duyệt trên web)

    func uploadLabelPhoto(_ image: UIImage, for item: ScannedItem) async {
        guard let api, let jpeg = image.resized(maxSide: 1600).jpegData(compressionQuality: 0.7) else { return }
        do {
            _ = try await api.uploadLabelPhoto(itemId: item.id, jpeg: jpeg)
            banner = "Đã gửi ảnh label cho \(item.barcode)"
        } catch {
            banner = "Gửi ảnh label thất bại: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        banner = nil
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
