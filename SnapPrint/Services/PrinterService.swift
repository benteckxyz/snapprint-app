import Foundation
import UIKit

// MARK: - NOTE -----------------------------------------------------------
// Star mC-Print3 (mCP31Ci) – kết nối USB-C/BT trực tiếp từ iPad
//
// SETUP (Swift Package Manager):
// 1. Xcode → File → Add Package Dependencies...
//      • https://github.com/star-micronics/stario-ios
//      • https://github.com/star-micronics/stario-extension-ios
//    → Add cả hai vào target "SnapPrint"
//
// 2. Info.plist:
//    UISupportedExternalAccessoryProtocols → jp.star-m.starpro
//    (bắt buộc để iOS nhận mC-Print3 qua MFi)
//
// 3. Cắm cable USB-C từ iPad vào mC-Print3 → bật máy in → chạy app
//
// PORT NAME: "BT:mC-Print3" hoặc "USB:mC-Print3" (auto-detected)
// PORT SETTINGS: ""  (empty = auto)
// EMULATION: StarPRNT (chế độ chuẩn cho mC-Print3)
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

        // ── Star SDK Official Pattern ─────────────────────────────────
        // Follows: StarPRNT-SDK-iOS-Swift/PrinterFunctions.swift
        //          StarPRNT-SDK-iOS-Swift/Communication.swift
        // ModelCapability: mC-Print3 (MCP31) → .starPRNT emulation
        // ──────────────────────────────────────────────────────────────

        let portName = AppConfig.printerPortName
        let portSettings = AppConfig.printerPortSettings
        let timeout = AppConfig.printerTimeout

        print("DEBUG: --- PRINT START ---")
        print("DEBUG: Port='\(portName)', Image=\(image.size.width)×\(image.size.height)pt, scale=\(image.scale)")

        // 1. Build commands — exact same pattern as official SDK sample
        let builder: ISCBBuilder = StarIoExt.createCommandBuilder(StarIoExtEmulation.starPRNT)

        builder.beginDocument()

        builder.appendBitmap(image, diffusion: false)

        builder.appendCutPaper(SCBCutPaperAction.partialCutWithFeed)

        builder.endDocument()

        let commands: Data = builder.commands.copy() as! Data

        print("DEBUG: Command buffer = \(commands.count) bytes")

        // 2. Open port
        let port = try SMPort.getPort(
            portName:         portName,
            portSettings:     portSettings,
            ioTimeoutMillis:  timeout
        )
        defer { SMPort.release(port) }

        // 3. Send data — pattern from official SDK Communication.sendCommandsDoNotCheckCondition
        var printerStatus = StarPrinterStatus_2()

        // Check printer status before writing
        try port.getParsedStatus(starPrinterStatus: &printerStatus, level: 2)

        var commandsArray: [UInt8] = [UInt8](repeating: 0, count: commands.count)
        commands.copyBytes(to: &commandsArray, count: commands.count)

        let startDate = Date()
        var total: UInt32 = 0

        while total < UInt32(commands.count) {
            var written: UInt32 = 0

            try port.write(
                writeBuffer: commandsArray,
                offset: total,
                size: UInt32(commands.count) - total,
                numberOfBytesWritten: &written
            )

            total += written

            if Date().timeIntervalSince(startDate) >= 30.0 {
                break
            }
        }

        if total < UInt32(commands.count) {
            print("DEBUG: ⚠️ Write timeout: \(total)/\(commands.count) bytes")
            throw SnapPrintError.printerError("Write timeout: \(total)/\(commands.count) bytes")
        }

        // Wait for printer to finish processing (including cut)
        try port.getParsedStatus(starPrinterStatus: &printerStatus, level: 2)

        print("DEBUG: --- PRINT COMPLETE — \(total) bytes sent ---")
        // ──────────────────────────────────────────────────────────────
    }

    // MARK: - Discover Printer

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

                let printerList = (try? SMPort.searchPrinter(target: "ALL:")) as? [PortInfo] ?? []
                let ports = printerList.compactMap { info -> PrinterPort? in
                    return PrinterPort(name: info.portName, modelName: info.modelName)
                }
                continuation.resume(returning: ports)
            }
        }
    }

    // MARK: - Test Print (Diagnostic)

    /// Thử in text đơn giản với MỌI emulation mode để tìm ra mode đúng cho máy in.
    /// Trả về tên emulation nào in thành công.
    func testPrint() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let portName = AppConfig.printerPortName
                let portSettings = AppConfig.printerPortSettings
                let timeout = AppConfig.printerTimeout

                // Thử từng emulation mode
                let emulations: [(StarIoExtEmulation, String)] = [
                    (.starPRNT,       "starPRNT"),
                    (.starLine,       "starLine"),
                    (.starGraphic,    "starGraphic"),
                    (.escPos,         "escPos"),
                    (.escPosMobile,   "escPosMobile"),
                    (.starDotImpact,  "starDotImpact"),
                ]

                var results: [String] = []

                for (emulation, name) in emulations {
                    do {
                        guard let builder = StarIoExt.createCommandBuilder(emulation) else {
                            results.append("[\(name)] builder=nil")
                            continue
                        }

                        builder.beginDocument()
                        let testText = "=== TEST: \(name) ===\nSnapPrint Diagnostic\nIf you see this,\nemulation: \(name)\nis CORRECT!\n\n"
                        if let textData = testText.data(using: .ascii) {
                            builder.append(textData)
                        }
                        builder.appendCutPaper(SCBCutPaperAction.partialCut)
                        builder.endDocument()

                        guard let commands = builder.commands else {
                            results.append("[\(name)] commands=nil")
                            continue
                        }

                        let port = try SMPort.getPort(
                            portName: portName,
                            portSettings: portSettings,
                            ioTimeoutMillis: timeout
                        )
                        defer { SMPort.release(port) }

                        var written: UInt32 = 0
                        let bytePointer = commands.bytes.assumingMemoryBound(to: UInt8.self)
                        _ = try port.write(
                            writeBuffer: bytePointer,
                            offset: 0,
                            size: UInt32(commands.length),
                            numberOfBytesWritten: &written
                        )

                        results.append("[\(name)] OK — sent \(written)/\(commands.length) bytes")

                        // Đợi 3 giây giữa mỗi emulation để máy in xử lý
                        Thread.sleep(forTimeInterval: 3.0)

                    } catch {
                        results.append("[\(name)] ERROR: \(error.localizedDescription)")
                    }
                }

                let summary = results.joined(separator: "\n")
                print("DEBUG: TEST PRINT RESULTS:\n\(summary)")
                continuation.resume(returning: summary)
            }
        }
    }
}
