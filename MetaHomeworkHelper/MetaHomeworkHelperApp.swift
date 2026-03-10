import SwiftUI
import MWDATCore

@main
struct MetaHomeworkHelperApp: App {
    init() {
        try? Wearables.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        try? await Wearables.shared.handleUrl(url)
                    }
                }
        }
    }
}
