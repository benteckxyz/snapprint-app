import SwiftUI
import StarIO
import StarIO_Extension

// MARK: - ReceiptEntryView

struct ReceiptEntryView: View {

    @StateObject private var viewModel = ReceiptEntryViewModel()
    @FocusState  private var isInputFocused: Bool
    @EnvironmentObject private var router: AppRouter
    @State private var showAdminPanel   = false

    // 5-tap secret trigger
    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    private let maxLen = AppConfig.receiptCodeLength

    var body: some View {
        ZStack {
            // ── Background ───────────────────────────────────────────────
            backgroundGradient

            // ── Content ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                // Title
                Text("Input Receipt Number")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 40)

                // OTP Boxes
                otpBoxes
                    .padding(.bottom, 28)

                // Status feedback
                statusLine

                Spacer()
            }
            .padding(.horizontal, 28)

            // Hidden keyboard capture
            hiddenInput
        }
        // Catch ALL taps for 5-tap admin trigger
        .simultaneousGesture(TapGesture().onEnded { handleSecretTap() })
        .navigationBarHidden(true)
        .sheet(isPresented: $showAdminPanel) {
            AdminSettingsView()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
                clearAndRefocus()
            }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Already Printed", isPresented: $viewModel.showAlreadyPrinted) {
            Button("OK") {
                viewModel.showAlreadyPrinted = false
                clearAndRefocus()
            }
        } message: {
            Text("This receipt has already been printed.")
        }
        .onChange(of: viewModel.isVerified) { verified in
            if verified {
                router.navigate(to: .camera(receiptId: viewModel.validReceiptId ?? ""))
            }
        }
        .onAppear {
            viewModel.isVerified    = false
            viewModel.code          = ""
            viewModel.statusMessage = ""
            viewModel.hasError      = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isInputFocused = true
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.04, blue: 0.12),
                Color(red: 0.08, green: 0.06, blue: 0.18)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - OTP Boxes

    private var otpBoxes: some View {
        HStack(spacing: 10) {
            ForEach(0..<maxLen, id: \.self) { index in
                OTPBox(
                    character: character(at: index),
                    isActive: isInputFocused && index == viewModel.code.count && index < maxLen,
                    isFilled: index < viewModel.code.count,
                    isError: viewModel.hasError
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = true }
        .offset(x: viewModel.shakeOffset)
        // Loading spinner overlay
        .overlay(alignment: .bottom) {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white.opacity(0.7))
                        .scaleEffect(0.8)
                    Text("Verifying...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .offset(y: 40)
            }
        }
    }

    private func character(at index: Int) -> Character? {
        let code = viewModel.code
        guard index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }

    // MARK: - Hidden Input

    private var hiddenInput: some View {
        TextField("", text: $viewModel.code)
            .focused($isInputFocused)
            .keyboardType(.default)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.characters)
            .opacity(0)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .onChange(of: viewModel.code) { val in
                // Filter + uppercase + limit length
                let filtered = String(val.uppercased()
                    .filter { $0.isLetter || $0.isNumber }
                    .prefix(maxLen))
                if viewModel.code != filtered {
                    viewModel.code = filtered
                    return
                }
                // Reset error state when user types
                if viewModel.hasError {
                    viewModel.hasError    = false
                    viewModel.statusMessage = ""
                }
                // Auto-verify when all boxes are filled
                if filtered.count == maxLen && !viewModel.isLoading {
                    isInputFocused = false
                    viewModel.verify()
                }
            }
    }

    // MARK: - Status Line

    @ViewBuilder
    private var statusLine: some View {
        if !viewModel.statusMessage.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: viewModel.hasError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13))
                Text(viewModel.statusMessage)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(viewModel.hasError
                ? Color(red: 1, green: 0.35, blue: 0.35)
                : Color(red: 0.3,  green: 1,   blue: 0.55))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.spring(duration: 0.3), value: viewModel.statusMessage)
        }
    }

    // MARK: - Helpers

    private func clearAndRefocus() {
        viewModel.code        = ""
        viewModel.hasError    = false
        viewModel.statusMessage = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isInputFocused = true
        }
    }

    // MARK: - 5-tap Admin Trigger

    private func handleSecretTap() {
        tapResetTask?.cancel()
        tapCount += 1
        if tapCount >= 5 {
            tapCount = 0
            showAdminPanel = true
            return
        }
        tapResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            tapCount = 0
        }
    }
}

// MARK: - OTP Box Component

private struct OTPBox: View {
    let character: Character?
    let isActive:  Bool
    let isFilled:  Bool
    let isError:   Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.11, green: 0.09, blue: 0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .frame(width: boxSize, height: boxSize * 1.25)

            if let char = character {
                Text(String(char))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(isError ? Color(red: 1, green: 0.45, blue: 0.45) : .white)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(duration: 0.2), value: character != nil)
            } else if isActive {
                CursorView()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: isFilled)
        .animation(.easeInOut(duration: 0.15), value: isError)
    }

    private var boxSize: CGFloat {
        let screen       = UIScreen.main.bounds.width
        let totalSpacing = CGFloat(AppConfig.receiptCodeLength - 1) * 10 + 56
        return min(54, (screen - totalSpacing) / CGFloat(AppConfig.receiptCodeLength))
    }

    private var borderColor: Color {
        if isError   { return Color(red: 1, green: 0.35, blue: 0.35).opacity(0.8) }
        if isActive  { return Color(red: 0.55, green: 0.35, blue: 1.0) }
        if isFilled  { return .white.opacity(0.45) }
        return .white.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        isActive || isError ? 2 : 1
    }
}

// MARK: - Blinking Cursor

private struct CursorView: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color(red: 0.55, green: 0.35, blue: 1.0))
            .frame(width: 2, height: 30)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) {
                    visible = false
                }
            }
    }
}

// MARK: - Admin Settings View

struct AdminSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var backendURL  = AppConfig.backendBaseURL
    @State private var printerPort = AppConfig.printerPortName
    @State private var apiKey      = AppConfig.apiKey
    @State private var beastMode   = AppConfig.beastMode
    @State private var footerLine1 = AppConfig.footerLine1
    @State private var footerLine2 = AppConfig.footerLine2
    @State private var selectedFrameStyle = AppConfig.frameStyle

    // Discovery State
    @State private var discoveredPrinters: [PortInfo] = []
    @State private var isSearching = false
    @State private var searchError: String? = nil

    // Diagnostic State
    @State private var isTesting = false
    @State private var testResult: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode Configuration") {
                    Toggle("Beast Mode", isOn: $beastMode)
                    Text("If enabled, the app skips receipt code verification and goes straight to the camera screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Print Frame Template") {
                    Picker("Template Style", selection: $selectedFrameStyle) {
                        ForEach(AppConfig.FrameStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(selectedFrameStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Print Footer Text") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Line 1 (Title)").font(.caption).foregroundStyle(.secondary)
                        TextField("Thanks for using", text: $footerLine1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Line 2 (Subtitle)").font(.caption).foregroundStyle(.secondary)
                        TextField("SnapPrint ✦", text: $footerLine2)
                    }
                }

                Section("Backend") {
                    TextField("https://print.thevietlab.com", text: $backendURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("X-API-Key (secret)", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Printer Port Selection") {
                    TextField("USB:Star mC-Print3", text: $printerPort)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Selected Port: \(printerPort.isEmpty ? "None" : printerPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Printer Discovery") {
                    Button(action: runPrinterDiscovery) {
                        HStack {
                            if isSearching {
                                ProgressView()
                                    .tint(.blue)
                                    .padding(.trailing, 8)
                                Text("Searching...")
                            } else {
                                Image(systemName: "magnifyingglass")
                                Text("Search Connected Printers")
                            }
                        }
                    }
                    .disabled(isSearching)

                    if !discoveredPrinters.isEmpty {
                        ForEach(discoveredPrinters, id: \.portName) { printer in
                            Button(action: {
                                printerPort = printer.portName ?? ""
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(printer.modelName ?? "Unknown Star Printer")
                                            .font(.body)
                                            .foregroundStyle(.white)
                                        Text("Port: \(printer.portName ?? "Unknown")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if printerPort == (printer.portName ?? "") {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                            .fontWeight(.bold)
                                    }
                                }
                            }
                        }
                    } else if let errorMsg = searchError {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Tap Search to detect USB, Bluetooth, or LAN printers automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("🔧 Diagnostic") {
                    Button {
                        isTesting = true
                        testResult = nil
                        Task {
                            let result = await PrinterService.shared.testPrint()
                            testResult = result
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "printer.dotmatrix")
                            Text("Test Print (All Emulations)")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    Text("Gửi text đơn giản bằng TẤT CẢ emulation modes. Mode nào đúng sẽ in ra giấy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("App Info") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Bundle",  value: Bundle.main.bundleIdentifier ?? "xyz.benteck.snapprint")
                    LabeledContent("Printer", value: "Star mC-Print3 (mCP31Ci)")
                    LabeledContent("Paper",   value: "80mm · 203 DPI")
                }
            }
            .navigationTitle("Admin Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        AppConfig.backendBaseURL  = backendURL
                        AppConfig.printerPortName = printerPort
                        AppConfig.apiKey          = apiKey
                        AppConfig.beastMode       = beastMode
                        AppConfig.footerLine1     = footerLine1
                        AppConfig.footerLine2     = footerLine2
                        AppConfig.frameStyle      = selectedFrameStyle
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func runPrinterDiscovery() {
        isSearching = true
        searchError = nil
        discoveredPrinters = []

        DispatchQueue.global(qos: .userInitiated).async {
            var allPrinters: [PortInfo] = []

            do {
                // "ALL:" is the unified SDK search target for USB, Bluetooth, and Ethernet
                if let found = try SMPort.searchPrinter(target: "ALL:") as? [PortInfo] {
                    allPrinters = found
                }
            } catch {
                print("DEBUG: Printer discovery searchPrinter('ALL:') failed with error: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.discoveredPrinters = allPrinters
                self.isSearching = false
                if allPrinters.isEmpty {
                    self.searchError = "No printers found. Ensure the printer is turned on, MFi cable is connected to the 'iPad' port, and other printer apps are closed."
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ReceiptEntryViewModel: ObservableObject {

    @Published var code               = ""
    @Published var isLoading          = false
    @Published var isVerified         = false
    @Published var showError          = false
    @Published var showAlreadyPrinted = false
    @Published var errorMessage       = ""
    @Published var statusMessage      = ""
    @Published var hasError           = false
    @Published var shakeOffset: CGFloat = 0

    var validReceiptId: String?

    func verify() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { await checkReceipt(code: trimmed) }
    }

    private func checkReceipt(code: String) async {
        isLoading   = true
        hasError    = false
        statusMessage = ""
        defer { isLoading = false }

        do {
            let result = try await SquareAPIService.shared.checkReceipt(code: code)

            if !result.exists {
                hasError      = true
                statusMessage = "Receipt not found — please try again"
                triggerShakeAndClear()
            } else if result.printed {
                showAlreadyPrinted = true
            } else {
                validReceiptId = result.receiptId
                statusMessage  = "Verified ✓"
                hasError       = false
                try? await Task.sleep(nanoseconds: 350_000_000)
                isVerified = true
            }
        } catch {
            errorMessage  = error.localizedDescription
            showError     = true
            hasError      = true
            statusMessage = "Connection failed"
            triggerShake()
        }
    }

    /// Shake + auto-clear code after animation
    private func triggerShakeAndClear() {
        triggerShake()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.code = ""
            }
        }
    }

    private func triggerShake() {
        let keyframes: [CGFloat] = [-10, 10, -7, 7, -4, 4, 0]
        for (i, offset) in keyframes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(.easeInOut(duration: 0.05)) {
                    self.shakeOffset = offset
                }
            }
        }
    }
}

#Preview {
    ReceiptEntryView()
        .environmentObject(AppRouter())
}
