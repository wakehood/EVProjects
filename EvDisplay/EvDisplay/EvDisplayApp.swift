import SwiftUI

@main
struct EvDisplayApp: App {
    @State private var showLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                if showLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeOut(duration: 0.7)) {
                        showLaunchScreen = false
                    }
                }
            }
        }
    }
}
