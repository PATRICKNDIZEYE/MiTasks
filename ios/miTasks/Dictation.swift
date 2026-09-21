import Foundation
import AVFoundation
import Speech

/// On-device speech capture. The audio never leaves the phone — only the
/// transcript is sent on, and only to be classified.
@MainActor
final class Dictation: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case working(String)
        case denied(String)
    }

    @Published var phase: Phase = .idle
    @Published var transcript = ""

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isListening: Bool { phase == .listening }

    // MARK: - Permission

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else {
            phase = .denied("Speech recognition is off — Settings › Privacy › Speech Recognition")
            return false
        }

        let mic = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard mic else {
            phase = .denied("Microphone is off — Settings › Privacy › Microphone")
            return false
        }
        return true
    }

    // MARK: - Capture

    func start() async {
        guard phase == .idle || isDenied else { return }
        guard await authorize() else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            phase = .denied("Speech recognition isn't available right now")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            phase = .denied("Couldn't start the microphone")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Prefer on-device so a voice memo never travels, even when the
        // network path would be quicker.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            phase = .denied("No microphone input")
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        engine.prepare()
        do { try engine.start() } catch {
            phase = .denied("Couldn't start the microphone")
            return
        }

        transcript = ""
        phase = .listening

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.teardown()
                }
            }
        }
    }

    /// Ends capture and returns whatever was heard.
    func stop() async -> String {
        guard isListening else { return transcript }
        teardown()
        // Let the recognizer flush its final pass before the caller acts on it.
        try? await Task.sleep(for: .milliseconds(350))
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        teardown()
        transcript = ""
        phase = .idle
    }

    private func teardown() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private var isDenied: Bool {
        if case .denied = phase { return true }
        return false
    }
}
