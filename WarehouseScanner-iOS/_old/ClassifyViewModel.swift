import SwiftUI
import AudioToolbox

/// MODULE 2 - Nhận diện mã kho: với mỗi kiện, đọc mã vạch + đọc chữ mã kho in trên nhãn (OCR),
/// khớp với quy tắc regex của web rồi gửi để gán nhóm khách hàng. Tối đa `window` giây cho mỗi kiện.
@MainActor
final class ClassifyViewModel: ObservableObject {
    enum Phase: Equatable { case idle, reading(String), sending(String) }

    struct LiveMatch: Equatable { let text: String; let group: String }

    @Published var phase: Phase = .idle
    @Published var notice: ScanNotice?
    @Published var liveMatch: LiveMatch?        // mã kho đang đọc thấy (hiển thị realtime cho người dùng)
    @Published var secondsLeft: Double = 0
    @Published var doneCount = 0

    let session: ReceivingSession
    var api: APIClient?
    var matcher = RuleMatcher(rules: [])

    /// Thời gian tối đa để tìm mã kho sau khi thấy mã vạch (yêu cầu: xử lý trong 3-5 giây).
    let window: TimeInterval = 4

    private var lastMatch: (text: String, rule: WarehouseRule, at: Date)?
    private var cooldown: [String: Date] = [:]
    private var windowTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(session: ReceivingSession) { self.session = session }

    // MARK: Đầu vào từ camera

    func handle(barcodes codes: [String]) {
        guard phase == .idle else { return }
        let now = Date()
        var picked: String?
        for raw in codes {
            let c = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.isEmpty { continue }
            if let t = cooldown[c], now.timeIntervalSince(t) <= 3 { continue }   // vừa xử lý xong, bỏ qua
            picked = c
            break
        }
        guard let code = picked else { return }

        Haptics.tick()
        AudioServicesPlaySystemSound(1057)
        // Mã kho có thể đã được đọc trước khi thấy mã vạch (vài khung hình trước) -> dùng luôn
        if let m = lastMatch, now.timeIntervalSince(m.at) < 2.5 {
            phase = .sending(code)
            Task { await finish(code: code, text: m.text, rule: m.rule) }
            return
        }
        phase = .reading(code)
        secondsLeft = window
        windowTask?.cancel()
        windowTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let left = self.window - Date().timeIntervalSince(start)
                self.secondsLeft = max(left, 0)
                if left <= 0 { break }
            }
            if !Task.isCancelled { self.timeout(code: code) }
        }
    }

    func handle(lines: [String]) {
        guard let hit = matcher.firstMatch(inLines: lines) else { return }
        lastMatch = (hit.text, hit.rule, Date())
        liveMatch = LiveMatch(text: hit.text, group: hit.rule.customerGroup)
        if case .reading(let code) = phase {
            windowTask?.cancel()
            Task { await finish(code: code, text: hit.text, rule: hit.rule) }
        }
    }

    // MARK: Kết thúc một kiện

    private func timeout(code: String) {
        guard case .reading(let c) = phase, c == code else { return }
        cooldown[code] = Date()
        phase = .idle
        show(.init(kind: .error, barcode: code, title: "KHÔNG ĐỌC ĐƯỢC MÃ KHO",
                   detail: "Đưa nhãn lại gần hơn, đủ sáng rồi thử lại"))
        Haptics.error()
    }

    private func finish(code: String, text: String, rule: WarehouseRule) async {
        phase = .sending(code)
        defer {
            phase = .idle
            lastMatch = nil
            cooldown[code] = Date()
        }
        guard let api else { return }
        do {
            let res = try await api.classify(sessionId: session.id, barcode: code, detectedText: text)
            if res.matched {
                doneCount += 1
                let isBiz = res.item.businessType == "KINH_DOANH"
                show(.init(kind: isBiz ? .business : .success, barcode: code,
                           title: res.item.customerGroup ?? rule.customerGroup,
                           detail: isBiz ? (res.warning ?? "Hàng kinh doanh") : "Mã kho: \(text)",
                           itemId: res.item.id))
                if isBiz { Haptics.warning() } else { Haptics.success() }
            } else {
                show(.init(kind: .unknown, barcode: code, title: "MÃ KHO KHÔNG KHỚP", detail: text))
                Haptics.warning()
            }
        } catch let e as APIError {
            let detail = e.code == "ITEM_NOT_SCANNED" ? "Kiện chưa quét nhập kho (làm Module 1 trước)" : e.message
            show(.init(kind: .error, barcode: code, title: "ĐỌC ĐƯỢC \(rule.customerGroup.uppercased())", detail: detail))
            Haptics.error()
        } catch {
            show(.init(kind: .error, barcode: code, title: "LỖI", detail: error.localizedDescription))
        }
    }

    /// Hàng kinh doanh không đủ điều kiện nhập khẩu -> chuyển thành không kinh doanh.
    func demoteToNonBusiness(_ n: ScanNotice) async {
        guard let api, let id = n.itemId else { return }
        do {
            _ = try await api.toggleBusinessType(itemId: id)
            show(.init(kind: .success, barcode: n.barcode, title: "ĐÃ CHUYỂN: KHÔNG KINH DOANH", detail: n.barcode))
            Haptics.success()
        } catch { show(.init(kind: .error, barcode: n.barcode, title: "LỖI", detail: error.localizedDescription)) }
    }

    private func show(_ n: ScanNotice) {
        notice = n
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}
