import Foundation
import Vision

struct TicketOCRResult {
    var lines: [RecognizedTextLine]
    var barcodePayloads: [String]
    var usedDocumentRecognition: Bool
}

final class OCRService {
    func recognizeTicket(in cgImage: CGImage) async throws -> TicketOCRResult {
        if #available(iOS 26.0, *) {
            do {
                let documentResult = try await recognizeDocument(in: cgImage)
                if !documentResult.lines.isEmpty {
                    return documentResult
                }
            } catch {
                // Fall through to classic OCR; tickets are often screenshots rather than clean documents.
            }
        }

        return TicketOCRResult(
            lines: try await recognizeText(in: cgImage),
            barcodePayloads: [],
            usedDocumentRecognition: false
        )
    }

    func recognizeText(in cgImage: CGImage) async throws -> [RecognizedTextLine] {
        var request = RecognizeTextRequest(RecognizeTextRequest.supportedRevisions.max())
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeightFraction = 0.008

        let observations = try await ImageRequestHandler(cgImage).perform(request)
        return observations
            .compactMap(makeRecognizedLine)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if yDelta > 0.015 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
    }

    @available(iOS 26.0, *)
    private func recognizeDocument(in cgImage: CGImage) async throws -> TicketOCRResult {
        var request = RecognizeDocumentsRequest(RecognizeDocumentsRequest.supportedRevisions.max())
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.maximumCandidateCount = 1
        request.barcodeDetectionOptions.enabled = true

        let observations = try await ImageRequestHandler(cgImage).perform(request)
        let recognizedTextObservations = observations.flatMap { observation in
            observation.document.paragraphs.flatMap(\.lines)
        }

        let lines = recognizedTextObservations
            .compactMap(makeRecognizedLine)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if yDelta > 0.015 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

        let barcodePayloads = Array(Set(observations.flatMap { observation in
            observation.document.barcodes.compactMap(\.payloadString)
        })).sorted()

        return TicketOCRResult(
            lines: lines,
            barcodePayloads: barcodePayloads,
            usedDocumentRecognition: true
        )
    }

    @available(iOS 26.0, *)
    private func makeRecognizedLine(from observation: RecognizedTextObservation) -> RecognizedTextLine? {
        let text = observation.transcript.isEmpty
            ? observation.topCandidates(1).first?.string ?? ""
            : observation.transcript

        let minX = min(observation.topLeft.x, observation.bottomLeft.x, observation.topRight.x, observation.bottomRight.x)
        let maxX = max(observation.topLeft.x, observation.bottomLeft.x, observation.topRight.x, observation.bottomRight.x)
        let minY = min(observation.topLeft.y, observation.bottomLeft.y, observation.topRight.y, observation.bottomRight.y)
        let maxY = max(observation.topLeft.y, observation.bottomLeft.y, observation.topRight.y, observation.bottomRight.y)

        return RecognizedTextLine(
            text: text,
            confidence: observation.confidence,
            boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        )
    }
}
