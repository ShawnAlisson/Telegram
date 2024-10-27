import Foundation
import AVFoundation

/// A queue that manages the buffering and rendering of media samples
final class SampleBufferRenderQueue {
    // MARK: - Types
    
    /// Represents the result of a dequeue operation
    enum Result {
        case finished     // Queue has completed processing all samples
        case waiting     // Waiting for more samples
        case skip        // Current sample should be skipped
        case frame(CMSampleBuffer)  // Successfully dequeued sample
    }
    
    // MARK: - Private Properties
    
    /// Type of media being processed (audio/video)
    private let mediaType: AVMediaType
    
    /// Queue of sample buffers ready for rendering
    private var samplesQueue: [CMSampleBuffer] = []
    
    /// Total duration of samples in the queue
    private var prebufferedDuration: CMTime = .zero
    
    /// Queue of sample buffer producers
    private var queue = [SampleBufferProducer]()
    
    /// Current producer index in the queue
    private var pointer: Int = 0
    
    /// Time offset for the last producer
    private var lastProducerOffset: CMTime
    
    /// Presentation timestamp of the last processed frame
    private var lastFramePts = CMTime.zero
    
    /// Flag indicating if queue has been marked as complete
    private var isCompleted = false
    
    /// Serial queue for thread-safe buffer operations
    private let bufferSyncQueue = DispatchQueue(label: "TGPlayer.BufferSyncQueue")
    
    // MARK: - Initialization
    
    /// Creates a new sample buffer render queue
    /// - Parameters:
    ///   - mediaType: Type of media to process
    ///   - startTime: Initial timing reference
    init(mediaType: AVMediaType, startTime: CMTime) {
        self.mediaType = mediaType
        self.lastProducerOffset = startTime
    }
    
    // MARK: - Public Methods
    
    /// Dequeues the next sample based on the target time
    /// - Parameter targetTime: The desired presentation time
    /// - Returns: A Result indicating the outcome of the dequeue operation
    func dequeue(targetTime: CMTime) -> Result {
        bufferSyncQueue.sync {
            // Check if we've processed all producers
            if pointer >= queue.count {
                if samplesQueue.isEmpty {
                    return isCompleted ? .finished : .waiting
                }
                
                let sample = samplesQueue.removeFirst()
                prebufferedDuration = CMTimeSubtract(prebufferedDuration, CMSampleBufferGetDuration(sample))
                return .frame(sample)
            }
            
            let current = queue[pointer]
            
            // Handle finished producer
            guard !current.isFinished else {
                pointer += 1
                lastProducerOffset = lastFramePts
                lastFramePts = CMTime.zero
                return .skip
            }
            
            // Produce next sample
            guard let sampleBuffer = current.produce() else {
                return .skip
            }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            guard pts.isValid else {
                return .skip
            }
            
            // Adjust presentation timestamp
            let lastProducerOffsetConverted = CMTimeConvertScale(
                lastProducerOffset,
                timescale: pts.timescale,
                method: .default
            )
            let newPts = CMTime(
                value: lastProducerOffsetConverted.value + pts.value,
                timescale: pts.timescale
            )
            
            CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, newValue: newPts)
            
            // Update timing tracking
            lastFramePts = CMTimeMaximum(lastFramePts, newPts)
            samplesQueue.append(sampleBuffer)
            prebufferedDuration = CMTimeAdd(prebufferedDuration, CMSampleBufferGetDuration(sampleBuffer))
            
            if samplesQueue.isEmpty {
                return .waiting
            }
            
            // Return next frame
            let sample = samplesQueue.removeFirst()
            prebufferedDuration = CMTimeSubtract(prebufferedDuration, CMSampleBufferGetDuration(sample))
            
            return .frame(sample)
        }
    }
    
    /// Enqueues a new asset for processing
    /// - Parameters:
    ///   - asset: The asset to process
    ///   - timeOffset: Timing offset for the asset
    func enqueue(asset: AVAsset, timeOffset: CMTime) {
        guard let producer = makeProducer(for: asset, timeOffset: timeOffset) else {
            return
        }
        
        bufferSyncQueue.async { [self] in
            self.queue.append(producer)
        }
    }
    
    /// Marks the queue as complete
    func complete() {
        isCompleted = true
    }
    
    // MARK: - Private Methods
    
    /// Creates a new sample buffer producer for the given asset
    private func makeProducer(for asset: AVAsset, timeOffset: CMTime) -> SampleBufferProducer? {
        SampleBufferProducer(asset: asset, mediaType: mediaType, timeOffset: timeOffset)
    }
}
