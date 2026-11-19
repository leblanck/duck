import OSLog
import PDFKit
import SwiftUI

extension FocusedValues {
    /// The reader in the focused window, for the View menu's zoom commands.
    @Entry var reader: ReaderController?
    /// What ⌘F does in the focused window: search the open paper, or the library.
    @Entry var find: FindAction?
}

/// A closure SwiftUI can compare (by name), so focus updates don't churn the menu.
struct FindAction: Equatable {
    let name: String
    let run: () -> Void
    static func == (a: Self, b: Self) -> Bool { a.name == b.name }
}

struct ReaderView: View {
    let id: String
    @Environment(Library.self) private var library
    @AppStorage("pageColor") private var pageColor = PageColor.tan
    @State private var document: PDFDocument?
    @State private var failed = false
    @State private var controller = ReaderController()
    @State private var choosingColor = false
    @State private var finding = false
    @State private var query = ""
    @State private var matches: [PDFSelection] = []
    @State private var findMarks: [[PDFAnnotation]] = [] // drawn marks for each match
    @State private var matchIndex = 0
    @FocusState private var findFocused: Bool

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
        .overlay(alignment: .top) { if finding { findBar } }
        .frame(minWidth: 400, minHeight: 400)
        .navigationTitle((id as NSString).deletingPathExtension)
        .focusedSceneValue(\.reader, document == nil ? nil : controller)
        .focusedSceneValue(\.find, document == nil ? nil : FindAction(name: "paper:" + id) { finding = true; findFocused = true })
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
        .task(id: id) {
            let url = library.url(for: id)
            await Library.download(url)
            guard let loaded = PDFDocument.tinted(url: url) else {
                Log.reader.error("PDFKit couldn't open \(id, privacy: .public)")
                failed = true
                return
            }
            for highlight in library.meta[id]?.highlights ?? [] {
                loaded.page(at: highlight.page)?.addAnnotation(ReaderController.makeHighlight(highlight.rect))
            }
            document = loaded
            controller.pageChanged = { [library, id] page in library.setLastPage(id, page) }
            library.markOpened(id)
        }
    }

    // MARK: Find

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField("Find in paper", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .focused($findFocused)
                .onSubmit { step(1) }
                .onExitCommand(perform: closeFind)
                .onChange(of: query) { search() }
            if !query.isEmpty {
                Text(matches.isEmpty ? "No matches" : "\(matchIndex + 1) of \(matches.count)")
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            Button { step(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).disabled(matches.isEmpty).help("Previous match")
            Button { step(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).disabled(matches.isEmpty).help("Next match (Return)")
            Button(action: closeFind) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Close (Esc)")
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14).frame(height: 36)
        .background(Capsule().fill(Theme.background))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.top, 12)
    }

    // Matches are drawn as temporary marks rather than PDFKit selections, so they get trimmed bounds too.
    private static let matchColor = NSColor(red: 1, green: 0.78, blue: 0.35, alpha: 0.35)
    private static let currentMatchColor = NSColor(red: 1, green: 0.6, blue: 0.1, alpha: 0.6)

    private func search() {
        guard let document else { return }
        removeFindMarks()
        matches = query.isEmpty ? [] : document.findString(query, withOptions: .caseInsensitive)
        findMarks = matches.map { match in
            match.pages.map { page in
                let mark = PDFAnnotation(bounds: ReaderController.textBounds(match, on: page), forType: .highlight, withProperties: nil)
                mark.color = Self.matchColor
                page.addAnnotation(mark)
                return mark
            }
        }
        matchIndex = 0
        show()
    }

    private func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        show()
    }

    private func show() {
        guard let view = controller.pdfView, findMarks.indices.contains(matchIndex) else { return }
        for (index, marks) in findMarks.enumerated() {
            marks.forEach { $0.color = index == matchIndex ? Self.currentMatchColor : Self.matchColor }
        }
        if let mark = findMarks[matchIndex].first, let page = mark.page {
            view.go(to: mark.bounds.insetBy(dx: 0, dy: -60), on: page)
        }
    }

    private func removeFindMarks() {
        findMarks.joined().forEach { $0.page?.removeAnnotation($0) }
        findMarks = []
    }

    private func closeFind() {
        finding = false
        query = ""
        removeFindMarks()
        matches = []
    }

    // MARK: Page color

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

    // MARK: Highlights

    /// Highlights live in library.json, not the PDF: saving through PDFKit rewrites the file and garbles its text.
    private func highlight() {
        guard let document else { return }
        var changed: [Int: [CGRect]] = [:]
        // With nothing selected, ⌃⌘H highlights the current search match.
        let match = finding && matches.indices.contains(matchIndex) ? matches[matchIndex] : nil
        for index in controller.toggleHighlight(fallback: match) {
            changed[index] = document.page(at: index)?.annotations.filter(ReaderController.isOurs).map(\.bounds) ?? []
        }
        if !changed.isEmpty { library.setHighlights(id, changed) }
    }
}

final class ReaderController {
    weak var pdfView: PDFView?
    var pageChanged: ((Int) -> Void)?

    /// Marks highlights Duck draws from library.json, as opposed to ones saved inside the PDF by other apps.
    private static let marker = "Duck"

    static func makeHighlight(_ bounds: CGRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.color = NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.5)
        annotation.userName = marker
        return annotation
    }

    static func isOurs(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == "Highlight" && annotation.userName == marker
    }

    /// Bounds of `selection` on `page`, trimmed to the text. Some PDFs declare fonts far taller than their
    /// letters (5× the font size, say), and PDFKit's bounds follow the declared size. The tall box is centered
    /// on the text, so keep its center and use a normal line height.
    static func textBounds(_ selection: PDFSelection, on page: PDFPage) -> CGRect {
        let bounds = selection.bounds(for: page)
        guard let text = selection.attributedString, text.length > 0 else { return bounds }
        var fontSize: CGFloat = 0
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let font = value as? NSFont { fontSize = max(fontSize, font.pointSize) }
        }
        guard fontSize > 0, bounds.height > fontSize * 1.6 else { return bounds }
        let height = fontSize * 1.2
        return CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
    }

    /// Highlights the selected text (or `fallback` when nothing is selected), or removes the highlights it overlaps.
    /// Returns the indexes of the pages that changed.
    func toggleHighlight(fallback: PDFSelection? = nil) -> [Int] {
        guard let view = pdfView, let document = view.document,
              let selection = view.currentSelection ?? fallback, !selection.pages.isEmpty else { return [] }
        let lines = selection.selectionsByLine().flatMap { line in line.pages.map { (page: $0, rect: Self.textBounds(line, on: $0)) } }

        var removed = false
        for (page, rect) in lines {
            for annotation in page.annotations where Self.isOurs(annotation) && annotation.bounds.intersects(rect) {
                page.removeAnnotation(annotation)
                removed = true
            }
        }
        if !removed {
            for (page, rect) in lines { page.addAnnotation(Self.makeHighlight(rect)) }
        }
        view.clearSelection()
        return selection.pages.map { document.index(for: $0) }
    }

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func fitWidth() { pdfView?.autoScales = true }
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
