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

    // MARK: - Thermal Enhancement Config
    // v3 — tuned from real print tests on Star mC-Print3
    private let shadowLift:      Float = 0.22   // lift deep shadows (tested: 0.22 optimal)
    private let midtoneLift:     Float = 0.26   // lift skin/face midtones
    private let sharpenAmount:   Float = 0.85   // strong unsharp mask → edges survive pre-blur
    private let sharpenRadius:   Float = 1.8    // unsharp mask radius
    private let preDitherBlur:   Float = 1.8    // Gaussian blur before dither → much less grain
    private let ditherThreshold: Float = 0.65   // higher → more white pixels → less grain density

    /// Compose layout (photo + footer) then optimise for thermal printing.
    func processForThermalPrint(_ sourceImage: UIImage) -> UIImage? {
        // Step 0: Compose print layout
        let composed = composeLayout(photo: fixOrientation(sourceImage))

        guard let cgImage = composed.cgImage else { return nil }

        // Step 1: Resize to printer width
        let targetWidth  = Int(AppConfig.thermalPrintWidthPx)
        let aspectRatio  = CGFloat(cgImage.height) / CGFloat(cgImage.width)
        let targetHeight = Int(CGFloat(targetWidth) * aspectRatio)

        guard let resized  = resize(cgImage: cgImage, width: targetWidth, height: targetHeight),
              let gray     = toGrayscale(cgImage: resized),
              let lifted   = liftToneCurve(cgImage: gray),
              let enhanced = applyThermalEnhancement(cgImage: lifted),
              let blurred  = applyPreDitherBlur(cgImage: enhanced),   // ← reduces grain
              let dithered = floydSteinbergDither(cgImage: blurred)
        else { return nil }

        return UIImage(cgImage: dithered)
    }

    /// B&W-process the raw photo only (no layout compose).
    /// Use this for the preview frame: call this first, then composeLayout.
    func processPhotoForPreview(_ photo: UIImage) -> UIImage {
        let oriented = fixOrientation(photo)
        guard let cgImage = oriented.cgImage,
              let gray    = toGrayscale(cgImage: cgImage),
              let lifted  = liftToneCurve(cgImage: gray),
              let sharp   = applyThermalEnhancement(cgImage: lifted)
        // Note: no blur/dither for preview — keep it smooth for on-screen display
        else { return photo }
        return UIImage(cgImage: sharp)
    }

    /// Redraws the image through UIKit so orientation metadata is baked in.
    /// Without this, UIImage→CGImage loses EXIF rotation and the image appears rotated.
    private func fixOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// Public wrapper so callers (e.g. view .task) can fix orientation before passing image in.
    func fixOrientationPublic(_ image: UIImage) -> UIImage { fixOrientation(image) }

    /// Downsample image to maxWidth — drastically reduces memory for preview processing.
    /// A 12MP iPhone photo (4032px wide) → 800px wide = ~96% less memory.
    func downsample(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        guard image.size.width > maxWidth else { return image }
        let scale  = maxWidth / image.size.width
        let newSize = CGSize(width: maxWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
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
            colorSpace: Unmanaged.passUnretained(CGColorSpaceCreateDeviceRGB()),
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

    // MARK: - Step 2b: Tone Curve — lift shadows & midtones
    //
    // Thermal printers crush dark pixels to solid black.
    // This curve lifts shadows/midtones so faces don't go solid black.
    // Control points (input → output):
    //   0.00 → 0.00  (pure black stays black)
    //   0.20 → 0.20+shadowLift  (lift deep shadows — prevents dark skin → black)
    //   0.50 → 0.50+midtoneLift (lift midtones — preserve face detail)
    //   0.80 → 0.82  (keep highlights mostly intact)
    //   1.00 → 1.00  (pure white stays white)
    //
    private func liftToneCurve(cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let curve   = CIFilter.toneCurve()
        curve.inputImage = ciImage
        curve.point0 = CGPoint(x: 0.00, y: 0.00)
        curve.point1 = CGPoint(x: 0.20, y: Double(0.20 + shadowLift))
        curve.point2 = CGPoint(x: 0.50, y: Double(0.50 + midtoneLift))
        curve.point3 = CGPoint(x: 0.80, y: 0.84)   // v3: 0.82 → 0.84
        curve.point4 = CGPoint(x: 1.00, y: 1.00)
        guard let out = curve.outputImage else { return nil }
        return ciContext.createCGImage(out, from: out.extent)
    }

    // MARK: - Step 3: Thermal Enhancement (sharpen + final tone)

    private func applyThermalEnhancement(cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        // Strong unsharp mask first — edges get crisp BEFORE pre-dither blur
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = ciImage
        sharpen.sharpness  = sharpenAmount   // 0.85 — stronger than before
        sharpen.radius     = sharpenRadius   // 1.8
        guard let sharpened = sharpen.outputImage else { return nil }
        return ciContext.createCGImage(sharpened, from: sharpened.extent)
    }

    // MARK: - Step 3b: Pre-Dither Gaussian Blur
    // Smooths high-freq noise so Floyd-Steinberg error diffuses gradually.
    // Applied AFTER sharpen so crisp edges survive; only flat areas (skin) get smoothed.
    private func applyPreDitherBlur(cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let blur    = CIFilter.gaussianBlur()
        blur.inputImage = ciImage
        blur.radius     = preDitherBlur   // 1.8
        guard let blurred = blur.outputImage else { return nil }
        // Clamp to original extent to remove CIGaussianBlur edge padding
        let clamped = blurred.cropped(to: ciImage.extent)
        return ciContext.createCGImage(clamped, from: clamped.extent)
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
                let new: Float = old > ditherThreshold ? 1.0 : 0.0   // tuned threshold
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
