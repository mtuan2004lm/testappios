import SwiftUI

/// MODULE 2 - Nhận diện mã kho: tự đọc chữ mã kho trên nhãn (OCR) rồi khớp quy tắc, thay cho việc đọc bằng mắt và dò tay.
struct ClassifyScanView: View {
    let session: ReceivingSession
    @EnvironmentObject var store: AppStore
    @StateObject private var camera = CameraEngine()
    @StateObject private var vm: ClassifyViewModel

    init(session: ReceivingSession) {
        self.session = session
        _vm = StateObject(wrappedValue: ClassifyViewModel(session: session))
    }

    private var reading: Bool { if case .reading = vm.phase { return true } else { return false } }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
            Reticle(active: reading).allowsHitTesting(false)

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ĐÃ NHẬN DIỆN").font(.caption2.bold()).opacity(0.7)
                        Text("\(vm.doneCount)").font(.system(size: 34, weight: .heavy, design: .monospaced))
                    }
                    Spacer()
                    statusView
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.navy.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                // Mã kho đang đọc thấy theo thời gian thực
                if let m = vm.liveMatch {
                    Label("\(m.text)  →  \(m.group)", systemImage: "text.viewfinder")
                        .font(.footnote.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accent.opacity(0.9), in: Capsule())
                }
                Spacer()

                if let n = vm.notice {
                    NoticeCard(notice: n) { n in Task { await vm.demoteToNonBusiness(n) } }
                } else {
                    Text(hint).font(.subheadline.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.5), in: Capsule())
                }

                Button { camera.toggleTorch() } label: {
                    Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill").font(.title3).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(Color.navy.opacity(0.85), in: Circle())
                }
                .padding(.bottom, 16)
            }
            .padding(.top, 8)

            if camera.authorized == false { PermissionDenied() }
        }
        .navigationTitle("Nhận diện mã kho")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            vm.api = store.api
            vm.matcher = store.matcher
            camera.ocrEnabled = true
            camera.onBarcodes = { vm.handle(barcodes: $0) }
            camera.onTextLines = { vm.handle(lines: $0) }
            camera.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            camera.ocrEnabled = false
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder private var statusView: some View {
        switch vm.phase {
        case .idle: Text("SẴN SÀNG").font(.caption.bold()).foregroundStyle(Color.okGreen)
        case .reading(let code):
            VStack(alignment: .trailing, spacing: 2) {
                Text("ĐANG ĐỌC · \(String(format: "%.1f", vm.secondsLeft))s").font(.caption.bold()).foregroundStyle(Color.accent)
                Text(code).font(.caption2.monospaced()).lineLimit(1)
            }
        case .sending: ProgressView().tint(.white)
        }
    }

    private var hint: String {
        store.matcher.isEmpty ? "Chưa có quy tắc mã kho. Vào Cài đặt để tải từ server." : "Đưa nhãn vào khung: thấy cả mã vạch và dòng mã kho"
    }
}
