import Foundation
import AVFoundation

/// A generic class that manages rendering of media samples to an AVQueuedSampleBufferRendering target
final class RenderTarget<Target: AVQueuedSampleBufferRendering> {
    // MARK: - Types
    
    /// Represents the current rendering status
    enum Status: Equatable {
        case playing  // Currently rendering frames
        case finished // Rendering completed
        case waiting  // Waiting for more frames
    }
    
    // MARK: - Private Properties
    
    /// The target renderer (weak to avoid retain cycles)
    private weak var target: Target?
    
    /// Queue for managing sample buffers
    private var renderBuffer: SampleBufferRenderQueue
    
    /// Queue for rendering operations
    private let renderQueue: DispatchQueue
    
    /// Type of media being rendered (audio/video)
    private let mediaType: AVMediaType
    
    /// Current rendering status with callback notification
    private var status: Status = .finished {
        didSet {
            if oldValue != status {
                onStatusChange?(status)
            }
        }
    }
    
    /// Callback for status changes
    private let onStatusChange: ((Status) -> Void)?
    
    /// Callback for monitoring waiting intervals
    private let onWaitingIntervalEnd: ((TimeInterval) -> Void)?
    
    /// Timestamp when waiting started (nil if not waiting)
    private var waitingIntervalStarted: TimeInterval? = CACurrentMediaTime()
    
    /// Initial render timing reference
    private let startTime: CMTime
    
    // MARK: - Initialization
    
    /// Creates a new render target
    /// - Parameters:
    ///   - target: The rendering destination
    ///   - mediaType: Type of media to render (audio/video)
    ///   - startTime: Initial timing reference
    ///   - renderQueue: Queue for rendering operations
    ///   - onStatusChange: Callback for status updates
    ///   - onWaitingIntervalEnd: Callback for waiting interval completion
    init(
        target: Target,
        mediaType: AVMediaType,
        startTime: CMTime,
        renderQueue: DispatchQueue = DispatchQueue(label: "CustomPlayer.RenderLoop", qos: .userInitiated),
        onStatusChange: ((Status) -> Void)?,
        onWaitingIntervalEnd: ((TimeInterval) -> Void)?
    ) {
        self.startTime = startTime
        self.target = target
        self.renderQueue = renderQueue
        self.renderBuffer = SampleBufferRenderQueue(mediaType: mediaType, startTime: startTime)
        self.mediaType = mediaType
        self.onStatusChange = onStatusChange
        self.onWaitingIntervalEnd = onWaitingIntervalEnd
    }
    
    // MARK: - Public Methods
    
    /// Begins waiting for and processing media data
    func waitForEnqueue() {
        guard let target else {
            return
        }
        
        target.requestMediaDataWhenReady(on: renderQueue) { [self] in
            while target.isReadyForMoreMediaData {
                let targetTime = CMTimebaseGetTime(target.timebase)
                
                switch renderBuffer.dequeue(targetTime: targetTime) {
                case .finished:
                    status = .finished
                    stop()
                    return
                    
                case let .frame(buffer):
                    status = .playing
                    
                    // Handle end of waiting interval if applicable
                    if let waitingIntervalStarted {
                        self.onWaitingIntervalEnd?(CACurrentMediaTime() - waitingIntervalStarted)
                        self.waitingIntervalStarted = nil
                    }
                    
                    target.enqueue(buffer)
                    
                case .skip:
                    continue
                    
                case .waiting:
                    status = .waiting
                    
                    // Start tracking waiting interval if not already
                    if waitingIntervalStarted == nil {
                        waitingIntervalStarted = CACurrentMediaTime()
                    }
                    
                    // Brief sleep to prevent tight loop
                    usleep(10000) // 10ms
                }
            }
        }
    }
    
    /// Enqueues a new asset for rendering
    /// - Parameters:
    ///   - asset: The asset to render
    ///   - timeOffset: Timing offset for the asset
    func enqueue(asset: AVAsset, timeOffset: CMTime) {
        renderBuffer.enqueue(asset: asset, timeOffset: timeOffset)
    }
    
    /// Marks rendering as complete
    func complete() {
        renderBuffer.complete()
    }
    
    /// Stops rendering and cleans up resources
    func stop() {
        renderBuffer.complete()
        target?.flush()
        target?.stopRequestingMediaData()
    }
}
