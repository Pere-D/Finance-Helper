import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    @State private var fillAmount: Double = 0
    @State private var textOpacity: Double = 0
    @State private var screenOpacity: Double = 1
    @State private var logoScale: Double = 0.75

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo with liquid fill effect
                ZStack {
                    // Ghost outline (faded)
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .opacity(0.08)

                    // Full-color logo revealed bottom-to-top
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .mask(
                            GeometryReader { geo in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    Rectangle()
                                        .frame(height: geo.size.height * fillAmount)
                                }
                            }
                        )

                    // Subtle border ring
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                        .frame(width: 110, height: 110)
                }
                .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 8)
                .scaleEffect(logoScale)

                VStack(spacing: 6) {
                    Text("Finance Helper")
                        .font(.title2.weight(.bold))
                    Text(NSLocalizedString("app_tagline", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(textOpacity)
            }
        }
        .opacity(screenOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.75)) {
                logoScale = 1.0
            }
            withAnimation(.easeInOut(duration: 1.1).delay(0.15)) {
                fillAmount = 1.0
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.7)) {
                textOpacity = 1.0
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1900))
                withAnimation(.easeOut(duration: 0.35)) { screenOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(350))
                onComplete()
            }
        }
    }
}

#Preview {
    SplashView {}
}
