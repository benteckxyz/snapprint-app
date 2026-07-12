import Foundation

// MARK: - Receipt Model

struct ReceiptCheckResponse: Codable {
    let exists: Bool
    let printed: Bool
    let receiptId: String?
    let message: String?
}

struct MarkPrintedRequest: Codable {
    let receiptId: String
}

struct MarkPrintedResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: - App State

enum ReceiptStatus {
    case unknown
    case valid(receiptId: String)
    case alreadyPrinted
    case notFound
}

enum PrintState: Equatable {
    case idle
    case processing
    case printing
    case success
    case failed(String)
}

// MARK: - Printer Discovery

struct PrinterPort {
    let name: String          // e.g. "TCP:192.168.1.100"
    let modelName: String?
}
