import PDFKit

enum PageColor: String, CaseIterable, Identifiable {
    case tan, sepia, white, dark

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

    /// What white paper becomes.
    var paper: RGB {
        switch self {
        case .tan: Theme.backgroundRGB // so pages blend into the window
        case .sepia: (0.92, 0.84, 0.70)
        case .white: (1, 1, 1)
        case .dark: (0.11, 0.11, 0.12)
        }
    }

    /// What black text becomes.
    var ink: RGB {
        self == .dark ? (0.87, 0.86, 0.82) : (0, 0, 0)
    }

    /// The area around and between pages.
    var gutter: CGColor {
        switch self {
        case .tan: CGColor(srgbRed: Theme.panelRGB.r, green: Theme.panelRGB.g, blue: Theme.panelRGB.b, alpha: 1)
        case .sepia: CGColor(srgbRed: 0.72, green: 0.66, blue: 0.57, alpha: 1)
        case .white: CGColor(gray: 0.88, alpha: 1)
        case .dark: CGColor(gray: 0.07, alpha: 1)
        }
    }
}

/// Paints the chosen page color onto each page as PDFKit draws it, as ordinary drawing, so it goes through the
/// same color handling as the rest of the UI. PDF files are never changed.
/// Never save a document made of these pages: PDFKit drops their content when writing. See `ReaderView.save`.
final class TintedPage: PDFPage {
    // Read from PDFKit's render threads, written on the main thread when the user picks a color.
    nonisolated(unsafe) static var color: PageColor = .tan

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        let color = Self.color
        guard color != .white else { return }

        // PDFKit's render tiles overhang the page slightly; tint only the page itself.
        let rect = context.boundingBoxOfClipPath.intersection(bounds(for: box))
        guard !rect.isNull, !rect.isEmpty else { return }

        func fill(_ mode: CGBlendMode, _ c: PageColor.RGB) {
            context.setBlendMode(mode)
            context.setFillColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
            context.fill(rect)
        }

        context.saveGState()
        // Pages without a painted background are transparent; put white behind so the blends below act on paper.
        fill(.destinationOver, (1, 1, 1))
        if color == .dark {
            fill(.difference, (1, 1, 1)) // invert: black paper, white text
            fill(.multiply, color.ink)   // soften the text
            fill(.screen, color.paper)   // lift the paper off pure black
        } else {
            fill(.multiply, color.paper) // white paper becomes the paper color; black text stays black
        }
        context.restoreGState()
    }
}

final class TintedPageProvider: NSObject, PDFDocumentDelegate {
    static let shared = TintedPageProvider()
    func classForPage() -> AnyClass { TintedPage.self }
}

extension PDFDocument {
    /// Opens a PDF for display whose pages draw with the current page color.
    static func tinted(url: URL) -> PDFDocument? {
        guard let document = PDFDocument(url: url) else { return nil }
        document.delegate = TintedPageProvider.shared
        return document
    }
}

extension PDFDocument {
    /// Saves the highlights on `pages` of the on-screen (tinted) document into the file at `url`.
    /// Writes through a fresh plain copy of the file, because writing a TintedPage document loses page content.
    static func saveHighlights(from display: PDFDocument, pages: [Int], to url: URL) throws {
        guard let plain = PDFDocument(url: url), plain.pageCount == display.pageCount else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The PDF on disk changed since it was opened."])
        }
        for index in pages {
            guard let target = plain.page(at: index), let source = display.page(at: index) else { continue }
            for annotation in target.annotations where annotation.type == "Highlight" { target.removeAnnotation(annotation) }
            for annotation in source.annotations where annotation.type == "Highlight" {
                if let copy = annotation.copy() as? PDFAnnotation { target.addAnnotation(copy) }
            }
        }
        guard let data = plain.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "PDFKit couldn't write this PDF."])
        }
        try data.write(to: url, options: .atomic)
    }
}
