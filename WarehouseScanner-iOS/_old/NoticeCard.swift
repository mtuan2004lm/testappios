import SwiftUI

/// Thẻ kết quả quét (màu theo loại) + nút chuyển "không kinh doanh" cho hàng kinh doanh.
struct NoticeCard: View {
    let notice: ScanNotice
    var onDemote: ((ScanNotice) -> Void)? = nil

    private var color: Color {
        switch notice.kind {
        case .success: return .okGreen
        case .business: return .accent
        case .unknown: return .unknownGray
        case .duplicate, .error: return .dupRed
        }
    }
    private var icon: String {
        switch notice.kind {
        case .success: return "checkmark.circle.fill"
        case .business: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .duplicate: return "arrow.triangle.2.circlepath"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 30))
            Text(notice.title).font(.title2.weight(.heavy)).multilineTextAlignment(.center)
            Text(notice.barcode).font(.system(.body, design: .monospaced).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
            if let d = notice.detail { Text(d).font(.footnote).multilineTextAlignment(.center).opacity(0.95) }
            if notice.kind == .business, notice.itemId != nil, let onDemote {
                Button { onDemote(notice) } label: {
                    Text("Không đủ điều kiện nhập khẩu → KHÔNG KINH DOANH")
                        .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white, in: Capsule()).foregroundStyle(Color.accent)
                }.padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(color, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Khung ngắm ở giữa màn hình camera.
struct Reticle: View {
    var active = false
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(active ? Color.accent : Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [18, 10]))
            .frame(width: 300, height: 190)
            .animation(.easeInOut(duration: 0.2), value: active)
    }
}
