import LingpaoCore
import SwiftUI

/// 零跑智控 iOS 原生重构版主入口
@main
struct LingpaoApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootContentView(viewModel: viewModel)
                .preferredColorScheme(viewModel.appearance.colorScheme)
                .task {
                    await viewModel.bootstrap()
                }
        }
    }
}

private struct RootContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.session.isLoggedIn || viewModel.isDemoMode {
                MainShellView(viewModel: viewModel)
                    .transition(.opacity)
            } else {
                LoginView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.session.isLoggedIn || viewModel.isDemoMode)
    }
}
