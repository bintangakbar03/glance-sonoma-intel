import CoreImage
import CoreML

/// Use the CPU for this Intel port's image conversion and face embeddings.
/// The live AVCapture preview has its own rendering path: a working preview
/// alone does not prove that Core Image or Core ML can use the local GPU.
nonisolated enum RecognitionRuntime {
    #if arch(x86_64)
    static let computeUnits: MLComputeUnits = .cpuOnly
    private static let softwareRenderer = true
    #else
    static let computeUnits: MLComputeUnits = .all
    private static let softwareRenderer = false
    #endif

    static func makeImageContext() -> CIContext {
        CIContext(options: [.useSoftwareRenderer: softwareRenderer])
    }
}
