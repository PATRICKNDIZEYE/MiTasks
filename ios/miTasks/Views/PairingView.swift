import SwiftUI
import AVFoundation

/// First run: point the phone at the widget. Scanning the QR is the path that
/// avoids typing a 16-character key by hand.
struct PairingView: View {
    @EnvironmentObject var store: Store
    @State private var manual = ""
    @State private var scanning = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(Theme.brandDot).frame(width: 10, height: 10)
                    Text("miTasks").font(Theme.display())
                }
                Eyebrow(text: "Connect to your Mac")
                    .padding(.top, Theme.Space.xs)

                Text("Open the widget on your Mac and scan its pairing code, or paste the link it shows you.")
                    .font(Theme.text(Theme.Size.body))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(Theme.Space.s6)
                    .padding(.top, Theme.Space.l)

                Button {
                    scanning = true
                } label: {
                    Label("Scan pairing code", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.crew(.primary, height: Theme.Height.large, fullWidth: true))
                .padding(.top, Theme.Space.xxl)

                HStack(spacing: Theme.Space.m) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("or").font(Theme.text(Theme.Size.xs)).foregroundStyle(Theme.faint)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                .padding(.vertical, Theme.Space.xl)

                TextField("http://10.0.0.5:43917/?key=…", text: $manual)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(Theme.mono(Theme.Size.m))
                    .crewInput()

                Button("Connect") {
                    _ = store.pair(with: manual)
                }
                .buttonStyle(.crew(.secondary, height: Theme.Height.large, fullWidth: true))
                .padding(.top, Theme.Space.s)
                .disabled(manual.isEmpty)
                .opacity(manual.isEmpty ? 0.5 : 1)

                if let err = store.lastError {
                    Text(err)
                        .font(Theme.text(Theme.Size.s))
                        .foregroundStyle(Theme.red)
                        .padding(.top, Theme.Space.m)
                }

                Spacer()

                Text("Your Mac and iPhone need to be on the same Wi‑Fi, and the widget has to be running — it's the server.")
                    .font(Theme.text(Theme.Size.s))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(Theme.Space.xxs)
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.vertical, Theme.Space.s40)
        }
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $scanning) {
            ScannerSheet { code in
                scanning = false
                _ = store.pair(with: code)
            }
        }
    }
}

private struct ScannerSheet: View {
    let onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScanner(onFound: onFound)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

/// Thin AVFoundation wrapper — SwiftUI has no native camera QR reader.
struct QRScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onFound: (String) -> Void
        private var handled = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            // A QR stays in frame for many frames; only the first one counts.
            guard !handled,
                  let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue
            else { return }
            handled = true
            DispatchQueue.main.async { self.onFound(value) }
        }
    }

    final class ScannerController: UIViewController {
        weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !session.isRunning else { return }
            // startRunning blocks; keeping it off the main thread avoids a hitch.
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }
    }
}
