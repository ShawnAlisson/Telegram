import Foundation
import AVFoundation

/// A class responsible for reading and producing sample buffers from an AVAsset
/// Used for streaming media data from assets like video or audio files
final class SampleBufferProducer {
    // MARK: - Public Properties
    
    /// The underlying asset reader
    let reader: AVAssetReader
    
    /// Indicates whether the producer has finished reading all available samples
    private(set) var isFinished = false
    
    // MARK: - Private Properties
    
    /// The output interface for reading track data
    private let output: AVAssetReaderTrackOutput
    
    /// Flag to track if reading has been initiated
    private var isReadingStarted = false
    
    // MARK: - Initialization
    
    /// Creates a new sample buffer producer
    /// - Parameters:
    ///   - asset: The source asset to read from
    ///   - mediaType: Type of media to read (audio/video)
    ///   - timeOffset: Starting time offset for reading
    /// - Returns: nil if the producer cannot be created with the given parameters
    init?(asset: AVAsset, mediaType: AVMediaType, timeOffset: CMTime) {
        // Initialize asset reader
        guard let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        
        // Configure time range from offset to infinity
        reader.timeRange = CMTimeRange(start: timeOffset, end: .positiveInfinity)
        
        self.reader = reader
        
        // Find and configure the media track
        guard let track = asset.tracks(withMediaType: mediaType).first else {
            return nil
        }
        
        // Create output with native format (nil settings)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        
        self.output = output
    }
    
    // MARK: - Public Methods
    
    /// Produces the next sample buffer from the asset
    /// - Returns: The next CMSampleBuffer, or nil if no more samples are available
    /// or if an error occurred
    func produce() -> CMSampleBuffer? {
        // Start reading if not already started
        if !isReadingStarted {
            if reader.startReading() {
                isReadingStarted = true
            } else {
                return nil
            }
        }
        
        // Get next sample buffer
        let buffer = output.copyNextSampleBuffer()
        
        // Update finished status if we've reached the end
        isFinished = reader.status != .unknown && buffer == nil
        
        // Clean up if finished
        if isFinished {
            reader.cancelReading()
        }
        
        return buffer
    }
}
