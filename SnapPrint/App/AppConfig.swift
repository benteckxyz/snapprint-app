import Foundation

/// Central configuration — runtime-editable values persist via UserDefaults.
/// Admin panel (5-tap) can change these without recompiling.
///
/// Production setup:
///   1. Operator opens Admin panel (tap SnapPrint logo 5×)
///   2. Enter Backend URL + API Key
///   3. Save — values persist in UserDefaults across launches
enum AppConfig {

    // MARK: - Backend API

    /// Base URL of the SnapPrint backend (e.g. https://print.yourdomain.com)
    static var backendBaseURL: String {
        get { UserDefaults.standard.string(forKey: "snapprint_backendURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_backendURL") }
    }

    /// X-API-Key header — set via Admin panel, never hardcoded in source.
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "snapprint_apiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_apiKey") }
    }

    static let receiptEndpoint = "/receipt"

    // MARK: - Printer (Star mC-Print3, USB-C)

    static var printerPortName: String {
        get { UserDefaults.standard.string(forKey: "snapprint_printerPort") ?? "USB:Star mC-Print3" }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_printerPort") }
    }
    static let printerPortSettings = ""
    static let printerTimeout: UInt32 = 10_000   // ms

    // MARK: - Image / Print (80mm, 203 DPI)

    static let thermalPrintWidthPx: CGFloat = 576

    // MARK: - UI

    static let appName           = "SnapPrint"
    static let receiptCodeLength = 6

    // MARK: - Camera

    static let countdownSeconds = 3

    // MARK: - Debug / Testing (only available in DEBUG builds)

#if DEBUG
    static var mockMode: Bool {
        get {
            if UserDefaults.standard.object(forKey: "snapprint_mockMode") != nil {
                return UserDefaults.standard.bool(forKey: "snapprint_mockMode")
            }
            return false
        }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_mockMode") }
    }

    static var mockPrinter: Bool {
        get {
            if UserDefaults.standard.object(forKey: "snapprint_mockPrinter") != nil {
                return UserDefaults.standard.bool(forKey: "snapprint_mockPrinter")
            }
            return false
        }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_mockPrinter") }
    }

    static let mockReceiptId   = "MOCK-001"
    static let mockPrintDelay: Double = 1.5
#endif
}
