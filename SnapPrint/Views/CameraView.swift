import SwiftUI
import AVFoundation

// MARK: - CameraView

struct CameraView: View {

    let receiptId: String

    @StateObject private var viewModel = CameraViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera preview (chỉ show khi session ready)
            if viewModel.isCameraReady {
                CameraPreviewLayer(session: viewModel.session)
                    .ignoresSafeArea()
            } else {
                // Placeholder khi camera đang khởi động
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Đang khởi động camera...")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // UI overlays
            VStack {
                topBar
                Spacer()
                bottomControls
            }

            // Countdown
            if viewModel.countdownValue > 0 {
                CountdownOverlay(count: viewModel.countdownValue)
            }

            // Flash
            if viewModel.showFlash {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .onAppear  { viewModel.startSession() }
        .onDisappear { viewModel.stopSession() }
        .onChange(of: viewModel.navigateToPreview) { shouldNav in
            if shouldNav, let photo = viewModel.capturedPhoto {
                router.capturedImage = photo
                router.navigate(to: .photoPreview(receiptId: receiptId))
                viewModel.navigateToPreview = false
            }
        }
        .alert("Camera Error", isPresented: $viewModel.showError) {
            Button("OK") { dismiss() }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }

            Spacer()

            Text("Take Photo")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: { viewModel.flipCamera() }) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.isCameraReady ? .white : .white.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .disabled(!viewModel.isCameraReady)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 0) {
            // Receipt pill
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
                Text("Receipt: \(receiptId.isEmpty ? "—" : receiptId)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(.bottom, 32)

            // Shutter
            Button(action: { viewModel.startCountdown() }) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 88, height: 88)
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(viewModel.isCountingDown ? .white.opacity(0.6) : .white)
                        .frame(width: 64, height: 64)
                        .scaleEffect(viewModel.isCountingDown ? 0.85 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isCountingDown)
                }
            }
            .disabled(viewModel.isCountingDown || !viewModel.isCameraReady)
            .opacity(viewModel.isCameraReady ? 1 : 0.4)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - CameraViewModel

@MainActor
final class CameraViewModel: NSObject, ObservableObject {

    @Published var isCountingDown  = false
    @Published var countdownValue  = 0
    @Published var capturedPhoto: UIImage?
    @Published var navigateToPreview = false
    @Published var showFlash       = false
    @Published var isCameraReady   = false   // ← guard trước khi capture
    @Published var showError       = false
    @Published var errorMessage    = ""

    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var countdownTask: Task<Void, Never>?

    // MARK: - Session lifecycle

    func startSession() {
        Task {
            await requestPermissionAndConfigure()
        }
    }

    func stopSession() {
        Task.detached(priority: .background) { [session] in
            if session.isRunning { session.stopRunning() }
        }
        isCameraReady = false
    }

    // MARK: - Permission + configure (on background thread)

    private func requestPermissionAndConfigure() async {
        // Xin permission nếu chưa có
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                errorMessage = "Camera bị từ chối. Vào Settings → SnapPrint → Camera để bật."
                showError = true
                return
            }
        } else if status == .denied || status == .restricted {
            errorMessage = "Camera bị từ chối. Vào Settings → SnapPrint → Camera để bật."
            showError = true
            return
        }

        // Configure session trên background thread
        let pos = currentCameraPosition
        let (configured, output) = await Task.detached(priority: .userInitiated) { [weak self] () -> (Bool, AVCapturePhotoOutput?) in
            guard let self else { return (false, nil) }
            return self.buildSession(position: pos)
        }.value

        if configured, let output {
            self.photoOutput = output
            // Start running trên background
            await Task.detached(priority: .userInitiated) { [session] in
                if !session.isRunning { session.startRunning() }
            }.value
            self.isCameraReady = true
        } else {
            // Simulator hoặc không có camera → dùng mock photo
            self.isCameraReady = true   // vẫn cho bấm shutter để test UI
        }
    }

    /// Chạy trên background thread – trả về (success, photoOutput)
    nonisolated private func buildSession(position: AVCaptureDevice.Position) -> (Bool, AVCapturePhotoOutput?) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // Remove old inputs
        session.inputs.forEach  { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        // Find camera
        guard let device = bestCamera(position: position),
              let input  = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return (false, nil)
        }
        session.addInput(input)

        // Add photo output
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else { return (false, nil) }
        session.addOutput(output)

        return (true, output)
    }

    nonisolated private func bestCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }

    // MARK: - Flip Camera

    func flipCamera() {
        currentCameraPosition = currentCameraPosition == .back ? .front : .back
        isCameraReady = false
        let pos = currentCameraPosition
        Task {
            let (ok, output) = await Task.detached(priority: .userInitiated) { [weak self] () -> (Bool, AVCapturePhotoOutput?) in
                guard let self else { return (false, nil) }
                return self.buildSession(position: pos)
            }.value
            if ok, let output { self.photoOutput = output }
            isCameraReady = true
        }
    }

    // MARK: - Countdown

    func startCountdown() {
        guard !isCountingDown else { return }
        countdownTask?.cancel()
        countdownTask = Task { await runCountdown() }
    }

    private func runCountdown() async {
        isCountingDown = true
        for i in stride(from: AppConfig.countdownSeconds, through: 1, by: -1) {
            guard !Task.isCancelled else { break }
            countdownValue = i
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        countdownValue  = 0
        isCountingDown  = false
        guard !Task.isCancelled else { return }
        capturePhoto()
    }

    // MARK: - Capture

    func capturePhoto() {
        // Simulator hoặc không có kết nối thật → dùng mock image
        guard !photoOutput.connections.isEmpty else {
            useMockPhoto()
            return
        }

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Mock photo cho simulator / không có camera
    private func useMockPhoto() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 576, height: 750))
        let mockImage = renderer.image { ctx in
            // Background gradient
            let colors = [UIColor(red: 0.1, green: 0.05, blue: 0.2, alpha: 1),
                          UIColor(red: 0.05, green: 0.1, blue: 0.3, alpha: 1)]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors.map(\.cgColor) as CFArray,
                                      locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient,
                                             start: .zero,
                                             end: CGPoint(x: 0, y: 750),
                                             options: [])
            // Label
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 40),
                .foregroundColor: UIColor.white
            ]
            let text = "📸 MOCK PHOTO"
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (576 - size.width) / 2,
                                                y: (750 - size.height) / 2),
                                   withAttributes: attrs)
        }
        Task { @MainActor in
            self.showFlash = true
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.showFlash = false
            self.capturedPhoto     = mockImage
            self.navigateToPreview = true
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data  = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        Task { @MainActor in
            self.showFlash = true
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.showFlash         = false
            self.capturedPhoto     = image
            self.navigateToPreview = true
        }
    }
}
