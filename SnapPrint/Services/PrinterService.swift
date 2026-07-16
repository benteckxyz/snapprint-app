import Foundation
import UIKit

// MARK: - NOTE -----------------------------------------------------------
// Star mC-Print3 (mCP31Ci) – kết nối USB-C trực tiếp từ iPad
//
// SETUP (Swift Package Manager):
// 1. Xcode → File → Add Package Dependencies...
//      • https://github.com/star-micronics/stario-ios
//      • https://github.com/star-micronics/stario-extension-ios
//    → Add cả hai vào target "SnapPrint"
//
// 2. Sau khi SPM resolve xong, uncomment 2 dòng import bên dưới:
//      import StarIO
//      import StarIO_Extension
//
// 3. Info.plist đã có sẵn:
//    UISupportedExternalAccessoryProtocols → jp.star-m.stario.StarIoExtPort
//    (bắt buộc để iOS nhận mC-Print3 qua USB-C MFi)
//
// 4. Cắm cable USB-C từ iPad vào mC-Print3 → bật máy in → chạy app
//
// PORT NAME: "USB:Star mC-Print3"  (đã set sẵn trong AppConfig)
// PORT SETTINGS: ""                (empty = auto for USB)
// ------------------------------------------------------------------------

// Uncomment sau khi thêm SPM packages:
import StarIO
import StarIO_Extension

/// StarPRNT SDK wrapper cho Star mC-Print3 (USB-C trực tiếp từ iPad/iPhone).
final class PrinterService: @unchecked Sendable {

    static let shared = PrinterService()
    private init() {}

    // MARK: - Print Image

    /// In UIImage đã được optimize lên mC-Print3.
    /// Tự xử lý background thread.
    func printImage(_ image: UIImage) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.performPrint(image: image)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Internal Print

    private func performPrint(image: UIImage) throws {

#if DEBUG
        if AppConfig.mockMode || AppConfig.mockPrinter {
            Thread.sleep(forTimeInterval: AppConfig.mockPrintDelay)
            return
        }
#endif

        // ── STARPRNT SDK – USB-C Connection ─────────────────────────────
        // 1. Mở port USB-C
        guard let port = SMPort.getPort(
            portName:         AppConfig.printerPortName,     // "USB:Star mC-Print3"
            portSettings:     AppConfig.printerPortSettings, // ""
            ioTimeoutMillis:  AppConfig.printerTimeout        // 10000
        ) else {
            throw SnapPrintError.printerNotFound
        }
        defer { SMPort.release(port) }

        // 2. Build lệnh in ảnh (StarGraphic emulation cho ảnh bitmap)
        guard let builder = ISCBBuilder(emulation: StarIoExt.Emulation.StarGraphic) else {
            throw SnapPrintError.printerError("Cannot create command builder")
        }
        builder.appendBitmap(
            image,
            diffusion: true,                               // Floyd-Steinberg trong SDK
            width:     Int32(AppConfig.thermalPrintWidthPx), // 576px cho 80mm
            bothScale: true
        )
        builder.appendCutPaper(.partial)                   // cắt giấy sau khi in

        // 3. Gửi lệnh đến máy in
        guard let commands = builder.commands else {
            throw SnapPrintError.printerError("Empty command buffer")
        }
        var written: UInt32 = 0
        commands.bytes.withUnsafeBytes { ptr in
            _ = port.write(
                ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                size:                    UInt32(commands.length),
                numberOfBytesWritten:    &written
            )
        }
        guard written == UInt32(commands.length) else {
            throw SnapPrintError.printerError("Print incomplete: wrote \(written)/\(commands.length) bytes")
        }
        // ────────────────────────────────────────────────────────────────
    }

    // MARK: - Discover USB Printer

    /// Tìm mC-Print3 đang kết nối qua USB-C.
    /// USB printers xuất hiện ngay khi cắm dây – không cần search như LAN.
    func discoverPrinters() async throws -> [PrinterPort] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .background).async {

#if DEBUG
                if AppConfig.mockMode || AppConfig.mockPrinter {
                    let mockPort = PrinterPort(name: AppConfig.printerPortName,
                                              modelName: "Star mC-Print3 (mCP31Ci) – USB-C")
                    continuation.resume(returning: [mockPort])
                    return
                }
#endif

                // Với USB, search theo "USB:" prefix
                let printerList = SMPort.searchPrinter(portType: "USB:") as? [[String: String]] ?? []
                let ports = printerList.compactMap { info -> PrinterPort? in
                    guard let portName = info["portName"] else { return nil }
                    return PrinterPort(name: portName, modelName: info["modelName"])
                }
                continuation.resume(returning: ports)
            }
        }
    }
}
