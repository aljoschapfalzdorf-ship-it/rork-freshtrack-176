import AVFoundation
import UIKit
import Observation

/// Owns the capture session for the receipt scanner.
@Observable
final class CameraService: NSObject {
    enum State: Equatable {
        case idle, requesting, denied, unavailable, running, failed
    }

    private(set) var state: State = .idle
    private(set) var hasTorch: Bool = false
    private(set) var isTorchOn: Bool = false

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var photoContinuation: CheckedContinuation<UIImage?, Never>?
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "vorrat.camera.session")

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            state = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { state = .denied; return }
        default:
            state = .denied
            return
        }
        configureIfNeeded()
    }

    func stop() {
        setTorch(false)
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        if device != nil {
            let session = self.session
            sessionQueue.async { if !session.isRunning { session.startRunning() } }
            state = .running
            return
        }
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera]
        if #available(iOS 17.0, *) { types.append(.external) }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        let preferred = discovery.devices.first { $0.position == .back } ?? discovery.devices.first
        guard let camera = preferred else {
            state = .unavailable
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            device = camera
            hasTorch = camera.hasTorch
            let session = self.session
            sessionQueue.async { session.startRunning() }
            state = .running
        } catch {
            state = .failed
        }
    }

    func toggleTorch() {
        setTorch(!isTorchOn)
    }

    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
        } catch {
            isTorchOn = false
        }
    }

    func capture() async -> UIImage? {
        guard state == .running, photoContinuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    fileprivate func finish(with image: UIImage?) {
        photoContinuation?.resume(returning: image)
        photoContinuation = nil
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            let image = data.flatMap { UIImage(data: $0) }
            self.finish(with: image)
        }
    }
}
