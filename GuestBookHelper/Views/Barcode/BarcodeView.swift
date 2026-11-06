import SwiftUI
import CoreImage
import UIKit

enum Code128BarcodeGenerator {
    static func image(for message: String) -> UIImage? {
        guard !message.isEmpty,
              let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        filter.setValue(8, forKey: "inputQuietSpace")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct BarcodeView: View {
    @EnvironmentObject private var state: AppState
    let serialNumber: String

    @State private var includesS = true
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    private let pointsPerMillimeter: CGFloat = 3.7795275591
    private var baseWidth: CGFloat { 30 * pointsPerMillimeter }
    private var baseHeight: CGFloat { 10 * pointsPerMillimeter }
    private var maximumWidth: CGFloat { max(baseWidth, UIScreen.main.bounds.width - 32) }
    private var maximumScale: CGFloat { max(1, maximumWidth / baseWidth) }
    private var currentWidth: CGFloat { min(maximumWidth, baseWidth * scale) }
    private var currentHeight: CGFloat { currentWidth / 3 }

    private var item: InventoryItem? {
        state.item(withSerial: serialNumber)
    }

    private var encodedValue: String {
        includesS ? "S\(serialNumber)" : serialNumber
    }

    private var barcodeImage: UIImage? {
        Code128BarcodeGenerator.image(for: encodedValue)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                prefixControl
                barcodeCard
                informationCard
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 34)
        }
        .background(Color.clear)
        .gbInlineTitle("序列号条码")
    }

    private var prefixControl: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    includesS.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: includesS ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17, weight: .semibold))
                    Text("生成带 S 的条码")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(includesS ? "已开启" : "已关闭")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(includesS ? AppTheme.accent : AppTheme.tertiary)
                }
                .foregroundColor(includesS ? AppTheme.accent : AppTheme.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(includesS ? AppTheme.accentSoft : AppTheme.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(includesS ? AppTheme.accent.opacity(0.4) : AppTheme.line.opacity(0.8), lineWidth: 0.8)
                )
            }
            .buttonStyle(PlainButtonStyle())

            Text("S 仅用于生成条码，不会改变实际序列号。")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.tertiary)
                .padding(.horizontal, 3)
        }
    }

    private var barcodeCard: some View {
        VStack(spacing: 10) {
            if let barcodeImage = barcodeImage {
                Image(uiImage: barcodeImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: currentWidth, height: currentHeight)
                    .background(Color.white)
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let proposed = lastScale * value
                                scale = min(max(proposed, 1), maximumScale)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .accessibility(label: Text("Code 128 条码 \(encodedValue)"))

                Text(encodedValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: SFSymbol.available("barcode", fallback: "number"))
                        .font(.system(size: 34, weight: .light))
                    Text("无法生成条码")
                        .font(.system(size: 12))
                }
                .foregroundColor(.black.opacity(0.55))
                .frame(width: max(160, currentWidth), height: max(90, currentHeight + 30))
            }

            HStack(spacing: 5) {
                Image(systemName: SFSymbol.available("arrow.up.left.and.arrow.down.right", fallback: "magnifyingglass"))
                    .font(.system(size: 8.5))
                Text("双指缩放 · 默认 30mm × 10mm · 最大屏幕宽度")
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(AppTheme.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
        )
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("条码信息")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundColor(AppTheme.ink)

            infoRow("序列号", serialNumber, mono: true)
            divider
            infoRow("型号", item?.subLOB.nonEmpty ?? "—")
            divider
            infoRow("颜色", item?.color.nonEmpty ?? "—")
            divider
            infoRow("容量", item?.capacity.nonEmpty ?? "—")
        }
        .padding(15)
        .surfaceCard(cornerRadius: 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.line.opacity(0.65))
            .frame(height: 0.6)
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(AppTheme.secondary)
                .frame(width: 66, alignment: .leading)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: mono ? 11.5 : 12, weight: mono ? .medium : .regular, design: mono ? .monospaced : .default))
                .foregroundColor(AppTheme.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
