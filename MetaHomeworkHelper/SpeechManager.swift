import Foundation
import Speech
import AVFoundation

enum SpeechMode {
    case idle
    case trigger
    case transcription
}

@MainActor
class SpeechManager: ObservableObject {
    @Published var triggerDetected = false
    @Published var transcribedText = ""
    @Published var isListening = false
    @Published var mode: SpeechMode = .idle

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasInputTap = false
    private var activeRecognitionSessionID = 0
    private var silenceTask: Task<Void, Never>?
    private let silenceTimeout: TimeInterval = 5.0
    private var lastSpeechActivityAt = Date()

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    completion(false)
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        completion(granted)
                    }
                }
            }
        }
    }

    func startTriggerListening() {
        mode = .trigger
        triggerDetected = false
        startRecognition { [weak self] transcript in
            guard let self else { return }
            if transcript.lowercased().contains("help me with my homework") {
                self.triggerDetected = true
                self.stopRecognition()
            }
        }
    }

    func startTranscriptionListening() {
        mode = .transcription
        transcribedText = ""
        lastSpeechActivityAt = Date()
        scheduleSilenceTimeout()
        startRecognition { [weak self] transcript in
            guard let self else { return }
            self.transcribedText = transcript
        }
    }

    func stopRecognition() {
        activeRecognitionSessionID += 1
        silenceTask?.cancel()
        silenceTask = nil
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        mode = .idle
    }

    // MARK: - Private

    private func startRecognition(onTranscript: @escaping (String) -> Void) {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        stopRecognition()
        let sessionID = activeRecognitionSessionID

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            guard let self else { return }
            if self.mode == .transcription, self.hasAudibleSpeech(in: buffer) {
                Task { @MainActor in
                    guard self.activeRecognitionSessionID == sessionID else { return }
                    self.lastSpeechActivityAt = Date()
                }
            }
        }
        hasInputTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            return
        }

        isListening = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            guard self.activeRecognitionSessionID == sessionID else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    guard self.activeRecognitionSessionID == sessionID else { return }
                    onTranscript(transcript)
                    if self.mode == .trigger && result.isFinal {
                        self.stopRecognition()
                    }
                }
            }
            if error != nil {
                Task { @MainActor in
                    guard self.activeRecognitionSessionID == sessionID else { return }
                    self.stopRecognition()
                }
            }
        }
    }

    private func scheduleSilenceTimeout() {
        guard mode == .transcription else { return }
        silenceTask?.cancel()
        let sessionID = activeRecognitionSessionID
        silenceTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                if self.activeRecognitionSessionID != sessionID {
                    return
                }
                if self.mode == .transcription,
                   Date().timeIntervalSince(self.lastSpeechActivityAt) >= self.silenceTimeout {
                    self.stopRecognition()
                    return
                }
            }
        }
    }

    private func hasAudibleSpeech(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }
        let channel = channelData[0]
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return false }

        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channel[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        return rms > 0.01
    }
}
