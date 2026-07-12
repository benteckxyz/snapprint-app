import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate

/// Pre-processes images for optimal printing on Star mC-Print3 thermal printer.
///
/// Print layout:
///   ┌─────────────────┐
///   │                 │
///   │    [  Photo  ]  │
///   │                 │
///   ├─────────────────┤  ← divider line
///   │                 │
///   │ Thanks for      │
///   │ using SnapPrint │
///   │                 │
///   └─────────────────┘
///
/// Pipeline: Compose → Resize → Grayscale → Contrast → Dither
///
final class ImageProcessor {

    static let shared = ImageProcessor()
    private init() {}

    private let ciContext = CIContext()

    // MARK: - Public

    /// Compose layout (photo + footer) then optimise for thermal printing.
    func processForThermalPrint(_ sourceImage: UIImage) -> UIImage? {
        // Step 0: Compose print layout
        let composed = composeLayout(photo: sourceImage)

        guard let cgImage = composed.cgImage else { return nil }

        // Step 1: Resize to printer width
        let targetWidth  = Int(AppConfig.thermalPrintWidthPx)
        let aspectRatio  = CGFloat(cgImage.height) / CGFloat(cgImage.width)
        let targetHeight = Int(CGFloat(targetWidth) * aspectRatio)

        guard let resized  = resize(cgImage: cgImage, width: targetWidth, height: targetHeight) else { return nil }

        // Step 2: Grayscale
        guard let gray     = toGrayscale(cgImage: resized)            else { return nil }

        // Step 3: Contrast + brightness
        guard let enhanced = applyThermalEnhancement(cgImage: gray)   else { return nil }

        // Step 4: Floyd-Steinberg dithering
        guard let dithered = floydSteinbergDither(cgImage: enhanced)  else { return nil }

        return UIImage(cgImage: dithered)
    }

    // MARK: - Step 0: Compose Layout

    /// Builds the print canvas: photo on top, branded footer below.
    func composeLayout(photo: UIImage) -> UIImage {
        let printWidth  = AppConfig.thermalPrintWidthPx
        let scale: CGFloat = 1                          // 1x — we work in print pixels

        // Photo height maintains aspect ratio
        let photoHeight = photo.size.height / photo.size.width * printWidth

        // Footer metrics
        let footerPadTop:    CGFloat = 20
        let footerPadBottom: CGFloat = 28
        let dividerHeight:   CGFloat = 1
        let titleSize:       CGFloat = 28
        let subtitleSize:    CGFloat = 22
        let lineSpacing:     CGFloat = 8

        let titleH    = titleSize    + 4
        let subtitleH = subtitleSize + 4
        let footerH   = footerPadTop + dividerHeight + 14
                      + titleH + lineSpacing + subtitleH + footerPadBottom

        let totalH = photoHeight + footerH

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: printWidth, height: totalH),
            format: {
                let f = UIGraphicsImageRendererFormat()
                f.scale = scale
                f.opaque = true
                return f
            }()
        )

        return renderer.image { ctx in
            let bounds = CGRect(x: 0, y: 0, width: printWidth, height: totalH)

            // ── White background ──────────────────────────────────────────
            UIColor.white.setFill()
            ctx.fill(bounds)

            // ── Photo ─────────────────────────────────────────────────────
            let photoRect = CGRect(x: 0, y: 0, width: printWidth, height: photoHeight)
            photo.draw(in: photoRect)

            // ── Divider line ──────────────────────────────────────────────
            let dividerY = photoHeight + footerPadTop
            UIColor.black.withAlphaComponent(0.5).setFill()
            ctx.fill(CGRect(x: 20, y: dividerY, width: printWidth - 40, height: dividerHeight))

            // ── Footer text ───────────────────────────────────────────────
            let textX: CGFloat = 0
            var textY = dividerY + dividerHeight + 14

            // "Thanks for using"
            let line1 = "Thanks for using"
            let para1 = NSMutableParagraphStyle()
            para1.alignment = .center
            let attrs1: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: titleSize, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle:  para1
            ]
            (line1 as NSString).draw(
                in: CGRect(x: textX, y: textY, width: printWidth, height: titleH + 4),
                withAttributes: attrs1
            )
            textY += titleH + lineSpacing

            // "SnapPrint" — bold accent
            let line2 = "SnapPrint ✦"
            let para2 = NSMutableParagraphStyle()
            para2.alignment = .center
            let attrs2: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: subtitleSize, weight: .bold),
                .foregroundColor: UIColor.black,
                .paragraphStyle:  para2
            ]
            (line2 as NSString).draw(
                in: CGRect(x: textX, y: textY, width: printWidth, height: subtitleH + 4),
                withAttributes: attrs2
            )
        }
    }

    // MARK: - Step 1: Resize

    private func resize(cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        var sourceBuffer      = vImage_Buffer()
        var destinationBuffer = vImage_Buffer()

        defer {
            sourceBuffer.data?.deallocate()
            destinationBuffer.data?.deallocate()
        }

        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }

        error = vImageBuffer_Init(&destinationBuffer,
                                  vImagePixelCount(height),
                                  vImagePixelCount(width),
                                  32,
                                  vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }

        error = vImageScale_ARGB8888(&sourceBuffer, &destinationBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else { return nil }

        return vImageCreateCGImageFromBuffer(&destinationBuffer, &format, nil, nil, vImage_Flags(kvImageNoFlags), nil)?.takeRetainedValue()
    }

    // MARK: - Step 2: Grayscale

    private func toGrayscale(cgImage: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return ctx.makeImage()
    }

    // MARK: - Step 3: Thermal Enhancement

    private func applyThermalEnhancement(cgImage: CGImage) -> CGImage? {
        var ciImage = CIImage(cgImage: cgImage)

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage  = ciImage
        colorControls.contrast    = AppConfig.thermalContrastBoost
        colorControls.brightness  = AppConfig.thermalBrightnessShift
        colorControls.saturation  = 0.0
        guard let enhanced = colorControls.outputImage else { return nil }
        ciImage = enhanced

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = ciImage
        sharpen.sharpness  = 0.4
        guard let sharpened = sharpen.outputImage else { return nil }

        return ciContext.createCGImage(sharpened, from: sharpened.extent)
    }

    // MARK: - Step 4: Floyd-Steinberg Dithering

    private func floydSteinbergDither(cgImage: CGImage) -> CGImage? {
        let width       = cgImage.width
        let height      = cgImage.height
        let bytesPerRow = width

        guard let dataProvider = cgImage.dataProvider,
              let data         = dataProvider.data,
              let srcBytes     = CFDataGetBytePtr(data) else { return nil }

        var pixels = [Float](repeating: 0, count: width * height)
        for i in 0 ..< width * height {
            pixels[i] = Float(srcBytes[i]) / 255.0
        }

        var output = [UInt8](repeating: 0, count: width * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let idx = y * width + x
                let old = pixels[idx]
                let new: Float = old > AppConfig.ditherThreshold ? 1.0 : 0.0
                output[idx] = new > 0.5 ? 255 : 0
                let err = old - new

                if x + 1 < width                      { pixels[idx + 1]         += err * (7.0 / 16.0) }
                if y + 1 < height {
                    if x > 0                           { pixels[idx + width - 1] += err * (3.0 / 16.0) }
                                                         pixels[idx + width]     += err * (5.0 / 16.0)
                    if x + 1 < width                  { pixels[idx + width + 1] += err * (1.0 / 16.0) }
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &output,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}
