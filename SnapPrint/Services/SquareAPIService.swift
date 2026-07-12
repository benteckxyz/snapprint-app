import Foundation

/// Service to check receipt codes against your backend,
/// which in turn calls Square API.
///
/// Backend expected endpoints:
///   GET  {baseURL}/receipt/{code}
///        Response: { "exists": Bool, "printed": Bool, "receiptId": String?, "message": String? }
///
///   POST {baseURL}/receipt/mark-printed
///        Body: { "receiptId": String }
///        Response: { "success": Bool, "message": String? }
///
final class SquareAPIService {

    static let shared = SquareAPIService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Build a request with auth header pre-filled
    private func makeRequest(url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !AppConfig.apiKey.isEmpty {
            req.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return req
    }

    // MARK: - Check Receipt

    /// Check if a receipt code exists and whether it has been printed.
    func checkReceipt(code: String) async throws -> ReceiptCheckResponse {

        // ── MOCK MODE ────────────────────────────────────────────────────
        if AppConfig.mockMode {
            try? await Task.sleep(nanoseconds: 800_000_000) // simulate network delay

            // Simulate "already printed" for codes ending with "X"
            if code.uppercased().hasSuffix("X") {
                return ReceiptCheckResponse(
                    exists: true,
                    printed: true,
                    receiptId: AppConfig.mockReceiptId,
                    message: "Already printed"
                )
            }
            // Simulate "not found" for codes shorter than 4 chars
            if code.count < 4 {
                return ReceiptCheckResponse(
                    exists: false,
                    printed: false,
                    receiptId: nil,
                    message: "Receipt not found"
                )
            }
            // Any other code → valid & not printed yet
            return ReceiptCheckResponse(
                exists: true,
                printed: false,
                receiptId: AppConfig.mockReceiptId,
                message: nil
            )
        }
        // ────────────────────────────────────────────────────────────────

        guard let url = URL(string: "\(AppConfig.backendBaseURL)\(AppConfig.receiptEndpoint)/\(code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code)") else {
            throw SnapPrintError.invalidURL
        }

        var request = makeRequest(url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SnapPrintError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(ReceiptCheckResponse.self, from: data)
        case 404:
            return ReceiptCheckResponse(exists: false, printed: false, receiptId: nil, message: "Receipt not found")
        default:
            throw SnapPrintError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Mark as Printed

    /// Mark a receipt as printed after successful print job.
    func markAsPrinted(receiptId: String) async throws -> MarkPrintedResponse {

        // ── MOCK MODE ────────────────────────────────────────────────────
        if AppConfig.mockMode {
            try? await Task.sleep(nanoseconds: 300_000_000)
            print("[SquareAPIService] MOCK: marked \(receiptId) as printed")
            return MarkPrintedResponse(success: true, message: nil)
        }
        // ────────────────────────────────────────────────────────────────

        guard let url = URL(string: "\(AppConfig.backendBaseURL)\(AppConfig.receiptEndpoint)/mark-printed") else {
            throw SnapPrintError.invalidURL
        }

        var request = makeRequest(url: url, method: "POST")
        let body = MarkPrintedRequest(receiptId: receiptId)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SnapPrintError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw SnapPrintError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(MarkPrintedResponse.self, from: data)
    }
}

// MARK: - Errors

enum SnapPrintError: LocalizedError {
    case invalidURL
    case networkError(String)
    case serverError(Int)
    case printerNotFound
    case printerError(String)
    case imageProcessingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL. Please check AppConfig."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .printerNotFound:
            return "Printer not found. Make sure the mC-Print3 is on the same network."
        case .printerError(let msg):
            return "Printer error: \(msg)"
        case .imageProcessingFailed:
            return "Failed to process image for printing."
        }
    }
}
