import Foundation
import AVFoundation

/// Protocol defining core rendering functionality for custom targets
protocol CustomTargetRendering: AnyObject {
    /// Prepares the renderer with an initial time offset
    /// - Parameter startTimeOffset: The starting time offset for rendering
    func prepare(startTimeOffset: CMTime)
    
    /// Enqueues a media file for rendering
    /// - Parameters:
    ///   - url: URL of the media file
    ///   - timeOffset: Time offset for the enqueued file
    func enqueueFile(withURL url: URL, timeOffset: CMTime)
    
    /// Cancels the current rendering operation
    func cancel()
    
    /// Completes the rendering operation
    func complete()
}

/// Represents the current state of media playback
enum PlaybackStatus {
    case playing   // Media is currently playing
    case finished  // Playback has completed
    case buffering // Media is buffering
}

/// Callback type for playback status changes
typealias PlaybackStatusChangeCallback = (PlaybackStatus) -> Void

/// Protocol defining video rendering functionality
protocol CustomVideoRendering: CustomTargetRendering, AVQueuedSampleBufferRendering {
    /// Attaches the renderer to a custom player
    /// - Parameter player: The custom player to attach to
    func attach(player: CustomPlayer)
    
    /// Sets up observation for playback status changes
    /// - Parameter onStatusChange: Callback to handle status changes
    func observeStatus(_ onStatusChange: @escaping PlaybackStatusChangeCallback)
    
    /// Sets up observation for quality change requests
    /// - Parameter onQualityChangeRequest: Callback to handle quality change requests
    func observeQualityDownchangeRequest(_ onQualityChangeRequest: @escaping () -> Void)
}

/// Custom implementation of AVSampleBufferDisplayLayer that handles video rendering
class CustomPlayerLayer: AVSampleBufferDisplayLayer, CustomVideoRendering {
    // MARK: - Private Properties
    
    private var renderLoop: RenderTarget<AVSampleBufferDisplayLayer>?
    private var onStatusChange: PlaybackStatusChangeCallback?
    private var onQualityChangeRequest: (() -> Void)?
    
    // MARK: - CustomTargetRendering Implementation
    
    func prepare(startTimeOffset: CMTime) {
        renderLoop = RenderTarget(
            target: self,
            mediaType: .video,
            startTime: startTimeOffset,
            onStatusChange: { [weak self] newStatus in
                // Map internal status to public PlaybackStatus
                switch newStatus {
                case .playing:
                    self?.onStatusChange?(.playing)
                case .finished:
                    self?.onStatusChange?(.finished)
                case .waiting:
                    self?.onStatusChange?(.buffering)
                }
            },
            onWaitingIntervalEnd: { [weak self] duration in
                // Trigger quality change request if buffering exceeds 4 seconds
                if duration >= 4.0 {
                    self?.onQualityChangeRequest?()
                }
            }
        )
        renderLoop?.waitForEnqueue()
    }
    
    func enqueueFile(withURL url: URL, timeOffset: CMTime) {
        guard let renderLoop = self.renderLoop else {
            assertionFailure("Call prepare() before enqueue assets")
            return
        }
        
        let asset = AVAsset(url: url)
        renderLoop.enqueue(asset: asset, timeOffset: timeOffset)
    }
    
    // MARK: - CustomVideoRendering Implementation
    
    func attach(player: CustomPlayer) {
        player.attach(layer: self)
    }
    
    func observeStatus(_ onStatusChange: @escaping PlaybackStatusChangeCallback) {
        self.onStatusChange = onStatusChange
    }
    
    func observeQualityDownchangeRequest(_ onQualityChangeRequest: @escaping () -> Void) {
        self.onQualityChangeRequest = onQualityChangeRequest
    }
    
    func complete() {
        renderLoop?.complete()
    }
    
    func cancel() {
        renderLoop?.stop()
        renderLoop = nil
    }
}
