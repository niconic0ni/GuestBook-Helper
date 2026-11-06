import SwiftUI
import AVFoundation
import Vision
import CoreMedia
import CoreVideo
import ImageIO
import UIKit

struct ScannerSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let onScanned: (String) -> Void

    @State private var message = "将 (S) Serial No. 下方的条码放入框内"

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                BarcodeScannerView { rawCode in
                    guard let serial = SerialScanParser.normalizedSerial(from: rawCode) else {
                        message = "仅支持以 S 开头的一维序列号条码"
                        return
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onScanned(serial)
                    presentationMode.wrappedValue.dismiss()
                }
                .edgesIgnoringSafeArea(.all)

                scannerOverlay
            }
            .gbInlineTitle("扫描序列号")
            .navigationBarItems(leading: Button("取消") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environment(\.colorScheme, .dark)
        .accentColor(.white)
    }

    private var scannerOverlay: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
                    .frame(width: 300, height: 108)
                Image(systemName: SFSymbol.available("barcode", fallback: "camera"))
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.16))
            }
            VStack(spacing: 7) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("支持 Code128 / Code39 · 仅识别 S 开头的序列号条码\n避开 IMEI 与 UPC 条码，识别后自动去除 S 填入搜索框")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 22)
            Spacer()
        }
        .padding(.top, 30)
        .padding(.bottom, 44)
        .allowsHitTesting(false)
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        BarcodeScannerViewController(onCode: onCode)
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

final class BarcodeScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.n1c0.guestbookhelper.scanner.session")
    private let videoQueue = DispatchQueue(label: "com.n1c0.guestbookhelper.scanner.video")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasDelivered = false
    private var lastScanTime = CACurrentMediaTime()
    private let onCode: (String) -> Void

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func requestCamera() {
        guard AVCaptureDevice.default(for: .video) != nil else {
            showMessage("此设备没有可用相机")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.showMessage("请在“设置”中允许 GuestBook Helper 使用相机")
                    }
                }
            }
        default:
            showMessage("请在“设置”中允许 GuestBook Helper 使用相机")
        }
    }

    private func configureSession() {
        guard previewLayer == nil else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showMessage("无法打开相机")
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            showMessage("无法初始化相机扫描")
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        configureCameraDevice(device)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func configureCameraDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            // The camera still works with the system defaults if tuning fails.
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func showMessage(_ text: String) {
        DispatchQueue.main.async {
            let label = UILabel()
            label.text = text
            label.textColor = .white
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 28),
                label.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -28)
            ])
        }
    }

    private var visionOrientation: CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !hasDelivered else { return }
        let now = CACurrentMediaTime()
        guard now - lastScanTime >= 0.22 else { return }
        lastScanTime = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.code128, .code39]
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: visionOrientation,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return
        }

        for observation in request.results ?? [] {
            guard let payload = observation.payloadStringValue else { continue }
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            // The serial barcode starts with S. IMEI/MEID and UPC barcodes on
            // the same box do not, so this also rejects them.
            guard trimmed.count > 1, trimmed.uppercased().hasPrefix("S") else { continue }
            hasDelivered = true
            stopSession()
            DispatchQueue.main.async { [weak self] in
                self?.onCode(trimmed)
            }
            return
        }
    }
}
