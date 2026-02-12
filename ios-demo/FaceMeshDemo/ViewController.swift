import UIKit
import AVFoundation
import MediaPipeTasksVision

final class ViewController: UIViewController {

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    private let stickerView = MeshStickerView(image: UIImage(named: "glasses"))
    private var faceLandmarker: FaceLandmarker!
    private var meshScale: CGFloat = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPreview()
        setupSticker()
        setupLandmarker()
        setupCamera()
        session.startRunning()
    }

    private func setupPreview() {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    private func setupSticker() {
        stickerView.frame = view.bounds
        stickerView.backgroundColor = .clear
        stickerView.isUserInteractionEnabled = false
        view.addSubview(stickerView)
    }

    private func setupLandmarker() {
        var options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task")!
        options.runningMode = .liveStream
        options.numFaces = 1
        options.minFaceDetectionConfidence = 0.5
        options.minFacePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.faceLandmarkerLiveStreamDelegate = self

        faceLandmarker = try? FaceLandmarker(options: options)
    }

    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input)
        else { return }

        session.addInput(input)

        let queue = DispatchQueue(label: "camera.queue")
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    private func updateSticker(landmarks: [NormalizedLandmark]) {
        let required = MeshStickerView.requiredLandmarks
        guard let maxIndex = required.max(), landmarks.count > maxIndex else {
            stickerView.clearSticker()
            return
        }

        let w = view.bounds.width
        let h = view.bounds.height

        var points = [Int: CGPoint]()
        required.forEach { index in
            points[index] = toScreenPoint(landmarks[index], width: w, height: h)
        }

        stickerView.updateStickerMesh(landmarkPoints: points, meshScale: meshScale)
    }

    private func toScreenPoint(_ landmark: NormalizedLandmark, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: (1 - CGFloat(landmark.x)) * width, y: CGFloat(landmark.y) * height)
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = Int(CACurrentMediaTime() * 1000)
        let mpImage = try? MPImage(pixelBuffer: imageBuffer)

        if let mpImage {
            try? faceLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestamp)
        }
    }
}

extension ViewController: FaceLandmarkerLiveStreamDelegate {
    func faceLandmarker(_ faceLandmarker: FaceLandmarker,
                        didFinishDetection result: FaceLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        guard error == nil,
              let face = result?.faceLandmarks.first
        else {
            DispatchQueue.main.async { self.stickerView.clearSticker() }
            return
        }

        DispatchQueue.main.async {
            self.updateSticker(landmarks: face)
        }
    }
}

private final class MeshStickerView: UIView {

    static let requiredLandmarks: Set<Int> = [33, 263, 168, 133, 362, 105, 334, 127, 356]

    private struct MeshVertex {
        let landmarkIndex: Int
        let sx: CGFloat
        let sy: CGFloat
    }

    private let meshVertices: [MeshVertex] = [
        MeshVertex(landmarkIndex: 33, sx: 0.26, sy: 0.42),
        MeshVertex(landmarkIndex: 263, sx: 0.74, sy: 0.42),
        MeshVertex(landmarkIndex: 168, sx: 0.50, sy: 0.60),
        MeshVertex(landmarkIndex: 133, sx: 0.34, sy: 0.44),
        MeshVertex(landmarkIndex: 362, sx: 0.66, sy: 0.44),
        MeshVertex(landmarkIndex: 105, sx: 0.30, sy: 0.30),
        MeshVertex(landmarkIndex: 334, sx: 0.70, sy: 0.30),
        MeshVertex(landmarkIndex: 127, sx: 0.10, sy: 0.44),
        MeshVertex(landmarkIndex: 356, sx: 0.90, sy: 0.44)
    ]

    private let meshTriangles: [[Int]] = [
        [33, 133, 105],
        [133, 168, 105],
        [263, 362, 334],
        [362, 168, 334],
        [33, 168, 133],
        [263, 168, 362],
        [33, 127, 168],
        [263, 356, 168],
        [33, 263, 168]
    ]

    private let image: UIImage?
    private var meshScale: CGFloat = 1.0
    private var landmarkPoints: [Int: CGPoint] = [:]
    private var visible = false

    init(image: UIImage?) {
        self.image = image
        super.init(frame: .zero)
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        self.image = nil
        super.init(coder: coder)
    }

    func clearSticker() {
        visible = false
        setNeedsDisplay()
    }

    func updateStickerMesh(landmarkPoints: [Int: CGPoint], meshScale: CGFloat) {
        self.landmarkPoints = landmarkPoints
        self.meshScale = meshScale
        visible = true
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard visible,
              let image,
              let cgImage = image.cgImage,
              requiredLandmarks.isSubset(of: Set(landmarkPoints.keys))
        else { return }

        let imageRect = CGRect(origin: .zero, size: image.size)
        guard let center = centerPoint() else { return }

        let srcPoints = Dictionary(uniqueKeysWithValues: meshVertices.map {
            ($0.landmarkIndex, CGPoint(x: $0.sx * image.size.width, y: $0.sy * image.size.height))
        })

        let dstPoints = Dictionary(uniqueKeysWithValues: meshVertices.compactMap { vertex -> (Int, CGPoint)? in
            guard let p = landmarkPoints[vertex.landmarkIndex] else { return nil }
            return (vertex.landmarkIndex, scaleAround(point: p, center: center, scale: meshScale))
        })

        guard let context = UIGraphicsGetCurrentContext() else { return }

        meshTriangles.forEach { tri in
            guard let s1 = srcPoints[tri[0]],
                  let s2 = srcPoints[tri[1]],
                  let s3 = srcPoints[tri[2]],
                  let t1 = dstPoints[tri[0]],
                  let t2 = dstPoints[tri[1]],
                  let t3 = dstPoints[tri[2]],
                  triangleArea(t1, t2, t3) > 1
            else { return }

            guard let transform = affineFromTriangles(
                sourceLeft: s1,
                sourceRight: s2,
                sourceNose: s3,
                targetLeft: t1,
                targetRight: t2,
                targetNose: t3
            ) else { return }

            context.saveGState()
            context.beginPath()
            context.move(to: t1)
            context.addLine(to: t2)
            context.addLine(to: t3)
            context.closePath()
            context.clip()
            context.concatenate(transform)
            context.draw(cgImage, in: imageRect)
            context.restoreGState()
        }
    }

    private func centerPoint() -> CGPoint? {
        let anchors = [33, 263, 168]
        let points = anchors.compactMap { landmarkPoints[$0] }
        guard points.count == anchors.count else { return nil }

        let x = points.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(points.count)
        let y = points.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    private func scaleAround(point: CGPoint, center: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + (point.x - center.x) * scale,
            y: center.y + (point.y - center.y) * scale
        )
    }

    private func triangleArea(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
        abs((p1.x * (p2.y - p3.y) + p2.x * (p3.y - p1.y) + p3.x * (p1.y - p2.y)) * 0.5)
    }

    private func affineFromTriangles(
        sourceLeft s1: CGPoint,
        sourceRight s2: CGPoint,
        sourceNose s3: CGPoint,
        targetLeft t1: CGPoint,
        targetRight t2: CGPoint,
        targetNose t3: CGPoint
    ) -> CGAffineTransform? {
        let ux = s2.x - s1.x
        let uy = s2.y - s1.y
        let vx = s3.x - s1.x
        let vy = s3.y - s1.y
        let det = ux * vy - uy * vx
        if abs(det) < 0.0001 { return nil }

        let uxp = t2.x - t1.x
        let uyp = t2.y - t1.y
        let vxp = t3.x - t1.x
        let vyp = t3.y - t1.y

        let a = (uxp * vy - vxp * uy) / det
        let c = (-uxp * vx + vxp * ux) / det
        let b = (uyp * vy - vyp * uy) / det
        let d = (-uyp * vx + vyp * ux) / det

        let tx = t1.x - a * s1.x - c * s1.y
        let ty = t1.y - b * s1.x - d * s1.y

        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}
