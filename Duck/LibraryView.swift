import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Filter: Hashable {
        case recent, all, untagged, tag(String)

        var name: String {
            switch self {
            case .recent: "Recent"
            case .all: "All papers"
            case .untagged: "Untagged"
            case .tag(let tag): tag
            }
        }
    }

    enum Sheet: Identifiable {
        case tags(Set<String>), rename(String)
        var id: String {
            switch self {
            case .tags(let ids): "tags:" + ids.sorted().joined(separator: "|")
            case .rename(let id): "rename:" + id
            }
        }
    }

    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @State private var filter = Filter.all
    @State private var openPaper: String?
    @State private var selection = Set<String>()
    @State private var search = ""
    @State private var searching = false
    @State private var sheet: Sheet?
    @State private var importing = false
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @FocusState private var searchFocused: Bool

    private var visiblePapers: [Paper] {
        let papers = library.papers
        let filtered: [Paper] = switch filter {
        case .recent:
            Array(papers.filter { $0.meta.opened != nil }.sorted { $0.meta.opened! > $1.meta.opened! }.prefix(20))
        case .all: papers.sorted { $0.added > $1.added }
        case .untagged: papers.filter { $0.meta.tags.isEmpty }.sorted { $0.added > $1.added }
        case .tag(let tag): papers.filter { $0.meta.tags.contains(tag) }.sorted { $0.added > $1.added }
        }
        guard !search.isEmpty else { return filtered }
        return filtered.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.tagList.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar.frame(width: 230)
            }
            panel
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.leading, sidebarVisible ? 0 : 14)
                .padding([.trailing, .bottom], 14)
        }
        .foregroundStyle(Theme.text)
        .focusedSceneValue(\.find, openPaper == nil ? FindAction(name: "library") { searching = true; searchFocused = true } : nil)
        .toolbar(removing: .title)
        .toolbar { toolbar }
        .duckWindowStyle()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.add(urls) }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .tags(let ids):
                TagEditor(ids: ids)
            case .rename(let id):
                RenameSheet(id: id, title: (id as NSString).deletingPathExtension) { newID in
                    if openPaper == id { openPaper = newID }
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
        } message: {
            Text(library.lastError ?? "")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 10) {
                crumb("My Library") { filter = .all; openPaper = nil }
                Text("/").foregroundStyle(Theme.tertiary)
                crumb(filter.name) { openPaper = nil }
                    .keyboardShortcut("[", modifiers: .command)
                if let openPaper {
                    Text("/").foregroundStyle(Theme.tertiary)
                    Text((openPaper as NSString).deletingPathExtension)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 360, alignment: .leading)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.leading, 8)
        }
        .sharedBackgroundVisibility(.hidden)

        if openPaper == nil {
            ToolbarItem {
                Button { importing = true } label: { Label("Add paper", systemImage: "plus").labelStyle(.titleAndIcon) }
                    .buttonStyle(PillButtonStyle())
                    .help("Add PDFs to the library (⌘O)")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                if searching {
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .padding(.horizontal, 12)
                        .frame(width: 200, height: 32)
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1.5))
                        .onExitCommand { search = ""; searching = false }
                        .onAppear { searchFocused = true }
                } else {
                    Button { searching = true } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(CircleButtonStyle())
                        .help("Search titles and tags (⌘F)")
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarItem {
            Button { withAnimation(.easeOut(duration: 0.2)) { sidebarVisible.toggle() } } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(CircleButtonStyle())
                .keyboardShortcut("s", modifiers: [.command, .control])
                .help("Show or hide the sidebar (⌃⌘S)")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private func crumb(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarRow(.recent)
            sidebarRow(.all, count: library.papers.count)

            Text("My library")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 22).padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarRow(.untagged, dot: Theme.tertiary, count: library.papers.count { $0.meta.tags.isEmpty })
                    ForEach(library.allTags, id: \.self) { tag in
                        sidebarRow(.tag(tag), dot: Theme.color(for: tag), count: library.papers.count { $0.meta.tags.contains(tag) })
                            .contextMenu {
                                Button("Remove Tag from All Papers") {
                                    if filter == .tag(tag) { filter = .all }
                                    library.removeTag(tag)
                                }
                            }
                    }
                }
            }
            .scrollIndicators(.never)

            Button { NSWorkspace.shared.open(library.folder) } label: {
                Label("Library folder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(Theme.secondary)
            .help(library.folder.path)
        }
        .padding(.leading, 26).padding(.trailing, 20).padding(.top, 8).padding(.bottom, 18)
    }

    private func sidebarRow(_ row: Filter, dot: Color? = nil, count: Int? = nil) -> some View {
        let selected = filter == row && openPaper == nil
        return Button {
            filter = row
            openPaper = nil
            selection = []
        } label: {
            HStack(spacing: 10) {
                if let dot { Circle().fill(dot).frame(width: 10, height: 10) }
                Text(row.name)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Theme.text : Theme.secondary)
                    .lineLimit(1)
                Spacer()
                if let count { Text("\(count)").monospacedDigit().foregroundStyle(Theme.tertiary) }
            }
            .font(.system(size: 14))
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Panel

    @ViewBuilder
    private var panel: some View {
        if let openPaper {
            ReaderView(id: openPaper).id(openPaper)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visiblePapers) { paper in
                        PaperRow(paper: paper, selected: selection.contains(paper.id))
                            .onTapGesture { tap(paper.id) }
                            .contextMenu { menu(for: selection.contains(paper.id) ? selection : [paper.id]) }
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { emptyState }
            .dropDestination(for: URL.self) { urls, _ in
                library.add(urls)
                return true
            }
            .onDeleteCommand { if !selection.isEmpty { library.trash(selection); selection = [] } }
        }
    }

    /// Click opens a paper here; ⌘-click selects several for tagging or trashing.
    private func tap(_ id: String) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = []
            openPaper = id
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first {
            Button("Open") { openPaper = id }
            Button("Open in New Window") { openWindow(value: id) }
        } else {
            Button("Open in New Windows") { ids.forEach { openWindow(value: $0) } }
        }
        Divider()
        Button(ids.count == 1 ? "Edit Tags…" : "Edit Tags for \(ids.count) Papers…") { sheet = .tags(ids) }
        if ids.count == 1, let id = ids.first {
            Button("Rename…") { sheet = .rename(id) }
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(ids.map(library.url(for:))) }
        Divider()
        Button("Move to Trash", role: .destructive) {
            library.trash(ids)
            selection.subtract(ids)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if visiblePapers.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: library.papers.isEmpty ? "doc.text" : "magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.tertiary)
                Text(emptyMessage)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var emptyMessage: String {
        if library.papers.isEmpty { return "Drag PDFs here to start your library" }
        if !search.isEmpty { return "No papers match “\(search)”" }
        return filter == .recent ? "Papers you open will show up here" : "No papers here yet"
    }
}

struct PaperRow: View {
    let paper: Paper
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(paper.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            HStack(spacing: 12) {
                ForEach(paper.meta.tags, id: \.self) { tag in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.color(for: tag)).frame(width: 7, height: 7)
                        Text(tag)
                    }
                }
                Text(paper.added, format: .dateTime.year().month().day())
                    .foregroundStyle(Theme.tertiary)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.selected : hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct TagEditor: View {
    let ids: Set<String>
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var initial = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ids.count == 1 ? "Tags" : "Tags for \(ids.count) papers").font(.headline)
            TextField("e.g. ml, to-read", text: $text)
                .frame(width: 320)
                .onSubmit(apply)
            Text(ids.count == 1 ? "Separate tags with commas." : "Shows tags all selected papers share. Other tags are kept.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear {
            let sets = ids.map { Set(library.meta[$0]?.tags ?? []) }
            initial = sets.dropFirst().reduce(sets.first ?? []) { $0.intersection($1) }
            text = initial.sorted().joined(separator: ", ")
        }
    }

    private func apply() {
        let tags = Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        library.updateTags(ids, adding: tags.subtracting(initial), removing: initial.subtracting(tags))
        dismiss()
    }
}

struct RenameSheet: View {
    let id: String
    @State var title: String
    var onRenamed: (String) -> Void = { _ in }
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename").font(.headline)
            TextField("Title", text: $title).frame(width: 360).onSubmit(apply)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func apply() {
        do {
            onRenamed(try library.rename(id, to: title))
            dismiss()
        } catch {
            Log.library.error("Rename of \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}
