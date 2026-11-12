import AVFoundation
import CoreImage

/// Capture configuration, delegate callbacks, and image processing share one serial executor.
actor RakaatCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated let queue = DispatchSerialQueue(label: "com.aljaroudi.Muntathir.rakaat")
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private let capture = AVCaptureSession()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var device: AVCaptureDevice?
    private var detector = RakaatDetector(target: 2)
    private var firstTime: Double?
    private var lastTime = -Double.infinity
    private var exposureLocked = false
    private var preparation = RakaatPreparation()
    private var preparationTimeout: Task<Void, Never>?
    private var continuation: AsyncStream<Update>.Continuation?

    struct Update: Sendable {
        let preview: CGImage?
        let count: Int
        let calibrated: Bool
        let complete: Bool
        var failure: RakaatPreparation.Failure?
    }

    enum Failure: Error { case unavailable }

    func start(target: Int) throws -> AsyncStream<Update> {
        stop()
        detector = RakaatDetector(target: target)
        firstTime = nil
        lastTime = -.infinity
        exposureLocked = false
        preparation = RakaatPreparation()
        capture.beginConfiguration()
        for input in capture.inputs {
            capture.removeInput(input)
        }
        for output in capture.outputs {
            capture.removeOutput(output)
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input)
        else { capture.commitConfiguration(); throw Failure.unavailable }
        device = camera
        if capture.canSetSessionPreset(.low) {
            capture.sessionPreset = .low
        }
        capture.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard capture.canAddOutput(output) else { capture.commitConfiguration(); throw Failure.unavailable }
        capture.addOutput(output)
        capture.commitConfiguration()
        try camera.lockForConfiguration()
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 10 && $0.maxFrameRate >= 10 }) {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 10)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 10)
        }
        camera.unlockForConfiguration()
        let pair = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = pair.continuation
        capture.startRunning()
        return pair.stream
    }

    func stop() {
        preparationTimeout?.cancel()
        preparationTimeout = nil
        if capture.isRunning {
            capture.stopRunning()
        }
        continuation?.finish()
        continuation = nil
    }

    nonisolated func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        // AVFoundation delivers on our executor; the buffer never escapes this synchronous callback.
        nonisolated(unsafe) let isolatedSample = sampleBuffer
        assumeIsolated { camera in camera.process(isolatedSample) }
    }

    private func process(_ sample: CMSampleBuffer) {
        guard continuation != nil, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        guard time - lastTime >= 0.095 else { return }
        lastTime = time
        if firstTime == nil {
            firstTime = time
            // A stalled capture must not leave calibration waiting for another frame.
            preparationTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                await self?.expirePreparation()
            }
        }
        let elapsed = time - (firstTime ?? time)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            return
        }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var sum = 0.0, count = 0.0
        for y in Swift.stride(from: 0, to: height, by: 8) {
            for x in Swift.stride(from: 0, to: width, by: 8) {
                let i = y * stride + x * 4
                sum += 0.0722 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.2126 * Double(bytes[i + 2])
                count += 1
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        let light = sum / max(count, 1) / 255
        if detector.baseline == nil,
           let failure = preparation.sample(light, elapsed: elapsed)
        {
            continuation?.yield(Update(preview: nil, count: 0, calibrated: false,
                                       complete: false, failure: failure))
            finish()
            return
        }
        if !exposureLocked, let device {
            // Exposure compensation would otherwise erase the shadow we are measuring.
            guard !device.isAdjustingExposure else { publish(preview: nil); return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                device.unlockForConfiguration()
                exposureLocked = true
            } catch { finish(); return }
        }
        detector.sample(light, at: time)
        if detector.baseline != nil {
            preparationTimeout?.cancel()
            preparationTimeout = nil
        }
        let source = CIImage(cvPixelBuffer: buffer).oriented(.leftMirrored)
        let tiny = source.transformed(by: CGAffineTransform(scaleX: 24 / source.extent.width, y: 24 / source.extent.width))
        let blurred = tiny.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4]).cropped(to: tiny.extent)
        let preview = detector.complete ? nil : context.createCGImage(blurred, from: tiny.extent)
        publish(preview: preview)
        if detector.complete {
            // Finish the callback before the consumer stops the capture session.
            finish()
        }
    }

    private func expirePreparation() {
        guard !Task.isCancelled, continuation != nil, detector.baseline == nil else { return }
        continuation?.yield(Update(preview: nil, count: 0, calibrated: false,
                                   complete: false, failure: .unstable))
        finish()
    }

    private func finish() {
        preparationTimeout?.cancel()
        preparationTimeout = nil
        continuation?.finish()
        continuation = nil
    }

    private func publish(preview: CGImage?) {
        continuation?.yield(Update(preview: preview, count: detector.sujoodCount,
                                   calibrated: detector.baseline != nil, complete: detector.complete))
    }
}
