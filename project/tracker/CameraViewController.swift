import UIKit
import AVFoundation
import Vision

enum SkeletonStyle {
    case pointsOnly
    case linesOnly
    case full
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    
    private var pointLayers: [CAShapeLayer] = []
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var overlayLayer = CAShapeLayer()
    private var currentStyle: SkeletonStyle = .pointsOnly
    
    override func viewDidLoad() {
        super.viewDidLoad()
        overlayLayer.frame = view.bounds
        overlayLayer.strokeColor = UIColor.systemRed.cgColor
        overlayLayer.fillColor = UIColor.systemRed.cgColor
        setupCamera()
        
        let styleControl = UISegmentedControl(items: ["Точки", "Скелет"])
        styleControl.selectedSegmentIndex = 0
        styleControl.addTarget(self, action: #selector(styleChanged(_:)), for: .valueChanged)
        styleControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(styleControl)

        NSLayoutConstraint.activate([
            styleControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            styleControl.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    @objc private func styleChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            currentStyle = .pointsOnly
        case 1:
            currentStyle = .linesOnly
        default:
            break
        }
    }
    
    private func setupCamera() {
        captureSession.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front) else {
            print("нет доступа к камере")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("ошибка подключения: \(error)")
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput
            .setSampleBufferDelegate(
                self,
                queue: DispatchQueue(label: "videoQueue")
            )
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
                
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        view.layer.addSublayer(overlayLayer)
                
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
            
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let request = VNDetectHumanBodyPoseRequest()
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                   orientation: .leftMirrored,
                                                   options: [:])
        do {
            try requestHandler.perform([request])
            guard let observations = request.results else {
                return
            }
            
            if observations.isEmpty {
                DispatchQueue.main.async {
                    self.pointLayers.forEach{$0.removeFromSuperlayer()}
                    self.pointLayers.removeAll()
                }
                return
            }

            for observation in observations {
                if let recognizedPoints = try? observation.recognizedPoints(
                    .all
                ) {
                    drawSkeleton(from: recognizedPoints)
                }
            }
        } catch {
            print("ошибка обработки кадра: \(error)")
        }
    }
    
    private func convertPoint(_ point: VNRecognizedPoint) -> CGPoint {
        let x = CGFloat(point.x) * self.view.bounds.width
        let y = (1 - CGFloat(point.y)) * self.view.bounds.height
        return CGPoint(x: x, y: y)
    }
    
    private func clearLayers() {
        self.pointLayers.forEach { $0.removeFromSuperlayer() }
        self.pointLayers.removeAll()
    }
    
    private func drawSkeleton(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        DispatchQueue.main.async {
            self.clearLayers()

            switch self.currentStyle {
            case .pointsOnly:
                for (_, point) in points {
                    guard point.confidence > 0.1 else { continue }
                    let position = self.convertPoint(point)
                    let radius: CGFloat = 6.0
                    let circleRect = CGRect(x: position.x - radius,
                                            y: position.y - radius,
                                            width: radius * 2,
                                            height: radius * 2)
                    let path = UIBezierPath(ovalIn: circleRect)

                    let layer = CAShapeLayer()
                    layer.path = path.cgPath
                    layer.fillColor = self.color(for: point.confidence).cgColor

                    self.view.layer.addSublayer(layer)
                    self.pointLayers.append(layer)
                }

            case .linesOnly:
                let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
                    (.leftShoulder, .rightShoulder),
                    (.leftHip, .rightHip),
                    (.neck, .root),
                    (.leftShoulder, .leftElbow),
                    (.leftElbow, .leftWrist),
                    (.rightShoulder, .rightElbow),
                    (.rightElbow, .rightWrist),
                    (.leftHip, .leftKnee),
                    (.leftKnee, .leftAnkle),
                    (.rightHip, .rightKnee),
                    (.rightKnee, .rightAnkle)
                ]

                for (jointA, jointB) in connections {
                    guard let pointA = points[jointA], let pointB = points[jointB],
                          pointA.confidence > 0.1, pointB.confidence > 0.1 else { continue }

                    let posA = self.convertPoint(pointA)
                    let posB = self.convertPoint(pointB)

                    let path = UIBezierPath()
                    path.move(to: posA)
                    path.addLine(to: posB)

                    let layer = CAShapeLayer()
                    layer.path = path.cgPath
                    layer.strokeColor = UIColor.systemGreen.cgColor
                    layer.lineWidth = 4.0

                    self.view.layer.addSublayer(layer)
                    self.pointLayers.append(layer)
                }

            case .full:
                //
                break
            }
        }
    }
    
    private func color(for confidence: Float) -> UIColor {
        switch confidence {
        case let c where c > 0.6:
            return .systemGreen
        case let c where c > 0.4:
            return .systemYellow
        default:
            return .systemRed
        }
    }
}
