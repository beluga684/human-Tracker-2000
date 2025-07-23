import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var overlayLayer = CAShapeLayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        overlayLayer.frame = view.bounds
        overlayLayer.strokeColor = UIColor.systemRed.cgColor
        overlayLayer.fillColor = UIColor.systemRed.cgColor
        setupCamera()
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
                    self.overlayLayer.path = nil
                }
                return
            }

            for observation in observations {
                if let recognizedPoints = try? observation.recognizedPoints(.all) {
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
    
    private func drawSkeleton(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        DispatchQueue.main.async {
            let path = UIBezierPath()

            for (_, point) in points {
                guard point.confidence > 0.3 else { continue }

                let position = self.convertPoint(point)
                let radius: CGFloat = 6.0
                let circle = UIBezierPath(ovalIn: CGRect(x: position.x - radius,
                                                         y: position.y - radius,
                                                         width: radius * 2,
                                                         height: radius * 2))
                path.append(circle)
            }

            self.overlayLayer.path = path.cgPath
        }
    }
}
