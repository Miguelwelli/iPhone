import SwiftUI

@main
struct TesteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Color.white
            .ignoresSafeArea()
    }
}
