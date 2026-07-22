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
        get { UserDefaults.standard.string(forKey: "snapprint_backendURL") ?? "https://print.thevietlab.com" }
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
        get { UserDefaults.standard.string(forKey: "snapprint_printerPort") ?? "AutoSwitch:" }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_printerPort") }
    }
    static let printerPortSettings = ""
    static let printerTimeout: UInt32 = 10_000   // ms

    // MARK: - Image / Print (80mm, 203 DPI)

    static let thermalPrintWidthPx: CGFloat = 576

    // MARK: - UI & Custom Footer

    static let appName           = "SnapPrint"
    static let receiptCodeLength = 6

    /// Line 1 of print footer (e.g. "Thanks for using")
    static var footerLine1: String {
        get { UserDefaults.standard.string(forKey: "snapprint_footerLine1") ?? "Thanks for using" }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_footerLine1") }
    }

    /// Line 2 of print footer (e.g. "SnapPrint ✦")
    static var footerLine2: String {
        get { UserDefaults.standard.string(forKey: "snapprint_footerLine2") ?? "SnapPrint ✦" }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_footerLine2") }
    }

    /// Frame style templates for printed photos
    enum FrameStyle: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case rounded  = "Modern Rounded"
        case vintage  = "Vintage Stamp"
        case sawtooth = "Sawtooth Frame"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .standard: return "Classic photo layout with solid divider"
            case .rounded:  return "Rounded photo corners with double divider"
            case .vintage:  return "Inner border with dashed divider line"
            case .sawtooth: return "Serrated picture frame with decorative teeth border"
            }
        }
    }

    /// Currently selected frame style
    static var frameStyle: FrameStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: "snapprint_frameStyle") ?? FrameStyle.standard.rawValue
            return FrameStyle(rawValue: raw) ?? .standard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "snapprint_frameStyle") }
    }

    // MARK: - Camera

    static let countdownSeconds = 3

    // MARK: - Beast Mode

    static var beastMode: Bool {
        get { UserDefaults.standard.bool(forKey: "snapprint_beastMode") }
        set { UserDefaults.standard.set(newValue, forKey: "snapprint_beastMode") }
    }

    // MARK: - Mock Fallback (internal constants, no toggles)
    static let mockReceiptId   = "BEAST_MODE"
    static let mockPrintDelay: Double = 1.5
    static var mockMode: Bool { false }
    static var mockPrinter: Bool { false }
}
