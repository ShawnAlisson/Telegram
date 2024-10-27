import Foundation
import AVFoundation

/// Protocol defining requirements for custom audio rendering capabilities
protocol CustomAudioRendering: CustomTargetRendering, AVQueuedSampleBufferRendering {
    /// The volume level of the audio renderer
    var volume: Float { get set }
}

/// A custom audio renderer that manages audio sample buffer rendering and playback
class CustomAudioRenderer: AVSampleBufferAudioRenderer, CustomAudioRendering {
    // MARK: - Private Properties
    
    /// The render loop responsible for managing audio sample buffer rendering
    private var renderLoop: RenderTarget<AVSampleBufferAudioRenderer>?
    
    /// Callback for handling playback status changes
    private var onStatusChange: PlaybackStatusChangeCallback?
    
    // MARK: - Public Methods
    
    /// Prepares the renderer for audio playback
    /// - Parameter startTimeOffset: The initial time offset for playback
    func prepare(startTimeOffset: CMTime) {
        renderLoop = RenderTarget(
            target: self,
            mediaType: .audio,
            startTime: startTimeOffset,
            onStatusChange: nil,
            onWaitingIntervalEnd: nil
        )
        renderLoop?.waitForEnqueue()
    }
    
    /// Enqueues an audio file for playback
    /// - Parameters:
    ///   - url: The URL of the audio file to enqueue
    ///   - timeOffset: The time offset at which to begin playing the audio file
    func enqueueFile(withURL url: URL, timeOffset: CMTime) {
        guard let renderLoop = self.renderLoop else {
            assertionFailure("Call prepare() before enqueue assets")
            return
        }
        
        let asset = AVAsset(url: url)
        renderLoop.enqueue(asset: asset, timeOffset: timeOffset)
    }
    
    /// Cancels the current render loop and cleans up resources
    func cancel() {
        renderLoop?.stop()
        renderLoop = nil
    }
    
    /// Completes the current render loop
    func complete() {
        renderLoop?.complete()
    }
}
