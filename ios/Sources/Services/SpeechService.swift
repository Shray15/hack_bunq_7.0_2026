import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechService: ObservableObject {
    @Published var isRecording  = false
    @Published var transcript   = ""
    @Published var isAuthorized = false

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine      = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func requestAuthorization() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.isAuthorized = (status == .authorized)
                    continuation.resume()
                }
            }
        }
    }

    func startRecording() throws {
        guard !isRecording else { return }

        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                if let result { self?.transcript = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { self?.stopRecording() }
            }
        }

        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
            recognitionRequest.append(buf)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        transcript  = ""
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask    = nil
        isRecording        = false
    }

    func speak(_ text: String) {
        let utterance          = AVSpeechUtterance(string: text)
        utterance.rate         = 0.52
        utterance.volume       = 0.85
        AVSpeechSynthesizer().speak(utterance)
    }
}
