import Foundation
import CoreGraphics
import CoreImage
import ImageIO

private struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct RecognitionSmokeTest {
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw SmokeFailure(description: "FAIL: " + message) }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw SmokeFailure(description: "Usage: recognition-smoke-test APP_PATH FACE_IMAGE")
        }
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[2])
        guard let source = CIImage(contentsOf: fixtureURL) else {
            throw SmokeFailure(description: "Could not read the test image")
        }
        let context = RecognitionRuntime.makeImageContext()
        guard let image = context.createCGImage(source, from: source.extent) else {
            throw SmokeFailure(description: "CPU image conversion failed")
        }
        print("PASS: CPU image conversion")

        let initialFaces = try FaceDetector.detectFaces(in: image)
        guard let initialFace = initialFaces.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let closeUp = FaceDetector.crop(initialFace, from: image, paddingFraction: 0.75) else {
            throw SmokeFailure(description: "Vision did not find the fixture face")
        }
        let faces = try FaceDetector.detectFaces(in: closeUp)
        guard let face = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            throw SmokeFailure(description: "Vision did not find the close-up face")
        }
        try require(face.yaw != nil && face.pitch != nil, "Vision did not return both head angles")
        guard let aligned = FaceAligner.align(face, from: closeUp) else {
            throw SmokeFailure(description: "Face alignment failed")
        }
        try require(aligned.tier == .fivePoint, "Five-point landmarks were not usable")
        print("PASS: Vision face detection, head angles, and five-point alignment")

        guard let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil),
              let modelURL = enumerator.allObjects.compactMap({ $0 as? URL })
                .first(where: { $0.lastPathComponent == "ArcFace.mlmodelc" }) else {
            throw SmokeFailure(description: "Compiled ArcFace model missing")
        }
        let embedder = try ArcFaceEmbedder(modelURL: modelURL)
        let vector = try embedder.embedding(for: aligned.image)
        try require(vector.count == 512 && vector.allSatisfy(\.isFinite), "Invalid ArcFace output")
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        try require(abs(norm - 1) < 0.001, "ArcFace output was not normalized")
        let repeated = try embedder.embedding(for: aligned.image)
        try require(FaceEmbedding.cosineSimilarity(vector, repeated) > 0.999, "Inference was not repeatable")
        print("PASS: bundled ArcFace model loads and produces repeatable CPU embeddings")

        let blank = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        guard let blankImage = context.createCGImage(blank, from: blank.extent) else {
            throw SmokeFailure(description: "Could not construct the negative test frame")
        }
        let blankFaces = try FaceDetector.detectFaces(in: blankImage)
        try require(blankFaces.isEmpty, "Blank frame was incorrectly treated as a face")
        print("PASS: a blank frame produces no face")
        print("All recognition smoke tests passed. Live camera enrollment on Sonoma still requires a device test.")
    }
}
