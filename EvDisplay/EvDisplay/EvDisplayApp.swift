import SwiftUI
import UIKit

private let launchColor = UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 1)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Paint the window dark immediately so there is no white flash before SwiftUI renders.
        application.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.backgroundColor = launchColor }
        return true
    }
}

@main
struct EvDisplayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var showLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 0.04, green: 0.07, blue: 0.14)
                    .ignoresSafeArea()
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
