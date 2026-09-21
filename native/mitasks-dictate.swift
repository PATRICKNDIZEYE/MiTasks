// mitasks-dictate — on-device speech capture for miTasks.
//
// Transcription happens locally through the Speech framework, so recordings
// never leave the Mac. Only the resulting text is sent anywhere, and only when
// the user has set a Jev key. Every line of stdout is one JSON object:
//
//   {"partial": "send the report"}     as you speak
//   {"final": "send the report today"} once
//   {"error": "..."}                   on failure, with a non-zero exit
//
//   mitasks-dictate auth        current permission, never prompts
//   mitasks-dictate request     triggers the mic + speech prompts
//   mitasks-dictate listen [--seconds N]
//
// Listening stops when stdin closes, on SIGTERM, or after --seconds.

import AVFoundation
import Foundation
import Speech

// MARK: - Output

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let line = String(data: data, encoding: .utf8)
    else { return }
    print(line)
    fflush(stdout)
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    emit(["error": message])
    exit(code)
}

// MARK: - Permission

func speechStatusName(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .authorized: return "authorized"
    @unknown default: return "unknown"
    }
}

func micStatusName(_ s: AVAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .authorized: return "authorized"
    @unknown default: return "unknown"
    }
}

func reportAuth() {
    emit([
        "speech": speechStatusName(SFSpeechRecognizer.authorizationStatus()),
        "microphone": micStatusName(AVCaptureDevice.authorizationStatus(for: .audio)),
    ])
}

/// Both prompts have to be answered before listening can start. TCC delivers
/// them on the main queue, so the thread is pumped rather than blocked — a
/// semaphore here would deadlock and the dialog would never appear.
func requestAccess() {
    var speechDone = false
    var micDone = false

    SFSpeechRecognizer.requestAuthorization { _ in speechDone = true }
    AVCaptureDevice.requestAccess(for: .audio) { _ in micDone = true }

    let deadline = Date().addingTimeInterval(120)
    while (!speechDone || !micDone) && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    reportAuth()
}

// MARK: - Listening

final class Dictator {
    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var finished = false

    init?(locale: Locale) {
        guard let r = SFSpeechRecognizer(locale: locale) else { return nil }
        recognizer = r
    }

    var isFinished: Bool { finished }

    func start() throws {
        guard recognizer.isAvailable else {
            fail("speech recognizer unavailable — check the dictation language is downloaded")
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Keeps audio on the machine even when a server round-trip would be
        // faster; this is someone's private voice memo.
        if #available(macOS 13, *) { req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { fail("no usable microphone input") }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if text != self.transcript {
                    self.transcript = text
                    emit(["partial": text])
                }
                if result.isFinal { self.complete() }
            }
            if error != nil { self.complete() }
        }
    }

    /// Ends the audio stream and lets the recognizer flush its final result.
    func stop() {
        guard !finished else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()

        // Give the recognizer a moment to emit its final pass before exiting.
        let deadline = Date().addingTimeInterval(3)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        complete()
    }

    private func complete() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        emit(["final": transcript])
    }
}

// MARK: - Arguments

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "auth"

func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch command {
case "auth":
    reportAuth()

case "request":
    requestAccess()

case "listen":
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
        fail("speech not authorized", code: 2)
    }
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
        fail("microphone not authorized", code: 2)
    }

    let localeId = flag("locale") ?? Locale.current.identifier
    guard let dictator = Dictator(locale: Locale(identifier: localeId)) else {
        fail("no recognizer for locale \(localeId)")
    }

    do { try dictator.start() } catch { fail("could not start audio: \(error.localizedDescription)") }

    let maxSeconds = Double(flag("seconds") ?? "") ?? 60
    let deadline = Date().addingTimeInterval(maxSeconds)

    // The parent closing stdin is the normal stop signal; SIGTERM is the
    // fallback when the app is quitting outright.
    signal(SIGTERM) { _ in exit(0) }
    signal(SIGINT) { _ in exit(0) }

    let stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO)
    var stdinClosed = false
    stdinSource.setEventHandler {
        var byte: UInt8 = 0
        if read(STDIN_FILENO, &byte, 1) <= 0 { stdinClosed = true }
    }
    stdinSource.resume()

    while !dictator.isFinished && !stdinClosed && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    dictator.stop()

default:
    fail("unknown command: \(command)")
}
