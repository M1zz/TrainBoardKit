#if canImport(UIKit) && canImport(AVFoundation) && canImport(Vision)
import SwiftUI
import AVFoundation
import Vision

// MARK: - Board camera
//
// Back camera + on-device Vision OCR, ~2 fps. Each frame's text is grouped into
// board rows (top row first) and handed to `onRows` — the app judges them with
// `TrainBoardJudge` and draws its own verdict. The OCR languages are the app's
// choice: KORA reads ["ko-KR", "en-US"], the Japan app ["ja-JP", "en-US"].

// @unchecked Sendable: @Published state is only mutated on the main thread; the
// capture session/output are confined to `videoQueue`. We manage that manually.
public final class BoardCamera: ObservableObject, @unchecked Sendable {

    @Published public private(set) var denied = false
    /// Latest rows read, top first — for on-screen debugging of real boards.
    @Published public private(set) var rows: [String] = []

    public let session = AVCaptureSession()
    /// Called on the camera queue with every frame's rows (possibly empty, so a
    /// stale verdict can reset when nothing is read).
    public var onRows: (([String]) -> Void)?

    private let videoQueue = DispatchQueue(label: "trainboardkit.camera")
    private let output = AVCaptureVideoDataOutput()
    private let handler: SampleHandler

    public init(recognitionLanguages: [String]) {
        handler = SampleHandler(languages: recognitionLanguages)
        handler.onBoxes = { [weak self] boxes in
            let rows = TrainBoardJudge.rows(from: boxes)
            self?.onRows?(rows)
            DispatchQueue.main.async { self?.rows = rows }
        }
    }

    @MainActor
    public func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else { denied = true; return }
        videoQueue.async { [weak self] in
            self?.setupSession()
        }
    }

    public func stop() {
        videoQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Runs on `videoQueue`.
    private func setupSession() {
        guard session.inputs.isEmpty else {
            if !session.isRunning { session.startRunning() }
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(handler, queue: videoQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
    }
}

// MARK: - Sample buffer → Vision OCR

private final class SampleHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onBoxes: (([TrainBoardJudge.TextBox]) -> Void)?
    private let languages: [String]
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 0.5   // ~2 fps OCR

    init(languages: [String]) {
        self.languages = languages
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= minInterval else { return }
        lastRun = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest { [weak self] req, _ in
            let results = req.results as? [VNRecognizedTextObservation] ?? []
            let boxes = results.compactMap { obs -> TrainBoardJudge.TextBox? in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                let r = obs.boundingBox
                return .init(text: text, minY: r.minY, maxY: r.maxY, minX: r.minX)
            }
            self?.onBoxes?(boxes)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - Camera preview

public struct BoardCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    public func updateUIView(_ uiView: PreviewView, context: Context) {}

    public final class PreviewView: UIView {
        override public class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
#endif
