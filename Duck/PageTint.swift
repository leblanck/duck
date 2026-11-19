import PDFKit

enum PageColor: String, CaseIterable, Identifiable {
    case tan, sepia, white, dark

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// The gray area around and between pages.
    var gutter: CGColor {
        switch self {
        case .tan: CGColor(red: 0.80, green: 0.76, blue: 0.69, alpha: 1)
        case .sepia: CGColor(red: 0.72, green: 0.66, blue: 0.57, alpha: 1)
        case .white: CGColor(gray: 0.88, alpha: 1)
        case .dark: CGColor(gray: 0.07, alpha: 1)
        }
    }
}

/// Paints the chosen paper tone onto each page as PDFKit draws it. The PDF file is never changed.
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

        func fill(_ mode: CGBlendMode, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
            context.setBlendMode(mode)
            context.setFillColor(red: r, green: g, blue: b, alpha: 1)
            context.fill(rect)
        }

        context.saveGState()
        // Pages without a painted background are transparent; put white behind so the blends below act on paper.
        fill(.destinationOver, 1, 1, 1)
        switch color {
        case .tan:
            // Multiply turns white paper tan while black text stays black.
            fill(.multiply, 0.96, 0.92, 0.83)
        case .sepia:
            fill(.multiply, 0.92, 0.84, 0.70)
        case .dark:
            fill(.difference, 1, 1, 1)        // invert: black paper, white text
            fill(.multiply, 0.86, 0.85, 0.82) // soften the text
            fill(.screen, 0.11, 0.11, 0.12)   // lift the paper off pure black
        case .white:
            break
        }
        context.restoreGState()
    }
}

final class TintedPageProvider: NSObject, PDFDocumentDelegate {
    static let shared = TintedPageProvider()
    func classForPage() -> AnyClass { TintedPage.self }
}

extension PDFDocument {
    /// Opens a PDF whose pages draw with the current page color.
    static func tinted(url: URL) -> PDFDocument? {
        guard let document = PDFDocument(url: url) else { return nil }
        document.delegate = TintedPageProvider.shared
        return document
    }
}
