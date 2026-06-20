import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

enum TicketImportError: LocalizedError {
    case unsupportedFile
    case unreadableImage
    case unreadablePDF
    case emptyPDF
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "Stubby could not import this file type."
        case .unreadableImage:
            return "Stubby could not read the selected image."
        case .unreadablePDF:
            return "Stubby could not read the selected PDF."
        case .emptyPDF:
            return "The selected PDF does not contain any pages."
        case .noTextFound:
            return "No ticket text was detected. Try a clearer screenshot or photo."
        }
    }
}

final class TicketImportService {
    private let ocrService: OCRService
    private let parser: TicketTextParser

    init(ocrService: OCRService = OCRService(), parser: TicketTextParser = TicketTextParser()) {
        self.ocrService = ocrService
        self.parser = parser
    }

    func importTicket(fromImageData data: Data) async throws -> TicketImportResult {
        guard let image = UIImage(data: data) else {
            throw TicketImportError.unreadableImage
        }
        return try await importTicket(from: image)
    }

    func importTicket(from fileURL: URL) async throws -> TicketImportResult {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey])
        let contentType = values?.contentType
        let data = try Data(contentsOf: fileURL)

        if contentType?.conforms(to: .pdf) == true || fileURL.pathExtension.lowercased() == "pdf" {
            return try await importTicket(fromPDFData: data)
        }

        if contentType?.conforms(to: .image) == true || UIImage(data: data) != nil {
            return try await importTicket(fromImageData: data)
        }

        throw TicketImportError.unsupportedFile
    }

    private func importTicket(from image: UIImage) async throws -> TicketImportResult {
        let normalizedImage = image.normalizedForOCR()
        guard let cgImage = normalizedImage.cgImage else {
            throw TicketImportError.unreadableImage
        }

        let ocrResult = try await ocrService.recognizeTicket(in: cgImage)
        guard !ocrResult.lines.isEmpty else {
            throw TicketImportError.noTextFound
        }

        return TicketImportResult(
            draft: ImportedEventDraft(details: parser.parse(lines: ocrResult.lines, barcodePayloads: ocrResult.barcodePayloads)),
            previewImageData: normalizedImage.previewImageData()
        )
    }

    private func importTicket(fromPDFData data: Data) async throws -> TicketImportResult {
        guard let document = PDFDocument(data: data) else {
            throw TicketImportError.unreadablePDF
        }
        guard document.pageCount > 0 else {
            throw TicketImportError.emptyPDF
        }

        let pageLimit = min(document.pageCount, 3)
        var allLines: [RecognizedTextLine] = []
        var allBarcodePayloads: [String] = []
        var previewImageData: Data?

        for pageIndex in 0..<pageLimit {
            guard let page = document.page(at: pageIndex) else { continue }
            let renderedPage = render(page: page)
            if previewImageData == nil {
                previewImageData = renderedPage.previewImageData()
            }
            guard let cgImage = renderedPage.cgImage else { continue }
            let ocrResult = try await ocrService.recognizeTicket(in: cgImage)
            allLines.append(contentsOf: ocrResult.lines)
            allBarcodePayloads.append(contentsOf: ocrResult.barcodePayloads)
        }

        guard !allLines.isEmpty else {
            throw TicketImportError.noTextFound
        }

        return TicketImportResult(
            draft: ImportedEventDraft(details: parser.parse(lines: allLines, barcodePayloads: Array(Set(allBarcodePayloads)).sorted())),
            previewImageData: previewImageData
        )
    }

    private func render(page: PDFPage) -> UIImage {
        let pageBounds = page.bounds(for: .mediaBox)
        let targetWidth: CGFloat = 1800
        let scale = max(1, targetWidth / max(pageBounds.width, 1))
        let targetSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            context.cgContext.saveGState()
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: 0, y: pageBounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }
}

private extension UIImage {
    func normalizedForOCR() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func previewImageData() -> Data? {
        jpegData(compressionQuality: 0.88) ?? pngData()
    }
}
