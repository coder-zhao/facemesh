import UIKit
import AVFoundation
import MediaPipeTasksVision

final class ViewController: UIViewController {

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    private let stickerView = UIImageView(image: UIImage(named: "glasses"))
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
        stickerView.contentMode = .scaleToFill
        stickerView.alpha = 0
        let imageSize = stickerView.image?.size ?? CGSize(width: 500, height: 220)
        stickerView.bounds = CGRect(origin: .zero, size: imageSize)
        stickerView.frame.origin = .zero
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
        guard landmarks.count > 263 else {
            stickerView.alpha = 0
            return
        }

        let w = view.bounds.width
        let h = view.bounds.height

        let leftEye = toScreenPoint(landmarks[33], width: w, height: h)
        let rightEye = toScreenPoint(landmarks[263], width: w, height: h)
        let noseBridge = toScreenPoint(landmarks[168], width: w, height: h)

        let center = CGPoint(x: (leftEye.x + rightEye.x + noseBridge.x) / 3, y: (leftEye.y + rightEye.y + noseBridge.y) / 3)

        let targetLeft = scaleAround(center: center, point: leftEye, scale: meshScale)
        let targetRight = scaleAround(center: center, point: rightEye, scale: meshScale)
        let targetNose = scaleAround(center: center, point: noseBridge, scale: meshScale)

        let imageSize = stickerView.image?.size ?? CGSize(width: 500, height: 220)
        let sourceLeft = CGPoint(x: imageSize.width * 0.26, y: imageSize.height * 0.42)
        let sourceRight = CGPoint(x: imageSize.width * 0.74, y: imageSize.height * 0.42)
        let sourceNose = CGPoint(x: imageSize.width * 0.50, y: imageSize.height * 0.60)

        guard let t = affineFromTriangles(
            sourceLeft: sourceLeft,
            sourceRight: sourceRight,
            sourceNose: sourceNose,
            targetLeft: targetLeft,
            targetRight: targetRight,
            targetNose: targetNose
        ) else {
            stickerView.alpha = 0
            return
        }

        stickerView.transform = t
        stickerView.alpha = 1
    }

    private func toScreenPoint(_ landmark: NormalizedLandmark, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: (1 - CGFloat(landmark.x)) * width, y: CGFloat(landmark.y) * height)
    }

    private func scaleAround(center: CGPoint, point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + (point.x - center.x) * scale,
            y: center.y + (point.y - center.y) * scale
        )
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
            DispatchQueue.main.async { self.stickerView.alpha = 0 }
            return
        }

        DispatchQueue.main.async {
            self.updateSticker(landmarks: face)
        }
    }
}
