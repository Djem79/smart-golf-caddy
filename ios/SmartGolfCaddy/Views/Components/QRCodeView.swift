// ios/SmartGolfCaddy/Views/Components/QRCodeView.swift
// QR через CoreImage — без сторонних зависимостей (веб использует qrcode.react).
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum QRCode {
    static func image(for text: String) -> UIImage? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Апскейл до читаемого размера: нативный вывод ~25x25 точек.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 200

    var body: some View {
        if let image = QRCode.image(for: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("QR-код для входа в лобби")
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}
