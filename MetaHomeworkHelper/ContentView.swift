import SwiftUI

struct ContentView: View {
    @StateObject private var wearables = WearablesManager()
    @StateObject private var speech = SpeechManager()

    @State private var flowState: FlowState = .notRegistered

    enum FlowState {
        case notRegistered
        case registered
        case streaming
        case photoCaptured
        case transcriptionComplete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch flowState {
                case .notRegistered:
                    notRegisteredView
                case .registered:
                    registeredView
                case .streaming:
                    streamingView
                case .photoCaptured:
                    photoCapturedView
                case .transcriptionComplete:
                    transcriptionCompleteView
                }
            }
            .padding()
            .navigationTitle("MetaHomeworkHelper")
        }
        .onChange(of: wearables.registrationState) { _, newState in
            if newState == .registered {
                startStreamAndListen()
            }
        }
        .onChange(of: speech.triggerDetected) { _, detected in
            if detected && flowState == .streaming {
                handleTriggerDetected()
            }
        }
        .onChange(of: speech.mode) { _, newMode in
            if newMode == .idle && flowState == .streaming {
                flowState = .registered
            }
        }
        .onChange(of: wearables.capturedPhoto) { _, photo in
            if photo != nil && flowState == .photoCaptured {
                wearables.stopStream()
                speech.startTranscriptionListening()
            }
        }
    }

    // MARK: - Subviews

    private var notRegisteredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Connect your Ray-Ban Meta glasses to get started.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Connect Glasses") {
                wearables.register()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var registeredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Glasses connected!")
                .font(.headline)
            Button("Start") {
                startStreamAndListen()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .onAppear {
            startStreamAndListen()
        }
    }

    private var streamingView: some View {
        VStack(spacing: 16) {
            if let frame = wearables.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black)
                    .frame(height: 300)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }

            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                Text("Listening for \"help me with my homework\"...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let streamErrorMessage = wearables.streamErrorMessage {
                Text(streamErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var photoCapturedView: some View {
        VStack(spacing: 16) {
            if let photo = wearables.capturedPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                Text("Speak your instructions...")
                    .font(.subheadline)
            }

            if speech.isListening {
                Text("Listening...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !speech.transcribedText.isEmpty {
                Text(speech.transcribedText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var transcriptionCompleteView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let photo = wearables.capturedPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Instructions")
                        .font(.headline)
                    Text(speech.transcribedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Start Over") {
                    resetFlow()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Actions

    private func startStreamAndListen() {
        flowState = .streaming
        speech.requestPermissions { granted in
            guard granted else {
                flowState = .registered
                return
            }
            wearables.startStream()
            speech.startTriggerListening()
        }
    }

    private func handleTriggerDetected() {
        wearables.capturePhoto()
        flowState = .photoCaptured
    }

    private func resetFlow() {
        speech.stopRecognition()
        wearables.capturedPhoto = nil
        speech.transcribedText = ""
        speech.triggerDetected = false
        flowState = .registered
    }
}

#Preview {
    ContentView()
}
