import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Filter: Hashable {
        case all, untagged, tag(String)
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
    @State private var filter: Filter? = .all
    @State private var selection = Set<String>()
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\Paper.added, order: .reverse)]
    @State private var sheet: Sheet?
    @State private var importing = false

    private var visiblePapers: [Paper] {
        library.papers.filter { paper in
            switch filter ?? .all {
            case .all: true
            case .untagged: paper.meta.tags.isEmpty
            case .tag(let tag): paper.meta.tags.contains(tag)
            }
        }
        .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.tagList.localizedCaseInsensitiveContains(search) }
        .sorted(using: sortOrder)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Label("All Papers", systemImage: "doc.on.doc").tag(Filter.all)
                Label("Untagged", systemImage: "doc").tag(Filter.untagged)
                if !library.allTags.isEmpty {
                    Section("Tags") {
                        ForEach(library.allTags, id: \.self) { tag in
                            Label(tag, systemImage: "tag").tag(Filter.tag(tag))
                                .contextMenu {
                                    Button("Remove Tag from All Papers") {
                                        if filter == .tag(tag) { filter = .all }
                                        library.removeTag(tag)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            table
        }
        .searchable(text: $search, prompt: "Search titles and tags")
        .toolbar {
            Button { importing = true } label: { Label("Add Papers", systemImage: "plus") }
                .keyboardShortcut("o")
                .help("Add PDFs to the library (⌘O)")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.add(urls) }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .tags(let ids): TagEditor(ids: ids)
            case .rename(let id): RenameSheet(id: id, title: (id as NSString).deletingPathExtension)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
        } message: {
            Text(library.lastError ?? "")
        }
    }

    private var table: some View {
        Table(visiblePapers, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title)
            TableColumn("Tags", value: \.tagList) { Text($0.tagList).foregroundStyle(.secondary) }
                .width(ideal: 160)
            TableColumn("Added", value: \.added) { Text($0.added, format: .dateTime.year().month().day()) }
                .width(ideal: 100)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button("Open") { ids.forEach { openWindow(value: $0) } }
                Button("Edit Tags…") { sheet = .tags(ids) }
                if ids.count == 1, let id = ids.first {
                    Button("Rename…") { sheet = .rename(id) }
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(ids.map(library.url(for:))) }
                Divider()
                Button("Move to Trash", role: .destructive) { library.trash(ids) }
            }
        } primaryAction: { ids in
            ids.forEach { openWindow(value: $0) }
        }
        .onDeleteCommand { library.trash(selection) }
        .dropDestination(for: URL.self) { urls, _ in
            library.add(urls)
            return true
        }
        .overlay {
            if library.papers.isEmpty {
                ContentUnavailableView("No papers yet", systemImage: "doc.text",
                                       description: Text("Drag PDFs here, or press ⌘O."))
            } else if visiblePapers.isEmpty {
                ContentUnavailableView.search
            }
        }
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
            try library.rename(id, to: title)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
