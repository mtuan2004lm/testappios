import SwiftUI

/// MODULE 1 - Nhập kho. Camera chạy liên tục; quét xong kiện này đưa kiện khác vào ngay.
struct InboundScanView: View {
    let session: ReceivingSession
    @EnvironmentObject var store: AppStore
    @StateObject private var camera = CameraEngine()
    @StateObject private var vm: InboundViewModel
    @State private var showPhoto = false
    @State private var photoTarget: ScannedItem?
    @State private var showHistory = false

    init(session: ReceivingSession) {
        self.session = session
        _vm = StateObject(wrappedValue: InboundViewModel(session: session))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
            Reticle(active: vm.inFlight > 0).allowsHitTesting(false)

            VStack {
                // Bộ đếm
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ĐÃ QUÉT").font(.caption2.bold()).opacity(0.7)
                        Text("\(vm.scanned) / \(vm.total)").font(.system(size: 34, weight: .heavy, design: .monospaced))
                    }
                    Spacer()
                    if vm.inFlight > 0 { ProgressView().tint(.white) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.navy.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                if let b = vm.banner {
                    Text(b).font(.footnote.bold()).padding(8).background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()

                if let n = vm.notice {
                    NoticeCard(notice: n) { n in Task { await vm.demoteToNonBusiness(n) } }
                } else {
                    Text(vm.scanned == 0 ? "Đưa mã vạch vào khung" : "Sẵn sàng · quét kiện tiếp theo")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.5), in: Capsule())
                }

                // Nút chức năng
                HStack(spacing: 14) {
                    roundButton(camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") { camera.toggleTorch() }
                    // Chỉ dùng được sau khi đã quét ít nhất một kiện; ảnh gắn vào kiện vừa quét
                    Button {
                        photoTarget = vm.lastItem
                        camera.stop()            // nhả camera trước khi mở màn chụp ảnh
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
            .padding(.top, 8)

            if camera.authorized == false { PermissionDenied() }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            vm.api = store.api
            camera.ocrEnabled = false
            camera.onBarcodes = { vm.handle($0) }
            camera.start()
            UIApplication.shared.isIdleTimerDisabled = true     // giữ màn hình luôn sáng
        }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(isPresented: $showPhoto, onDismiss: { camera.start() }) {
            PhotoPicker(onImage: { img in
                showPhoto = false
                if let item = photoTarget { Task { await vm.uploadDamagePhoto(img, for: item) } }
            }, onCancel: { showPhoto = false })
            .ignoresSafeArea()
            .onAppear { camera.stop() }          // nhả camera cho màn chụp ảnh
        }
        .sheet(isPresented: $showHistory) { HistorySheet(logs: vm.logs) }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Color.navy.opacity(0.85), in: Circle())
        }
    }
}

struct HistorySheet: View {
    let logs: [ScanLog]
    var body: some View {
        NavigationStack {
            List(logs) { l in
                HStack {
                    Text(l.barcode).font(.system(.body, design: .monospaced))
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(l.group ?? "—").font(.caption)
                        Text(l.time, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if logs.isEmpty { Text("Chưa quét kiện nào").foregroundStyle(.secondary) } }
            .navigationTitle("Lịch sử quét")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

struct PermissionDenied: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Chưa có quyền dùng camera").font(.headline)
            Text("Vào Cài đặt > Warehouse Scanner > bật Camera.").font(.footnote).multilineTextAlignment(.center)
            Button("Mở Cài đặt") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                .buttonStyle(.borderedProminent)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.navy)
        .foregroundStyle(.white)
    }
}
