import SwiftUI

/// Màn hình quét duy nhất: camera chạy liên tục, mỗi nhãn đưa vào khung một lần là tự lấy
/// mã vạch + mã kho rồi gửi về web. Không có hộp thoại xác nhận nào.
struct AutoScanView: View {
    let session: ReceivingSession
    @EnvironmentObject var store: AppStore
    @StateObject private var camera = CameraEngine()
    @StateObject private var vm: AutoScanViewModel
    @State private var showPhoto = false
    @State private var photoTarget: ScannedItem?
    @State private var showHistory = false

    init(session: ReceivingSession) {
        self.session = session
        _vm = StateObject(wrappedValue: AutoScanViewModel(session: session))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
            Reticle(active: vm.reading).allowsHitTesting(false)

            VStack(spacing: 10) {
                counters
                if vm.reading {
                    ProgressView(value: vm.progress).tint(Color.accent).padding(.horizontal, 24)
                }
                if let b = vm.banner {
                    Text(b).font(.footnote.bold()).padding(8).background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                statusStrip
                buttons
            }
            .padding(.top, 8)

            if camera.authorized == false { PermissionDenied() }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            vm.api = store.api
            vm.matcher = store.matcher
            if store.matcher.isEmpty {                   // chưa có quy tắc -> tải ngay từ web
                Task { await store.refresh(); vm.matcher = store.matcher }
            }
            camera.ocrEnabled = true
            camera.onBarcodes = { vm.handle(barcodes: $0) }
            camera.onTextLines = { vm.handle(lines: $0) }
            camera.start()
            UIApplication.shared.isIdleTimerDisabled = true     // giữ màn hình luôn sáng
        }
        .onDisappear {
            camera.ocrEnabled = false
            camera.stop()
            vm.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(isPresented: $showPhoto, onDismiss: { camera.start() }) {
            PhotoPicker(onImage: { img in
                showPhoto = false
                if let item = photoTarget { Task { await vm.uploadDamagePhoto(img, for: item) } }
            }, onCancel: { showPhoto = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showHistory) { AutoHistorySheet(entries: vm.entries) }
    }

    // MARK: Thành phần giao diện

    private var counters: some View {
        HStack(spacing: 18) {
            counter("ĐÃ GỬI", vm.sent, .okGreen)
            counter("BỎ QUA", vm.skipped, vm.skipped > 0 ? .accent : .white)
            if vm.queued > 0 { counter("CHỜ GỬI", vm.queued, .accent) }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.navy.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func counter(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
            Text("\(value)").font(.system(size: 30, weight: .heavy, design: .monospaced)).foregroundStyle(color)
        }
    }

    /// Dòng trạng thái nhỏ, tự đổi, không cần bấm gì: hiển thị nhãn vừa quét thuộc kho nào.
    private var statusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.statusOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(vm.statusLine).lineLimit(2)
        }
        .font(.title3.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(vm.statusOK ? Color.okGreen : Color.accent, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.15), value: vm.statusLine)
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            roundButton(camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") { camera.toggleTorch() }
            Button {
                photoTarget = vm.lastItem
                camera.stop()                      // nhả camera cho màn chụp ảnh
                showPhoto = true
            } label: {
                Label(vm.lastItem.map { "Báo hỏng · \($0.barcode)" } ?? "Báo hỏng", systemImage: "camera.fill")
                    .font(.subheadline.bold()).lineLimit(1)
                    .padding(.horizontal, 16).frame(height: 48)
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
                .frame(width: 48, height: 48).background(Color.navy.opacity(0.85), in: Circle())
        }
    }
}

// MARK: - Lịch sử

struct AutoHistorySheet: View {
    let entries: [ScanEntry]

    var body: some View {
        NavigationStack {
            List(entries) { e in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(e.status)).foregroundStyle(color(e.status)).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.barcode).font(.system(.body, design: .monospaced).weight(.semibold))
                        Text(e.group.map { "\($0) · \(e.warehouseText ?? "")" } ?? (e.note ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(e.time, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .overlay { if entries.isEmpty { Text("Chưa quét nhãn nào").foregroundStyle(.secondary) } }
            .navigationTitle("Lịch sử quét")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func icon(_ s: ScanEntry.Status) -> String {
        s == .sent ? "checkmark.circle.fill" : (s == .queued ? "clock.fill" : "forward.circle.fill")
    }
    private func color(_ s: ScanEntry.Status) -> Color {
        s == .sent ? .okGreen : (s == .queued ? .accent : .unknownGray)
    }
}

// MARK: - Thành phần dùng chung

/// Khung ngắm ở giữa màn hình camera.
struct Reticle: View {
    var active = false
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(active ? Color.accent : Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [18, 10]))
            .frame(width: 320, height: 200)
            .animation(.easeInOut(duration: 0.2), value: active)
    }
}

struct PermissionDenied: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Chưa có quyền dùng camera").font(.headline)
            Text("Vào Cài đặt > Kho Scanner > bật Camera.").font(.footnote).multilineTextAlignment(.center)
            Button("Mở Cài đặt") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                .buttonStyle(.borderedProminent)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.navy)
        .foregroundStyle(.white)
    }
}
