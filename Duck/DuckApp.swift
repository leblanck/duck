import SwiftUI
import UniformTypeIdentifiers

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
        .commands { ReaderCommands(library: library) }
    }
}

struct ReaderCommands: Commands {
    let library: Library
    @FocusedValue(\.reader) private var reader
    @FocusedValue(\.find) private var find

    var body: some Commands {
        // Replaces File > New Paper Window, which SwiftUI adds for the paper WindowGroup but can't open without a paper.
        CommandGroup(replacing: .newItem) {
            Button("Add PDF…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.pdf]
                panel.allowsMultipleSelection = true
                if panel.runModal() == .OK { library.add(panel.urls) }
            }
            .keyboardShortcut("o")
        }
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
