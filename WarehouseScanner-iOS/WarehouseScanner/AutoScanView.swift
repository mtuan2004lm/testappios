import SwiftUI

/// Màn hình quét duy nhất: đưa nhãn vào khung một lần, app tự lấy mã vạch + mã kho và gửi về web.
/// Chỉ hiển thị nhãn thuộc kho nào; không hỏi xác nhận, nhãn không đọc được thì tự bỏ qua.
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
            Color.black.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)
            Reticle(active: vm.reading, progress: vm.progress).allowsHitTesting(false)

            VStack(spacing: 10) {
                counters
                if vm.queued > 0 {
                    Label("Mất kết nối, đang tự gửi lại (\(vm.queued) nhãn chờ)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accent.opacity(0.9), in: Capsule())
                }
                if let b = vm.banner {
                    Text(b).font(.footnote.bold()).padding(8).background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                resultCard
                buttons
            }
            .padding(.top, 8)

            if camera.authorized == false { PermissionDenied() }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { startScanning() }
        .onDisappear {
            vm.stop()
            camera.ocrEnabled = false
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(isPresented: $showPhoto, onDismiss: { startScanning() }) {
            PhotoPicker(onImage: { img in
                showPhoto = false
                if let item = photoTarget { Task { await vm.uploadDamagePhoto(img, for: item) } }
            }, onCancel: { showPhoto = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showHistory) { HistorySheet(entries: vm.entries) }
    }

    private func startScanning() {
        vm.api = store.api
        vm.matcher = store.matcher
        camera.ocrEnabled = true                 // đọc cả mã vạch lẫn chữ mã kho trên cùng khung hình
        camera.onBarcodes = { codes in Task { @MainActor in vm.handle(barcodes: codes) } }
        camera.onTextLines = { lines in Task { @MainActor in vm.handle(lines: lines) } }
        camera.start()
        UIApplication.shared.isIdleTimerDisabled = true      // giữ màn hình luôn sáng
    }

    // MARK: Thành phần giao diện

    private var counters: some View {
        HStack(spacing: 0) {
            counter("ĐÃ GỬI", vm.sent, .okGreen)
            Divider().frame(height: 36).overlay(Color.white.opacity(0.2))
            counter("BỎ QUA", vm.skipped, .unknownGray)
        }
        .padding(.vertical, 10)
        .background(Color.navy.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func counter(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
            Text("\(value)").font(.system(size: 32, weight: .heavy, design: .monospaced)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var resultCard: some View {
        if vm.reading {
            card(bg: Color.navy.opacity(0.92)) {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Đang đọc nhãn…").font(.headline)
                }
            }
        } else if let r = vm.last {
            if let group = r.group {
                // Thành công: chỉ hiển thị nhãn thuộc kho nào
                card(bg: Color.okGreen) {
                    VStack(spacing: 4) {
                        Text("KHO").font(.caption.bold()).opacity(0.85)
                        Text(group).font(.system(size: 34, weight: .heavy)).minimumScaleFactor(0.6).lineLimit(1)
                        if let t = r.warehouseText { Text(t).font(.system(.title3, design: .monospaced).weight(.semibold)) }
                        Text(r.barcode).font(.system(.footnote, design: .monospaced)).opacity(0.85)
                    }
                }
            } else {
                // Bỏ qua: hiện ngắn gọn, không cần bấm gì
                card(bg: Color.unknownGray) {
                    VStack(spacing: 2) {
                        Text("BỎ QUA").font(.headline.weight(.heavy))
                        Text(r.barcode).font(.system(.footnote, design: .monospaced))
                        if let m = r.message { Text(m).font(.footnote).opacity(0.9) }
                    }
                }
            }
        } else {
            Text("Đưa nhãn vào khung: thấy cả mã vạch và dòng mã kho")
                .font(.subheadline.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.5), in: Capsule())
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
                camera.stop()                    // nhả camera trước khi mở màn chụp ảnh
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
                .frame(width: 48, height: 48).background(Color.navy.opacity(0.88), in: Circle())
        }
    }
}
