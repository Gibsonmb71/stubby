import CoreGraphics
import Foundation

struct RecognizedTextLine: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var confidence: Float
    var boundingBox: CGRect
}
