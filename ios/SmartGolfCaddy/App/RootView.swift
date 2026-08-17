import GoogleSignIn
import SwiftUI

struct RootView: View {
    @State private var session = SessionViewModel()

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                AuthView()
            case .signedIn:
                HomePlaceholderView()
            }
        }
        .environment(session)
        .task { session.start() }
        .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
    }
}
