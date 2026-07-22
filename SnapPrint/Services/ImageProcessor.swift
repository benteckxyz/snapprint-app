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

    // MARK: - Print Layout
    // mC-Print3: 72mm printable = 576 dots @ 203 DPI

    /// Tạo 1 tấm hình hoàn chỉnh cho in thermal:
    /// 1) Nướng sạch EXIF orientation & crop transform
    /// 2) Downsample về 576px wide (scale = 1.0)
    /// 3) B&W dither (grayscale → tone curve → sharpen → blur → Floyd-Steinberg dither)
    /// 4) Ghép ảnh B&W đã dither + footer text → 1 UIImage duy nhất
    func processForThermalPrint(_ sourceImage: UIImage) -> UIImage? {
        let printWidth = AppConfig.thermalPrintWidthPx  // 576.0

        // Step 1: Always fix orientation & strip embedded transform
        let oriented = fixOrientation(sourceImage)

        // Step 2: Downsample photo to exactly 576px wide (scale 1.0)
        let scaled = downsample(oriented, maxWidth: printWidth)

        // Step 3: Extract CGImage for thermal enhancement & dithering
        guard let cgImage = scaled.cgImage else { return nil }

        // Step 4: Xử lý ảnh cho giấy nhiệt (grayscale → tone → sharpen → blur → dither)
        guard let gray     = toGrayscale(cgImage: cgImage),
              let lifted   = liftToneCurve(cgImage: gray),
              let enhanced = applyThermalEnhancement(cgImage: lifted),
              let blurred  = applyPreDitherBlur(cgImage: enhanced),
              let dithered = floydSteinbergDither(cgImage: blurred)
        else { return nil }

        // Step 5: Ghép ảnh B&W đã dither + footer text → 1 tấm hình hoàn chỉnh
        let processedPhoto = UIImage(cgImage: dithered, scale: 1.0, orientation: .up)
        let finalImage = composeLayout(photo: processedPhoto)

        print("DEBUG: Final print image size: \(finalImage.size.width)×\(finalImage.size.height)pt, scale=\(finalImage.scale)")
        return finalImage
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

    /// Redraws the image through UIKit so orientation metadata is baked into pixels.
    /// Uses image.scale so full pixel resolution of the photo is preserved.
    private func fixOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// Public wrapper so callers can fix orientation if needed.
    func fixOrientationPublic(_ image: UIImage) -> UIImage { fixOrientation(image) }

    /// Downsamples image to target pixel width (e.g. 576px) maintaining aspect ratio.
    /// Produces a clean 1.0 scale UIImage where 1 pt = 1 pixel.
    func downsample(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let pixelW = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let pixelH = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))

        guard pixelW > 0 else { return image }
        let aspect = pixelH / pixelW
        let targetPixelSize = CGSize(width: maxWidth, height: maxWidth * aspect)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // 1pt = 1px
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetPixelSize))
        }
    }

    // MARK: - Step 0: Compose Layout

    /// Builds the print canvas with selected frame template (Standard, Rounded, or Vintage).
    func composeLayout(photo: UIImage) -> UIImage {
        let printWidth  = AppConfig.thermalPrintWidthPx
        let scale: CGFloat = 1                          // 1x — we work in print pixels
        let frameStyle = AppConfig.frameStyle

        // Canvas dimensions & layout margins depending on frame style
        let sideMargin: CGFloat = (frameStyle == .rounded || frameStyle == .vintage) ? 16 : 0
        let topMargin: CGFloat  = (frameStyle == .rounded || frameStyle == .vintage) ? 16 : 0
        let photoRenderWidth    = printWidth - (sideMargin * 2)
        let photoHeight         = photo.size.height / photo.size.width * photoRenderWidth

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

        let totalH = topMargin + photoHeight + footerH

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

            let photoRect = CGRect(x: sideMargin, y: topMargin, width: photoRenderWidth, height: photoHeight)

            // ── Photo Drawing (per Frame Style) ───────────────────────────
            switch frameStyle {
            case .standard:
                // Standard: Full-width square-edge photo
                photo.draw(in: photoRect)

            case .rounded:
                // Modern Rounded: Photo with 20px rounded corners & subtle border
                let clipPath = UIBezierPath(roundedRect: photoRect, cornerRadius: 20)
                ctx.cgContext.saveGState()
                clipPath.addClip()
                photo.draw(in: photoRect)
                ctx.cgContext.restoreGState()

                // Outline border
                UIColor.black.withAlphaComponent(0.6).setStroke()
                clipPath.lineWidth = 2
                clipPath.stroke()

            case .vintage:
                // Vintage: Polaroid Inner Frame (white margin + thin black inner line)
                photo.draw(in: photoRect)

                // Outer border around photo
                let outerBorder = UIBezierPath(rect: photoRect)
                UIColor.black.setStroke()
                outerBorder.lineWidth = 2
                outerBorder.stroke()

                // Inner inset line
                let innerRect = photoRect.insetBy(dx: 6, dy: 6)
                let innerBorder = UIBezierPath(rect: innerRect)
                UIColor.white.withAlphaComponent(0.8).setStroke()
                innerBorder.lineWidth = 1.5
                innerBorder.stroke()

            case .sawtooth:
                // Sawtooth Frame: Serrated picture frame border
                let sawtoothPath = createSawtoothPath(rect: photoRect, toothSize: 16, toothDepth: 6)
                ctx.cgContext.saveGState()
                sawtoothPath.addClip()
                photo.draw(in: photoRect)
                ctx.cgContext.restoreGState()

                // Outline border for teeth
                UIColor.black.setStroke()
                sawtoothPath.lineWidth = 2
                sawtoothPath.stroke()
            }

            // ── Divider Line (per Frame Style) ────────────────────────────
            let dividerY = topMargin + photoHeight + footerPadTop

            switch frameStyle {
            case .standard:
                // Single solid line
                UIColor.black.withAlphaComponent(0.6).setFill()
                ctx.fill(CGRect(x: 24, y: dividerY, width: printWidth - 48, height: 1.5))

            case .rounded:
                // Double line divider
                UIColor.black.withAlphaComponent(0.7).setFill()
                ctx.fill(CGRect(x: 32, y: dividerY - 2, width: printWidth - 64, height: 1))
                ctx.fill(CGRect(x: 48, y: dividerY + 3, width: printWidth - 96, height: 1))

            case .vintage:
                // Dashed line divider
                let dashPath = UIBezierPath()
                dashPath.move(to: CGPoint(x: 24, y: dividerY))
                dashPath.addLine(to: CGPoint(x: printWidth - 24, y: dividerY))
                let dashes: [CGFloat] = [6, 4]
                dashPath.setLineDash(dashes, count: dashes.count, phase: 0)
                dashPath.lineWidth = 1.5
                UIColor.black.withAlphaComponent(0.7).setStroke()
                dashPath.stroke()

            case .sawtooth:
                // Decorative ornament line (dot-dash pattern)
                let dashPath = UIBezierPath()
                dashPath.move(to: CGPoint(x: 24, y: dividerY))
                dashPath.addLine(to: CGPoint(x: printWidth - 24, y: dividerY))
                let dashes: [CGFloat] = [10, 4, 3, 4]
                dashPath.setLineDash(dashes, count: dashes.count, phase: 0)
                dashPath.lineWidth = 1.5
                UIColor.black.withAlphaComponent(0.8).setStroke()
                dashPath.stroke()
            }

            // ── Footer text ───────────────────────────────────────────────
            let textX: CGFloat = 0
            var textY = dividerY + dividerHeight + 14

            // Footer Line 1 (configurable)
            let line1 = AppConfig.footerLine1
            if !line1.isEmpty {
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
            }

            // Footer Line 2 (configurable)
            let line2 = AppConfig.footerLine2
            if !line2.isEmpty {
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
    }

    /// Generates a serrated sawtooth path around a rectangle (like a postage stamp or picture frame).
    private func createSawtoothPath(rect: CGRect, toothSize: CGFloat = 16, toothDepth: CGFloat = 6) -> UIBezierPath {
        let path = UIBezierPath()

        let left   = rect.minX
        let right  = rect.maxX
        let top    = rect.minY
        let bottom = rect.maxY

        let width  = rect.width
        let height = rect.height

        let numTeethX = max(1, Int(width / toothSize))
        let stepX     = width / CGFloat(numTeethX)

        let numTeethY = max(1, Int(height / toothSize))
        let stepY     = height / CGFloat(numTeethY)

        path.move(to: CGPoint(x: left, y: top))

        // Top edge
        for i in 0..<numTeethX {
            let startX = left + CGFloat(i) * stepX
            let midX   = startX + stepX / 2.0
            let endX   = startX + stepX
            path.addLine(to: CGPoint(x: midX, y: top + toothDepth))
            path.addLine(to: CGPoint(x: endX, y: top))
        }

        // Right edge
        for i in 0..<numTeethY {
            let startY = top + CGFloat(i) * stepY
            let midY   = startY + stepY / 2.0
            let endY   = startY + stepY
            path.addLine(to: CGPoint(x: right - toothDepth, y: midY))
            path.addLine(to: CGPoint(x: right, y: endY))
        }

        // Bottom edge
        for i in (0..<numTeethX).reversed() {
            let startX = left + CGFloat(i) * stepX
            let midX   = startX + stepX / 2.0
            path.addLine(to: CGPoint(x: midX, y: bottom - toothDepth))
            path.addLine(to: CGPoint(x: startX, y: bottom))
        }

        // Left edge
        for i in (0..<numTeethY).reversed() {
            let startY = top + CGFloat(i) * stepY
            let midY   = startY + stepY / 2.0
            path.addLine(to: CGPoint(x: left + toothDepth, y: midY))
            path.addLine(to: CGPoint(x: left, y: startY))
        }

        path.close()
        return path
    }

    // MARK: - Step 1: Resize

    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // 1pt = 1px (576px)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
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
        let width  = cgImage.width
        let height = cgImage.height

        // 1. Render cgImage into a contiguous 8-bit DeviceGray buffer (1 byte per pixel)
        // CoreImage outputs 32-bit ARGB CGImages; rendering into Gray CGContext guarantees 1 byte/pixel
        var srcPixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let drawCtx = CGContext(
            data: &srcPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        drawCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 2. Convert to Float array for error diffusion
        var pixels = [Float](repeating: 0, count: width * height)
        for i in 0 ..< width * height {
            pixels[i] = Float(srcPixels[i]) / 255.0
        }

        var output = [UInt8](repeating: 0, count: width * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let idx = y * width + x
                let old = pixels[idx]
                let new: Float = old > ditherThreshold ? 1.0 : 0.0
                output[idx] = new > 0.5 ? 255 : 0
                let err = old - new

                if x + 1 < width                  { pixels[idx + 1]         += err * (7.0 / 16.0) }
                if y + 1 < height {
                    if x > 0                       { pixels[idx + width - 1] += err * (3.0 / 16.0) }
                                                     pixels[idx + width]     += err * (5.0 / 16.0)
                    if x + 1 < width              { pixels[idx + width + 1] += err * (1.0 / 16.0) }
                }
            }
        }

        guard let outCtx = CGContext(
            data: &output,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        return outCtx.makeImage()
    }
}
