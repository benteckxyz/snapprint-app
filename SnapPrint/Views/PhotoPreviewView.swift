import SwiftUI

/// Screen 3: Photo preview with Print and Cancel buttons.
/// Shows the captured photo and allows printing or retaking.
struct PhotoPreviewView: View {

    let image: UIImage
    let receiptId: String

    @StateObject private var viewModel = PhotoPreviewViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 8)

                Spacer(minLength: 20)

                // Photo frame
                photoFrame

                Spacer(minLength: 20)

                // Print state info
                printStatusLabel

                // Action buttons
                actionButtons
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarHidden(true)
        .statusBarHidden(false)
        .onAppear { viewModel.image = image }
        .alert("Print Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.printState) { state in
            if case .success = state { router.popToRoot() }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.06, blue: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Retake")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.white.opacity(0.1), in: Capsule())
            }

            Spacer()

            Text("Preview")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            // Spacer to balance layout
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Retake")
                    .font(.system(size: 15, weight: .semibold))
            }
            .opacity(0) // Hidden spacer for centering
        }
    }

    // MARK: - Photo Frame

    private var photoFrame: some View {
        GeometryReader { geo in
            let maxWidth   = min(geo.size.width, 360.0)
            // Composed image aspect: photo + footer (~18% extra height)
            let frameSize  = CGSize(width: maxWidth, height: maxWidth * 1.42)

            // Build composed preview (same as what will be printed)
            let composed = ImageProcessor.shared.composeLayout(photo: image)

            ZStack {
                // Outer glow
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: frameSize.width + 20, height: frameSize.height + 20)
                    .blur(radius: 20)

                // Composed print preview
                Image(uiImage: composed)
                    .resizable()
                    .scaledToFit()
                    .frame(width: frameSize.width, height: frameSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                // Print processing overlay
                if viewModel.printState == .processing {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.black.opacity(0.6))
                        .frame(width: frameSize.width, height: frameSize.height)
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.5)
                                Text("Optimizing for\nthermal printing...")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                if viewModel.printState == .printing {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.black.opacity(0.6))
                        .frame(width: frameSize.width, height: frameSize.height)
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "printer.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color(red: 0.6, green: 0.4, blue: 1.0))
                                    .scaleEffect(viewModel.printerIconPulse ? 1.2 : 0.9)
                                    .animation(
                                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                                        value: viewModel.printerIconPulse
                                    )
                                    .onAppear { viewModel.printerIconPulse = true }
                                    .onDisappear { viewModel.printerIconPulse = false }
                                Text("Printing...")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    // MARK: - Print Status Label

    @ViewBuilder
    private var printStatusLabel: some View {
        switch viewModel.printState {
        case .idle:
            receiptPill
        case .processing:
            statusPill(text: "Preparing image...", color: .orange, icon: "gearshape")
        case .printing:
            statusPill(text: "Sending to printer...", color: .blue, icon: "printer")
        case .success:
            statusPill(text: "Printed successfully!", color: .green, icon: "checkmark.circle")
        case .failed(let msg):
            statusPill(text: msg, color: .red, icon: "exclamationmark.triangle")
        }
    }

    private var receiptPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13))
            Text("Ready to print")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
        .padding(.bottom, 16)
    }

    private func statusPill(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: Capsule())
        .padding(.bottom, 16)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Cancel / Retake
            Button(action: { dismiss() }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.white.opacity(0.85))
                .background(.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
            }
            .disabled(viewModel.isPrinting)

            // Print
            Button(action: { Task { await viewModel.print(receiptId: receiptId) } }) {
                HStack(spacing: 8) {
                    if viewModel.isPrinting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "printer.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Print")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: viewModel.isPrinting
                            ? [.gray.opacity(0.4)]
                            : [Color(red: 0.5, green: 0.3, blue: 1.0), Color(red: 0.2, green: 0.5, blue: 1.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.purple.opacity(0.5), radius: 12, y: 4)
                .scaleEffect(viewModel.isPrinting ? 0.97 : 1.0)
                .animation(.spring(response: 0.2), value: viewModel.isPrinting)
            }
            .disabled(viewModel.isPrinting)
        }
    }

    // navigateBackToStart() removed — using router.popToRoot() instead
}

// MARK: - ViewModel

@MainActor
final class PhotoPreviewViewModel: ObservableObject {

    @Published var printState: PrintState = .idle
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var printerIconPulse: Bool = false

    var image: UIImage?

    var isPrinting: Bool {
        switch printState {
        case .processing, .printing: return true
        default: return false
        }
    }

    func print(receiptId: String) async {
        guard let sourceImage = image else { return }

        // Step 1: Optimize image
        printState = .processing
        let processedOptional = await Task.detached(priority: .userInitiated) {
            ImageProcessor.shared.processForThermalPrint(sourceImage)
        }.value
        guard let processedImage = processedOptional else {
            printState = .failed("Image processing failed")
            errorMessage = "Could not prepare image for printing."
            showError = true
            return
        }

        // Step 2: Send to printer
        printState = .printing
        do {
            try await PrinterService.shared.printImage(processedImage)

            // Step 3: Mark as printed in backend
            if !receiptId.isEmpty {
                _ = try? await SquareAPIService.shared.markAsPrinted(receiptId: receiptId)
            }

            printState = .success
            // auto-navigate back — no popup

        } catch {
            printState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
