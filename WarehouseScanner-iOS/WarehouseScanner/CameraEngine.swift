import AVFoundation
import Vision
import UIKit

/// Camera chạy liên tục. Cùng một luồng hình cho cả hai việc:
///  - Đọc barcode bằng AVCaptureMetadataOutput (nhanh, chạy trên chip chuyên dụng)
///  - Đọc chữ (mã kho in trên nhãn) bằng Vision, chỉ khi bật `ocrEnabled`, đọc nhanh (.fast) ~8 khung/giây, cứ 4 lần thì có 1 lần đọc kỹ (.accurate) để không bỏ sót chữ nhỏ.
final class CameraEngine: NSObject, ObservableObject,
                          AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    @Published private(set) var authorized: Bool? = nil     // nil = chưa hỏi
    @Published private(set) var torchOn = false

    /// Gọi trên main thread: danh sách mã vạch đang thấy trong khung hình.
    var onBarcodes: (([String]) -> Void)?
    /// Gọi trên main thread: các dòng chữ đọc được trong một khung hình.
    var onTextLines: (([String]) -> Void)?

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private var device: AVCaptureDevice?
    private var configured = false

    // Cờ dùng giữa nhiều luồng -> bảo vệ bằng lock
    private let lock = NSLock()
    private var _ocrEnabled = false
    private var _ocrBusy = false
    private var _lastOCR = Date.distantPast
    private var _ocrCount = 0
    var ocrEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _ocrEnabled }
        set { lock.lock(); _ocrEnabled = newValue; lock.unlock() }
    }

    private static let barcodeTypes: [AVMetadataObject.ObjectType] = [
        .code128, .code39, .code93, .ean13, .ean8, .upce, .itf14, .interleaved2of5, .qr, .pdf417, .dataMatrix, .aztec,
    ]

    // MARK: Vòng đời

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.authorized = true }
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.authorized = granted }
                if granted { self?.run() }
            }
        default:
            DispatchQueue.main.async { self.authorized = false }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func run() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            if self.configured, !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1080p: đủ nét để đọc chữ nhỏ trên nhãn mà vẫn nhẹ
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) else { return }
        session.addInput(input)
        device = cam

        // Lấy nét liên tục: quan trọng để đọc nhanh khi liên tục đưa kiện mới vào
        if (try? cam.lockForConfiguration()) != nil {
            if cam.isFocusModeSupported(.continuousAutoFocus) { cam.focusMode = .continuousAutoFocus }
            if cam.isExposureModeSupported(.continuousAutoExposure) { cam.exposureMode = .continuousAutoExposure }
            if cam.isSmoothAutoFocusSupported { cam.isSmoothAutoFocusEnabled = false }   // lấy nét nhanh hơn
            // Nhãn luôn ở gần (15-40 cm): giới hạn tầm lấy nét gần để không "săn nét" ra xa -> nét nhanh hơn rõ rệt
            if cam.isAutoFocusRangeRestrictionSupported { cam.autoFocusRangeRestriction = .near }
            if cam.isLowLightBoostSupported { cam.automaticallyEnablesLowLightBoostWhenAvailable = true }
            cam.unlockForConfiguration()
        }

        let meta = AVCaptureMetadataOutput()
        if session.canAddOutput(meta) {
            session.addOutput(meta)
            meta.setMetadataObjectsDelegate(self, queue: .main)
            meta.metadataObjectTypes = Self.barcodeTypes.filter { meta.availableMetadataObjectTypes.contains($0) }
        }

        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(video) { session.addOutput(video) }

        configured = true
    }

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let cam = self.device, cam.hasTorch, (try? cam.lockForConfiguration()) != nil else { return }
            cam.torchMode = cam.torchMode == .on ? .off : .on
            let on = cam.torchMode == .on
            cam.unlockForConfiguration()
            DispatchQueue.main.async { self.torchOn = on }
        }
    }

    // MARK: Barcode

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        if !codes.isEmpty { onBarcodes?(codes) }
    }

    // MARK: OCR

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let allowed = _ocrEnabled && !_ocrBusy && Date().timeIntervalSince(_lastOCR) > 0.1
        var accurate = false
        if allowed { _ocrBusy = true; _lastOCR = Date(); _ocrCount += 1; accurate = _ocrCount % 4 == 0 }
        lock.unlock()
        guard allowed, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest { [weak self] req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first }
                .filter { $0.confidence > 0.3 }
                .map { $0.string } ?? []
            if !lines.isEmpty { DispatchQueue.main.async { self?.onTextLines?(lines) } }
        }
        // Phần lớn khung hình đọc nhanh (.fast, ~vài chục ms) để ra kết quả sớm; 1/4 khung đọc kỹ cho chữ nhỏ/mờ
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = false     // mã không phải từ điển, tránh bị "sửa" sai

        // Camera sau ở chế độ dọc: ảnh gốc xoay 90° -> .right
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right, options: [:])
        try? handler.perform([request])

        lock.lock(); _ocrBusy = false; lock.unlock()
    }
}
