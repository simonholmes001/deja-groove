import SwiftUI
import DejaGrooveApp

struct AuthGateView<Content: View>: View {
    @ObservedObject var coordinator: AppAuthCoordinator
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if coordinator.requiresSignIn {
                VStack(spacing: 16) {
                    Text("Deja Groove")
                        .font(.title2)
                    Text("Sign in to start scanning your collection.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let error = coordinator.lastError {
                        Text(error.message)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.red)
                    }
                    Button("Sign In") {
                        Task { await coordinator.signInInteractively() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.isSigningIn)
                }
                .padding(24)
                .task { coordinator.bootstrap() }
            } else {
                content
                    .task {
                        await coordinator.refreshAuthenticationState()
                    }
            }
        }
    }
}
