import SwiftUI

struct LaunchScreenView: View {
    @State private var opacity = 0.0
    @State private var scale = 0.88

    var body: some View {
        ZStack {
            // Dark gradient background — matches the EV/tech aesthetic
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.14),
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.45), radius: 28, x: 0, y: 10)

                VStack(spacing: 10) {
                    Text("EvDisplay")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("by Dilithium Design")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                        .tracking(1.0)
                }
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                    opacity = 1.0
                    scale = 1.0
                }
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
