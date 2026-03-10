import Foundation
import UIKit
import MWDATCore
import MWDATCamera

@MainActor
class WearablesManager: ObservableObject {
    @Published var registrationState: RegistrationState = .unavailable
    @Published var capturedPhoto: UIImage?
    @Published var isStreaming = false
    @Published var currentFrame: UIImage?
    @Published var streamState: StreamSessionState = .stopped
    @Published var streamErrorMessage: String?

    private var streamSession: StreamSession?
    private var tokens = [any AnyListenerToken]()

    func register() {
        let token = Wearables.shared.addRegistrationStateListener { [weak self] state in
            Task { @MainActor in
                self?.registrationState = state
            }
        }
        tokens.append(token)

        Task {
            try? await Wearables.shared.startRegistration()
        }
    }

    func startStream() {
        Task {
            streamErrorMessage = nil
            currentFrame = nil

            let hasPermission = await ensureCameraPermission()
            guard hasPermission else {
                streamErrorMessage = "Camera access for Meta Wearables was denied."
                return
            }

            let config = StreamSessionConfig(
                videoCodec: .raw,
                resolution: .medium,
                frameRate: 24
            )
            let session = StreamSession(
                streamSessionConfig: config,
                deviceSelector: AutoDeviceSelector(wearables: Wearables.shared)
            )
            self.streamSession = session

            let frameToken = session.videoFramePublisher.listen { [weak self] frame in
                let image = frame.makeUIImage()
                Task { @MainActor in
                    self?.currentFrame = image
                }
            }
            tokens.append(frameToken)

            let photoToken = session.photoDataPublisher.listen { [weak self] photoData in
                let image = UIImage(data: photoData.data)
                Task { @MainActor in
                    self?.capturedPhoto = image
                }
            }
            tokens.append(photoToken)

            let stateToken = session.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    self?.streamState = state
                    self?.isStreaming = (state == .streaming)
                }
            }
            tokens.append(stateToken)

            let errorToken = session.errorPublisher.listen { [weak self] error in
                Task { @MainActor in
                    self?.streamErrorMessage = "Stream error: \(String(describing: error))"
                }
            }
            tokens.append(errorToken)

            await session.start()
        }
    }

    func capturePhoto() {
        streamSession?.capturePhoto(format: .jpeg)
    }

    func stopStream() {
        if let streamSession {
            Task {
                await streamSession.stop()
            }
        }
        streamSession = nil
        isStreaming = false
        streamState = .stopped
        currentFrame = nil
        tokens.removeAll()
    }

    private func ensureCameraPermission() async -> Bool {
        let currentStatus = try? await Wearables.shared.checkPermissionStatus(.camera)
        if currentStatus == .granted {
            return true
        }

        let requestedStatus = try? await Wearables.shared.requestPermission(.camera)
        return requestedStatus == .granted
    }
}
