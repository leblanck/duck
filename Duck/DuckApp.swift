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
        .commands { ReaderCommands() }
    }
}

struct ReaderCommands: Commands {
    @FocusedValue(\.reader) private var reader
    @FocusedValue(\.find) private var find

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find…") { find?.run() }
                .keyboardShortcut("f")
                .disabled(find == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Zoom In") { reader?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(reader == nil)
            Button("Zoom Out") { reader?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(reader == nil)
            Button("Fit Width") { reader?.fitWidth() }
                .keyboardShortcut("0")
                .disabled(reader == nil)
            Divider()
        }
    }
}
