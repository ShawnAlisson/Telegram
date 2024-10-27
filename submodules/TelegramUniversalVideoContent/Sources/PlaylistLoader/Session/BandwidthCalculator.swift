import Foundation

/// A thread-safe calculator for network bandwidth estimation
/// Uses a rolling average of transfer rates to provide stable bandwidth measurements
final class BandwidthCalculator {
    // MARK: - Static Properties
    
    /// Shared instance for global bandwidth calculation
    static let shared = BandwidthCalculator()
    
    // MARK: - Public Properties
    
    /// Current estimated bandwidth in bits per second
    /// Returns nil if insufficient samples are available
    var bandwidth: Int? {
        return buffer.count < 4 ? nil : _bandwidth
    }
    
    // MARK: - Private Properties
    
    /// Calculates the average bandwidth from the buffer
    /// Returns 0 if buffer is empty
    private var _bandwidth: Int {
        if buffer.isEmpty { return 0 }
        return buffer.reduce(0, +) / buffer.count
    }
    
    /// Thread-safe storage for bandwidth samples
    /// Each entry represents bits per second for a transfer
    @ThreadSafe
    private var buffer: [Int] = []
    
    /// Maximum number of samples to store before consolidation
    private let shrinkThreshold = 20
    
    // MARK: - Initialization
    
    /// Creates a new bandwidth calculator
    init() { }
    
    // MARK: - Public Methods
    
    /// Adds a new bandwidth sample based on transfer time and bytes
    /// - Parameters:
    ///   - time: Duration of the transfer in seconds
    ///   - bytes: Number of bytes transferred
    /// - Note: Automatically consolidates samples when buffer reaches threshold
    func add(time: TimeInterval, bytes: Int) {
        // Validate input
        guard !time.isZero, bytes > 0 else {
            return
        }
        
        // Convert to bits per second
        let bitsPerSecond = Int(Double(bytes) * 8.0 / time)
        
        // Consolidate buffer if threshold reached
        if buffer.count == shrinkThreshold {
            buffer = [_bandwidth]
        }
        
        // Add new sample
        buffer.append(bitsPerSecond)
    }
}
