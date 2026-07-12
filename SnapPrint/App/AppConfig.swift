import Foundation

/// Central configuration — runtime-editable values persist via UserDefaults.
/// Admin panel (5-tap) can change these without recompiling.
enum AppConfig {

    // MARK: - Mock Mode
    /// true  → bypass backend + printer (auto-true in DEBUG)
    /// false → real backend + real printer
    static var mockMode: Bool {
        get {
            if UserDefaults.standard.object(forKey: "snapprint_mockMode") != nil {
                return UserDefaults.standard.bool(forKey: "snapprint_mockMode")
            }
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_mockMode") }
    }

    // MARK: - Backend API
    static var backendBaseURL: String {
        get { UserDefaults.standard.string(forKey: "snapprint_backendURL") ?? "https://api.yourdomain.com" }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_backendURL") }
    }
    /// X-API-Key header sent to backend
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
    static let ditherThreshold: Float       = 0.5
    static let thermalContrastBoost: Float  = 1.4
    static let thermalBrightnessShift: Float = 0.05

    // MARK: - UI
    static let appName           = "SnapPrint"
    static let receiptCodeLength = 6        // number of OTP boxes

    // MARK: - Camera
    static let countdownSeconds  = 3

    // MARK: - Mock Data
    static let mockReceiptId     = "MOCK-001"
    static let mockPrintDelay: Double = 1.5
}
