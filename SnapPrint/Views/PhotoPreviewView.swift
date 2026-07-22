import SwiftUI

/// Screen 3: Photo preview with Print and Cancel buttons.
/// Shows the captured photo and allows printing or retaking.
struct PhotoPreviewView: View {

    let image: UIImage
    let receiptId: String

    @StateObject private var viewModel = PhotoPreviewViewModel()
    @State private var composedPreview: UIImage? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                Spacer(minLength: 16)

                photoFrame

                Spacer(minLength: 16)

                actionButtons
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 0)
        }
        .navigationBarHidden(true)
        .statusBarHidden(false)
        .onAppear { viewModel.image = image }
        .task {
            let raw = image
            let result = await Task.detached(priority: .userInitiated) {
                ImageProcessor.shared.processForThermalPrint(raw)
            }.value
            if let result = result {
                withAnimation(.easeIn(duration: 0.35)) {
                    composedPreview = result
                }
            }
        }
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
            Spacer()
            Text("Preview")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    // MARK: - Photo Frame

    private var photoFrame: some View {
        GeometryReader { geo in
            let availableWidth  = geo.size.width - 48
            let availableHeight = geo.size.height - 16
            let aspectRatio: CGFloat = 1.42

            // Dynamic aspect-fit size calculation to prevent overflowing screens on iPad
            let size: CGSize = {
                if availableWidth * aspectRatio > availableHeight {
                    let h = availableHeight
                    let w = h / aspectRatio
                    return CGSize(width: w, height: h)
                } else {
                    let w = availableWidth
                    let h = w * aspectRatio
                    return CGSize(width: w, height: h)
                }
            }()

            let frameWidth  = size.width
            let frameHeight = size.height

            ZStack(alignment: .topTrailing) {
                if let preview = composedPreview {
                    // Cached result — no recompute on layout pass
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(width: frameWidth, height: frameHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.55), radius: 28, x: -4, y: 10)
                        .shadow(color: Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.25), radius: 16, x: 0, y: 4)
                        .rotationEffect(.degrees(-1.8))
                } else {
                    // Skeleton while processing on background thread
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.06))
                        .frame(width: frameWidth, height: frameHeight)
                        .overlay(ProgressView().tint(.white).scaleEffect(1.4))
                        .rotationEffect(.degrees(-1.8))
                }

                // Ready badge — show once preview is loaded and idle
                if viewModel.printState == .idle, composedPreview != nil {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Ready")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.1, green: 0.55, blue: 0.3).opacity(0.92))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    )
                    .offset(x: -18, y: 18)   // inside top-right of frame
                    .zIndex(10)
                }

                // Print processing overlay
                if viewModel.printState == .processing {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.black.opacity(0.6))
                        .frame(width: frameWidth, height: frameHeight)
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
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .rotationEffect(.degrees(-1.8))
                }

                if viewModel.printState == .printing {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.black.opacity(0.6))
                        .frame(width: frameWidth, height: frameHeight)
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
                                    .onAppear  { viewModel.printerIconPulse = true  }
                                    .onDisappear { viewModel.printerIconPulse = false }
                                Text("Printing...")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .rotationEffect(.degrees(-1.8))
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

    @State private var saveState: SaveState = .idle

    private enum SaveState {
        case idle, saving, saved, failed(String)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Retake
            Button(action: { dismiss() }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Retake")
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

            // Save
            Button(action: { Task { await saveImage() } }) {
                HStack(spacing: 8) {
                    if case .saving = saveState {
                        ProgressView().tint(.white)
                    } else if case .saved = saveState {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                        Text("Saved")
                            .font(.system(size: 16, weight: .semibold))
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.white.opacity(0.85))
                .background({
                    if case .saved = saveState {
                        return Color.green.opacity(0.4)
                    }
                    return Color.white.opacity(0.1)
                }())
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
            }
            .disabled(viewModel.isPrinting || {
                if case .saving = saveState { return true }
                return false
            }())

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
        .padding(.horizontal, 24)
    }

    private func saveImage() async {
        guard let sourceImage = viewModel.image ?? self.image as UIImage? else { return }
        saveState = .saving

        let finalImage = await Task.detached(priority: .userInitiated) {
            ImageProcessor.shared.processForThermalPrint(sourceImage)
        }.value

        guard let imageToSave = finalImage else {
            saveState = .failed("Processing failed")
            return
        }

        UIImageWriteToSavedPhotosAlbum(imageToSave, nil, nil, nil)
        withAnimation { saveState = .saved }

        // Reset after 2 seconds
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        withAnimation { saveState = .idle }
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
