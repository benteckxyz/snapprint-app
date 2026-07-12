import SwiftUI

/// Animated 3-2-1 countdown overlay shown over the camera before capture.
struct CountdownOverlay: View {

    let count: Int

    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            if count > 0 {
                ZStack {
                    // Pulsing ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.3, blue: 1.0),
                                    Color(red: 0.3, green: 0.6, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(scale)
                        .opacity(opacity)

                    // Number
                    Text("\(count)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.8, green: 0.7, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.purple.opacity(0.6), radius: 20)
                        .scaleEffect(scale * 0.85)
                        .opacity(opacity)
                }
                .id(count) // Force re-animation on count change
                .onAppear { animate() }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: count)
    }

    private func animate() {
        scale = 1.4
        opacity = 0

        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
        }

        // Fade out near end of second
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeIn(duration: 0.25)) {
                opacity = 0.3
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CountdownOverlay(count: 3)
    }
}
