import SwiftUI

/// Màn hình quét duy nhất: đưa nhãn vào khung một lần, app tự lấy mã vạch + mã kho và gửi về web.
/// Chỉ hiển thị nhãn thuộc kho nào; không hỏi xác nhận, nhãn không đọc được thì tự bỏ qua.
struct AutoScanView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    let session: ReceivingSession
    @EnvironmentObject var store: AppStore
    @StateObject private var camera = CameraEngine()
    @StateObject private var vm: AutoScanViewModel
    @State private var showPhoto = false
    @State private var photoTarget: ScannedItem?
    @State private var photoIsLabel = false      // true: ảnh label · false: ảnh báo hỏng
    @State private var showHistory = false
    @Environment(\.dismiss) private var dismiss
    @State private var paused = false              // đã dừng quét (chốt kiện)
    @State private var confirmStop = false
    @State private var confirmClose = false
    @State private var working = false
    @State private var actionError: String?
    @State private var finalCount = 0
    @State private var serverScanned: Int?        // số đã quét theo server (cập nhật ~1 giây như web)

    init(session: ReceivingSession) {
        self.session = session
        _vm = StateObject(wrappedValue: AutoScanViewModel(session: session))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            Color.black.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)

            // Bố cục: [ĐÃ GỬI to] → [thẻ kết quả] → [khung quét co giãn] → [back + BỎ QUA + FAIL] → [nút chức năng]
            // Phần trên/dưới cao cố định, khung quét ăn phần còn lại nên iPhone Pro và Pro Max trông giống nhau.
            VStack(spacing: 12) {
                sentCounter
                resultCard
                    .frame(height: 200, alignment: .top)       // chừa chỗ cố định để khung quét không nhảy mỗi lần quét
                ZStack(alignment: .top) {
                    Reticle(active: vm.reading, progress: vm.progress).allowsHitTesting(false)
                    VStack(spacing: 6) {
                        if vm.queued > 0 {
                            Label(tr("Mất kết nối, đang tự gửi lại ({0} nhãn chờ)", vm.queued), systemImage: "arrow.triangle.2.circlepath")
                                .font(.footnote.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accent.opacity(0.9), in: Capsule())
                        }
                        if vm.photosPending > 0 {
                            Label(tr("{0} ảnh label đang chờ gửi", vm.photosPending), systemImage: "photo.on.rectangle.angled")
                                .font(.footnote.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.black.opacity(0.6), in: Capsule())
                        }
                        if let b = vm.banner {
                            Text(b).font(.footnote.bold()).padding(8).background(.ultraThinMaterial, in: Capsule())
                        }
                        if let h = vm.hint {
                            Text(h).font(.footnote.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.black.opacity(0.65), in: Capsule())
                        }
                    }
                    .padding(.top, 10).padding(.horizontal, 20)
                }
                .frame(maxHeight: .infinity)
                bottomBar
                buttons
            }
            .padding(.top, 8)

            // Đã dừng quét: che camera, chỉ còn Tiếp tục / Kết thúc phiên
            if paused {
                ZStack {
                    Color.black.opacity(0.88).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "pause.circle.fill").font(.system(size: 56)).foregroundStyle(Color.accent)
                        Text(tr("ĐÃ DỪNG QUÉT")).font(.title2.weight(.heavy))
                        Text(tr("Đã chốt {0} kiện", finalCount)).font(.title3.bold()).foregroundStyle(Color.okGreen)
                        if let e = actionError { Text(e).font(.footnote).foregroundStyle(Color.accent).multilineTextAlignment(.center) }
                        Button { resumeScanning() } label: {
                            Text(tr("Tiếp tục quét")).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent).tint(.accent)
                        Button(role: .destructive) { confirmClose = true } label: {
                            Text(tr("Kết thúc phiên")).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        Button(tr("Quay lại danh sách phiên")) { dismiss() }.foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white).padding(24).frame(maxWidth: 380)
                }
            }

            // Pop-up chặn: đủ 3 tracking không có thông tin -> bắt buộc quét QR END CODE rồi mới quét tiếp
            if vm.endRequired {
                ZStack {
                    Color.black.opacity(0.75).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.yellow)
                        Text(tr("BẮT BUỘC QUÉT QR END CODE")).font(.title2.weight(.heavy)).multilineTextAlignment(.center)
                        Text(tr("Tem này đã quét đủ 3 tracking nhưng không có thông tin. Hãy quét mã QR END CODE trước khi quét tem khác."))
                            .font(.subheadline).multilineTextAlignment(.center).opacity(0.9)
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 56)).opacity(0.9)
                    }
                    .foregroundStyle(.white).padding(24)
                    .background(Color.dupRed.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)
                }
                .allowsHitTesting(false)      // camera vẫn quét được QR END CODE phía sau
            }

            if camera.authorized == false { PermissionDenied() }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { startScanning() }
        .task {
            // Đồng bộ số ĐÃ GỬI với server mỗi 1 giây (đơn xoá/thêm trên web hoặc máy khác cũng hiện ngay)
            while !Task.isCancelled {
                await pollServerCount()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: vm.sent) { _ in Task { await pollServerCount() } }
        .onDisappear {
            vm.stop()
            camera.ocrEnabled = false
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(isPresented: $showPhoto, onDismiss: { startScanning() }) {
            PhotoPicker(onImage: { img in
                showPhoto = false
                if let item = photoTarget {
                    Task { if photoIsLabel { await vm.uploadLabelPhoto(img, for: item) } else { await vm.uploadDamagePhoto(img, for: item) } }
                }
            }, onCancel: { showPhoto = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showHistory) { HistorySheet(entries: vm.entries) }
        .alert(tr("Dừng quét và chốt kiện?"), isPresented: $confirmStop) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Dừng quét")) { Task { await stopScanning() } }
        } message: { Text(tr("Chốt số kiện của phiên = số đã quét ({0}).", vm.sent)) }
        .alert(tr("Kết thúc phiên?"), isPresented: $confirmClose) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Kết thúc"), role: .destructive) { Task { await closeSession() } }
        } message: { Text(tr("Sau khi kết thúc sẽ không quét thêm được.")) }
    }

    // MARK: Dừng quét / kết thúc phiên (giống web: "Chốt kiện - END CODE" và "Kết thúc phiên")

    private func stopScanning() async {
        working = true; actionError = nil
        defer { working = false }
        do {
            let s = try await store.api.finalizeSession(id: session.id)
            finalCount = s.totalExpectedPackages
            vm.stop(); camera.ocrEnabled = false; camera.stop()
            paused = true
            Haptics.success()
        } catch {
            vm.banner = error.localizedDescription      // không dừng được thì vẫn tiếp tục quét
            Haptics.error()
        }
    }

    private func pollServerCount() async {
        if let d = try? await store.api.sessionDetail(id: session.id) { serverScanned = d.session.scannedCount }
    }

    private func resumeScanning() { paused = false; actionError = nil; startScanning() }

    private func closeSession() async {
        working = true
        defer { working = false }
        do {
            _ = try await store.api.closeSession(id: session.id)
            Haptics.success()
            dismiss()
        } catch {
            if paused { actionError = error.localizedDescription } else { vm.banner = error.localizedDescription }
            Haptics.error()
        }
    }

    private func startScanning() {
        vm.api = store.api
        vm.matcher = store.matcher
        vm.snapshotProvider = { [camera] in await camera.snapshot() }
        vm.photosPending = PhotoOutbox.count
        if vm.photosPending > 0 { vm.startPhotoFlush() }       // gửi bù ảnh còn sót từ lần quét trước
        camera.ocrEnabled = true                 // đọc cả mã vạch lẫn chữ mã kho trên cùng khung hình
        camera.onBarcodes = { codes in Task { @MainActor in vm.handle(barcodes: codes) } }
        camera.onTextLines = { lines in Task { @MainActor in vm.handle(lines: lines) } }
        camera.start()
        UIApplication.shared.isIdleTimerDisabled = true      // giữ màn hình luôn sáng
    }

    // MARK: Thành phần giao diện

    /// Ô ĐÃ GỬI to ở trên cùng.
    private var sentCounter: some View {
        VStack(spacing: 0) {
            Text(tr("ĐÃ GỬI")).font(.caption.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.7))
            Text("\(serverScanned ?? vm.sent)").font(.system(size: 72, weight: .heavy, design: .monospaced)).foregroundStyle(Color.okGreen)
                .minimumScaleFactor(0.5).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.navy.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// Hàng dưới: nút quay lại + BỎ QUA + FAIL (nhỏ).
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Color.navy.opacity(0.9), in: Circle())
            }
            .accessibilityLabel(tr("Quay lại"))
            Spacer(minLength: 0)
            smallCounter(tr("BỎ QUA"), vm.skipped, .unknownGray)
            smallCounter("FAIL", vm.failed, .dupRed)
            Menu {
                Button { confirmStop = true } label: { Label(tr("Dừng quét (chốt kiện)"), systemImage: "pause.circle") }
                Button(role: .destructive) { confirmClose = true } label: { Label(tr("Kết thúc phiên"), systemImage: "flag.checkered") }
            } label: {
                Image(systemName: "ellipsis").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Color.navy.opacity(0.9), in: Circle())
            }
            .accessibilityLabel(tr("Dừng quét hoặc kết thúc phiên"))
        }
        .padding(.horizontal, 16)
    }

    private func smallCounter(_ title: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.white.opacity(0.75))
            Text("\(value)").font(.system(.body, design: .monospaced).weight(.bold)).foregroundStyle(color)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(Color.navy.opacity(0.9), in: Capsule())
    }

    /// Mã dài không được rớt dòng: một dòng, tự thu nhỏ chữ; quá dài thì cắt phần giữa.
    private func codeText(_ code: String, _ font: Font = .system(.footnote, design: .monospaced)) -> some View {
        Text(shortCode(code)).font(font).lineLimit(1).minimumScaleFactor(0.5).opacity(0.92)
    }

    private func shortCode(_ c: String, max: Int = 40) -> String {
        guard c.count > max else { return c }
        let head = c.prefix(max / 2 - 1), tail = c.suffix(max / 2 - 2)
        return "\(head)…\(tail)"
    }

    @ViewBuilder private var resultCard: some View {
        if vm.reading {
            card(bg: Color.navy.opacity(0.92)) {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(tr("Đang đọc nhãn…")).font(.headline)
                }
            }
        } else if let r = vm.last {
            if let n = r.track {
                // Tracking chưa có thông tin: "ting"
                card(bg: Color.accent) {
                    VStack(spacing: 4) {
                        Text("TING").font(.system(size: 34, weight: .heavy))
                        Text(tr("Tracking {0}/3 chưa có thông tin", n)).font(.subheadline.bold())
                        codeText(r.barcode)
                        if let m = r.message { Text(m).font(.footnote).opacity(0.9).multilineTextAlignment(.center) }
                    }
                }
            } else if r.noName {
                card(bg: Color.purple) {
                    VStack(spacing: 4) {
                        Text("NO NAME").font(.system(size: 34, weight: .heavy))
                        Text(tr("Cả 3 tracking không có thông tin")).font(.subheadline.bold())
                        codeText(r.barcode)
                        Text(tr("Nên chụp ảnh label để nhân viên VN kiểm tra")).font(.footnote).opacity(0.9)
                    }
                }
            } else if r.endBlocked {
                card(bg: Color.dupRed) {
                    VStack(spacing: 4) {
                        Text(tr("QUÉT END CODE")).font(.system(size: 30, weight: .heavy))
                        Text(r.message ?? tr("Bắt buộc quét QR END CODE")).font(.subheadline.bold()).multilineTextAlignment(.center)
                    }
                }
            } else if r.duplicate {
                // Quét lại nhãn đã quét trong phiên: MÃ TRÙNG (không phải FAIL)
                card(bg: Color.accent) {
                    VStack(spacing: 4) {
                        Text(tr("MÃ TRÙNG")).font(.system(size: 34, weight: .heavy))
                        Text(tr("Nhãn này đã quét trong phiên")).font(.subheadline.bold())
                        codeText(r.barcode)
                    }
                }
            } else if r.failed {
                // Không đọc được mã vạch (nhưng đọc được mã kho): FAIL, web cũng hiện FAIL
                card(bg: Color.dupRed) {
                    VStack(spacing: 4) {
                        Text("FAIL").font(.system(size: 34, weight: .heavy))
                        Text(r.message ?? tr("Không đọc được mã vạch")).font(.subheadline.bold()).multilineTextAlignment(.center)
                        if !r.barcode.isEmpty { codeText(r.barcode) }
                        if let g = r.group { Text(tr("KHO {0}", g)).font(.footnote).opacity(0.9) }
                        if let t = r.warehouseText { Text(t).font(.system(.title3, design: .monospaced).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5) }
                    }
                }
            } else if let group = r.group {
                // Thành công: hiện riêng Nhóm KH, Mã kho, Loại hình (web cũng lưu và hiển thị riêng từng cột)
                card(bg: Color.okGreen) {
                    VStack(spacing: 6) {
                        Text("SUCCESS").font(.headline.weight(.heavy))
                        codeText(r.barcode)
                        VStack(spacing: 4) {
                            infoRow(tr("NHÓM KH"), group)
                            infoRow(tr("MÃ KHO"), r.warehouseText ?? "—", mono: true)
                            infoRow(tr("LOẠI HÌNH"), businessLabel(r.businessType))
                        }
                    }
                }
            } else {
                // Bỏ qua: hiện ngắn gọn, không cần bấm gì
                card(bg: Color.unknownGray) {
                    VStack(spacing: 2) {
                        Text(tr("BỎ QUA")).font(.headline.weight(.heavy))
                        codeText(r.barcode)
                        if let m = r.message { Text(m).font(.footnote).opacity(0.9) }
                    }
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption.bold()).opacity(0.85).frame(width: 84, alignment: .leading)
            Text(value).font(mono ? .system(.title3, design: .monospaced).weight(.bold) : .title3.weight(.bold))
                .minimumScaleFactor(0.6).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func businessLabel(_ t: String?) -> String {
        switch t {
        case "KINH_DOANH": return "Kinh doanh"
        case "KHONG_KINH_DOANH": return tr("Không kinh doanh")
        default: return "—"
        }
    }

    private func card<C: View>(bg: Color, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(bg, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(.horizontal, 16)
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            roundButton(camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") { camera.toggleTorch() }
            Button {
                photoTarget = vm.lastItem
                photoIsLabel = true
                camera.stop()                    // nhả camera trước khi mở màn chụp ảnh
                showPhoto = true
            } label: {
                Label(tr("Ảnh label"), systemImage: "doc.viewfinder")
                    .font(.subheadline.bold()).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(vm.lastItem == nil ? Color.gray.opacity(0.6) : Color.navy.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(vm.lastItem == nil)
            Button {
                photoTarget = vm.lastItem
                photoIsLabel = false
                camera.stop()                    // nhả camera trước khi mở màn chụp ảnh
                showPhoto = true
            } label: {
                Label(tr("Hỏng"), systemImage: "camera.fill")
                    .font(.subheadline.bold()).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(vm.lastItem == nil ? Color.gray.opacity(0.6) : Color.dupRed, in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(vm.lastItem == nil)
            roundButton("list.bullet") { showHistory = true }
        }
        .padding(.bottom, 16)
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Color.navy.opacity(0.88), in: Circle())
        }
    }
}
