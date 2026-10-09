import SwiftUI

@main
@MainActor
struct MetaRayRecorderApp: App {
    @StateObject private var model = RecorderModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RecorderView(model: model)
                .preferredColorScheme(.dark)
                .onOpenURL { url in Task { await model.handleURL(url) } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background || phase == .inactive { model.enteredBackground() }
                    else if phase == .active { model.enteredForeground() }
                }
        }
    }
}
