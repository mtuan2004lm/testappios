import SwiftUI
import AudioToolbox

/// Một dòng trong lịch sử quét.
struct ScanEntry: Identifiable {
    enum Status { case sent, queued, noWarehouseCode, duplicate, rejected }
    let id = UUID()
    let barcode: String
    var warehouseText: String?
    var group: String?
    var status: Status
    var note: String?
    let time = Date()
}

/// QUÉT TỰ ĐỘNG: mỗi nhãn chỉ cần đưa vào khung một lần.
/// App lấy cùng lúc mã vạch + dòng mã kho (OCR) trong cùng một "cửa sổ" ~3,5 giây rồi tự gửi về web.
/// Nhãn nào không đọc đủ (thiếu mã kho) thì bỏ qua, không hỏi gì, không chặn quét nhãn tiếp theo.
@MainActor
final class AutoScanViewModel: ObservableObject {
    @Published var sent = 0
    @Published var skipped = 0
    @Published var queued = 0                 // đang chờ gửi lại do mất mạng
    @Published var reading = false
    @Published var progress: Double = 0       // 0...1 của cửa sổ đọc
    @Published var statusLine = "Sẵn sàng – đưa nhãn vào khung"
    @Published var statusOK = true
    @Published var entries: [ScanEntry] = []
    @Published var lastItem: ScannedItem?     // kiện gửi thành công gần nhất (để gắn ảnh hỏng nếu cần)
    @Published var banner: String?

    let session: ReceivingSession
    var api: APIClient?
    var matcher = RuleMatcher(rules: [])

    /// Thời gian tối đa gom đủ barcode + mã kho cho một nhãn (yêu cầu 3-5 giây).
    let window: TimeInterval = 3.5

    private struct Pending {
        var barcode: String?
        var warehouse: (text: String, group: String)?
        let start: Date
    }
    private var pending: Pending?
    private var recentMatch: (text: String, group: String, at: Date)?
    private var done = Set<String>()                      // mã đã gửi (hoặc đang gửi) -> không gửi lại
    private var skippedAt: [String: Date] = [:]           // mã đã bị bỏ qua, để không đếm lặp
    private var cooldown: [String: Date] = [:]
    private var retryList: [(code: String, text: String, group: String)] = []
    private var timerTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    init(session: ReceivingSession) { self.session = session }

    func stop() {
        timerTask?.cancel(); retryTask?.cancel(); retryTask = nil
    }

    // MARK: Đầu vào từ camera

    func handle(barcodes: [String]) {
        let now = Date()
        for raw in barcodes {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, !done.contains(code) else { continue }
            if let t = cooldown[code], now.timeIntervalSince(t) < 2 { continue }

            if pending == nil {
                begin(Pending(barcode: code, warehouse: nil, start: now))
            } else if pending?.barcode == nil {
                pending?.barcode = code
            } else if pending?.barcode != code {
                continue                                    // đang xử lý một nhãn khác
            }
            // Mã kho có thể đã đọc được vài khung hình trước khi thấy mã vạch
            if pending?.warehouse == nil, let r = recentMatch, now.timeIntervalSince(r.at) < 2.5 {
                pending?.warehouse = (r.text, r.group)
            }
            tryComplete()
            return
        }
    }

    func handle(lines: [String]) {
        guard let hit = matcher.firstMatch(inLines: lines) else { return }
        let now = Date()
        let m = (text: hit.text, group: hit.rule.customerGroup)
        recentMatch = (m.text, m.group, now)
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
        statusLine = "Đang đọc nhãn…"
        statusOK = true
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(p.start)
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
        submit(code: code, text: w.text, group: w.group)
    }

    /// Hết thời gian mà vẫn thiếu một trong hai -> bỏ qua.
    private func expire() {
        let p = pending
        clearPending()
        guard let code = p?.barcode, p?.warehouse == nil else {
            statusLine = "Sẵn sàng – đưa nhãn vào khung"
            return          // chỉ thấy chữ mà không có mã vạch: coi như nhiễu, không đếm
        }
        cooldown[code] = Date()
        let now = Date()
        if let t = skippedAt[code], now.timeIntervalSince(t) < 60 { return }   // đã đếm rồi
        skippedAt[code] = now
        skipped += 1
        entries.insert(ScanEntry(barcode: code, status: .noWarehouseCode, note: "Không đọc được mã kho"), at: 0)
        statusLine = "Bỏ qua \(code): không đọc được mã kho"
        statusOK = false
    }

    // MARK: Gửi về web

    private func submit(code: String, text: String, group: String) {
        done.insert(code)                      // chặn gửi lặp ngay lập tức
        cooldown[code] = Date()
        Task { await send(code: code, text: text, group: group) }
    }

    private func send(code: String, text: String, group: String) async {
        guard let api else { return }
        do {
            let data = try await api.scan(sessionId: session.id, barcode: code, detectedText: text)
            if skippedAt[code] != nil { skippedAt[code] = nil; skipped = max(skipped - 1, 0) }   // trước đó bỏ qua, giờ đã đọc được
            sent += 1
            lastItem = data.item
            let g = data.item.customerGroup ?? group
            entries.insert(ScanEntry(barcode: code, warehouseText: text, group: g, status: .sent), at: 0)
            statusLine = "\(g) · \(text)"          // chỉ cần biết nhãn thuộc kho nào
            statusOK = true
            Haptics.success()
            AudioServicesPlaySystemSound(1057)
        } catch let e as APIError {
            if e.isDuplicate {
                skipped += 1
                entries.insert(ScanEntry(barcode: code, warehouseText: text, status: .duplicate, note: "Đã quét trước đó"), at: 0)
                statusLine = "Bỏ qua \(code): mã đã quét trong phiên"
                statusOK = false
            } else if e.isNetwork {
                enqueue(code: code, text: text, group: group)
            } else {
                done.remove(code)
                skipped += 1
                entries.insert(ScanEntry(barcode: code, warehouseText: text, status: .rejected, note: e.message), at: 0)
                statusLine = "Bỏ qua \(code): \(e.message)"
                statusOK = false
            }
        } catch {
            enqueue(code: code, text: text, group: group)
        }
    }

    /// Mất mạng: giữ lại và tự gửi lại mỗi 4 giây, không làm mất kiện nào.
    private func enqueue(code: String, text: String, group: String) {
        retryList.append((code, text, group))
        queued = retryList.count
        statusLine = "Mất kết nối, đang tự gửi lại (\(queued) kiện chờ)"
        statusOK = false
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
