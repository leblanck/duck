import SwiftUI

@main
struct DuckApp: App {
    @State private var library = Library()

    var body: some Scene {
        Window("Library", id: "library") {
            LibraryView().environment(library)
        }
        .defaultSize(width: 1100, height: 800)
        .windowToolbarStyle(.unified)

        WindowGroup("Paper", for: String.self) { $id in
            if let id {
                ReaderView(id: id)
                    .environment(library)
                    .duckWindowStyle()
            }
        }
        .defaultSize(width: 850, height: 1050)
    }
}
