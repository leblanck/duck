import PDFKit
import SwiftUI

struct ReaderView: View {
    let id: String
    @Environment(Library.self) private var library
    @AppStorage("pageColor") private var pageColor = PageColor.tan
    @State private var document: PDFDocument?
    @State private var failed = false
    @State private var controller = ReaderController()
    @State private var saveError: String?
    @State private var choosingColor = false

    var body: some View {
        Group {
            if let document {
                PDFKitView(document: document, pageColor: pageColor,
                           startPage: library.meta[id]?.lastPage ?? 0, controller: controller)
            } else if failed {
                ContentUnavailableView("Couldn't open this PDF", systemImage: "exclamationmark.triangle",
                                       description: Text(id))
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .navigationTitle((id as NSString).deletingPathExtension)
        .toolbar {
            ToolbarItem {
                Button { choosingColor.toggle() } label: { Image(systemName: "circle.lefthalf.filled") }
                    .buttonStyle(CircleButtonStyle())
                    .help("Page color")
                    .popover(isPresented: $choosingColor, arrowEdge: .bottom) { colorPicker }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                Button(action: highlight) { Image(systemName: "highlighter") }
                    .buttonStyle(CircleButtonStyle())
                    .keyboardShortcut("h", modifiers: [.command, .control])
                    .help("Highlight selected text, or remove highlights it overlaps (⌃⌘H)")
                    .disabled(document == nil)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .alert("Couldn't save highlight", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
        } message: {
            Text(saveError ?? "")
        }
        .task(id: id) {
            let url = library.url(for: id)
            await Library.download(url)
            document = PDFDocument.tinted(url: url)
            failed = document == nil
            controller.pageChanged = { [library, id] page in library.setLastPage(id, page) }
            if document != nil { library.markOpened(id) }
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 14) {
            ForEach(PageColor.allCases) { color in
                Button {
                    pageColor = color
                    choosingColor = false
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: color.paper.r, green: color.paper.g, blue: color.paper.b))
                            .overlay(Text("Aa").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(red: color.ink.r, green: color.ink.g, blue: color.ink.b)))
                            .overlay(Circle().strokeBorder(color == pageColor ? Theme.accent : Theme.stroke,
                                                           lineWidth: color == pageColor ? 2 : 1))
                            .frame(width: 34, height: 34)
                        Text(color.name).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    private func highlight() {
        guard let document else { return }
        let pages = controller.toggleHighlight()
        guard !pages.isEmpty else { return }
        let url = library.url(for: id)
        // If the paper was renamed or deleted while open, don't recreate it under the old name.
        guard FileManager.default.fileExists(atPath: url.path) else {
            saveError = "The file was moved or renamed. Reopen it from the library."
            return
        }
        do { try PDFDocument.saveHighlights(from: document, pages: pages, to: url) } catch { saveError = error.localizedDescription }
    }
}

final class ReaderController {
    weak var pdfView: PDFView?
    var pageChanged: ((Int) -> Void)?

    /// Highlights the selected text, or removes the highlights the selection overlaps.
    /// Returns the indexes of the pages that changed.
    func toggleHighlight() -> [Int] {
        guard let view = pdfView, let document = view.document,
              let selection = view.currentSelection, !selection.pages.isEmpty else { return [] }

        var removed = false
        for page in selection.pages {
            let area = selection.bounds(for: page)
            for annotation in page.annotations where annotation.type == "Highlight" && annotation.bounds.intersects(area) {
                page.removeAnnotation(annotation)
                removed = true
            }
        }
        if !removed {
            for line in selection.selectionsByLine() {
                for page in line.pages {
                    let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                    annotation.color = NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.5)
                    page.addAnnotation(annotation)
                }
            }
        }
        view.clearSelection()
        return selection.pages.map { document.index(for: $0) }
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let pageColor: PageColor
    let startPage: Int
    let controller: ReaderController

    final class Coordinator {
        var color: PageColor?
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        TintedPage.color = pageColor
        view.backgroundColor = NSColor(cgColor: pageColor.gutter) ?? .gray
        view.document = document
        context.coordinator.color = pageColor
        controller.pdfView = view

        let coordinator = context.coordinator
        let controller = controller
        let startPage = startPage
        // Jump after the first layout, then start tracking, so the initial page 1 isn't saved as the reading position.
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            if startPage > 0, let page = document.page(at: startPage) { view.go(to: page) }
            coordinator.observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak view] _ in
                guard let view, let page = view.currentPage, let doc = view.document else { return }
                controller.pageChanged?(doc.index(for: page))
            }
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.color != pageColor else { return }
        context.coordinator.color = pageColor
        TintedPage.color = pageColor
        view.backgroundColor = NSColor(cgColor: pageColor.gutter) ?? .gray
        // PDFKit caches rendered pages; re-setting the document is the reliable way to redraw them.
        let position = view.currentDestination
        view.document = nil
        view.document = document
        if let position { view.go(to: position) }
    }
}
