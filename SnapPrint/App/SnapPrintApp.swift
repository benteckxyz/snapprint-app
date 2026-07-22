import SwiftUI

// MARK: - Navigation Destinations

enum AppDestination: Hashable {
    case camera(receiptId: String)
    case photoPreview(receiptId: String)
}

// MARK: - AppRouter

/// Central navigation controller — owns the NavigationPath so popToRoot() works from anywhere.
final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()

    /// Stored here because UIImage isn't Hashable (can't go in NavigationPath directly).
    var capturedImage: UIImage?

    func navigate(to destination: AppDestination) {
        path.append(destination)
    }

    func popToRoot() {
        path = NavigationPath()
        capturedImage = nil
    }
}

// MARK: - App Entry Point

@main
struct SnapPrintApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var router: AppRouter
    @AppStorage("snapprint_beastMode") private var beastMode = false

    var body: some View {
        NavigationStack(path: $router.path) {
            if beastMode {
                CameraView(receiptId: "BEAST_MODE")
                    .navigationDestination(for: AppDestination.self) { destination in
                        switch destination {
                        case .camera(let receiptId):
                            CameraView(receiptId: receiptId)
                        case .photoPreview(let receiptId):
                            if let image = router.capturedImage {
                                PhotoPreviewView(image: image, receiptId: receiptId)
                            }
                        }
                    }
            } else {
                ReceiptEntryView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        switch destination {
                        case .camera(let receiptId):
                            CameraView(receiptId: receiptId)
                        case .photoPreview(let receiptId):
                            if let image = router.capturedImage {
                                PhotoPreviewView(image: image, receiptId: receiptId)
                            }
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
    }
}
