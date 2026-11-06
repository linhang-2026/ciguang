import CoreImage
import SwiftUI
import UIKit

enum ThemeExtractor {
    static func dominantColor(from data: Data?) -> Color? {
        guard let data, let image = UIImage(data: data) else { return nil }

                let thumbSize = CGSize(width: 32, height: 32)
        let thumb = UIGraphicsImageRenderer(size: thumbSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbSize))
        }

                guard let ciImage = CIImage(image: thumb),
              let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        guard let cgImage = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: 1, height: 1))
        else { return nil }

                guard let ctx = CGContext(
            data: &pixel,
            width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return Color(red: Double(pixel[0]) / 255.0,
                      green: Double(pixel[1]) / 255.0,
                      blue: Double(pixel[2]) / 255.0)
    }
}
