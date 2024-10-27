import Foundation
import CoreMedia
import AVFoundation

/// A custom video player implementation that manages playback, buffering, and resolution control
final class CustomPlayer {
    // MARK: - Public Properties
    
    /// Current playback rate. Setting this value updates both player rate and base rate
    var rate: Float {
        get { _player?.rate ?? 0.0 }
        set {
            _player?.rate = newValue
            baseRate = newValue
        }
    }
    
    /// Current playback volume
    var volume: Float {
        get { _player?.volume ?? 0.0 }
        set { _player?.volume = newValue }
    }
    
    /// Callback triggered when player state updates
    var onUpdate: (() -> Void)?
    
    /// Returns true if media is currently playing (rate > 0)
    var isPlaying: Bool {
        !rate.isZero
    }
    
    /// Duration of buffered content in seconds
    var bufferedTime: TimeInterval {
        _player?.loadedProgress?.duration ?? 0.0
    }
    
    /// Offset of buffered content in seconds
    var bufferedTimeOffset: TimeInterval {
        _player?.loadedProgress?.offset ?? 0.0
    }
    
    /// Array of available video resolution options
    var availableResolutions: [Int] {
        _player?.availableResolutions ?? []
    }
    
    /// Currently active video resolution
    var currentResolution: Int? {
        _player?.currentResolution
    }
    
    /// Selected video resolution. Setting this value updates player resolution mode
    var selectedResolution: Int? {
        didSet {
            if let selectedResolution {
                _player?.setManualResolution(selectedResolution)
            } else {
                _player?.setAutomaticResolution()
            }
        }
    }
    
    // MARK: - Private Properties
    
    private(set) var currentTime: CMTime = .indefinite
    private(set) var isBuffering: Bool = false
    private(set) var duration: TimeInterval?
    
    private var _player: CustomPlayerBase?
    private var _layer: CustomPlayerLayer?
    
    private var baseRate: Float = 0.0
    private var didInitiallyStart = false
    private var isManuallyPaused = false
    private var isCompleted = false
    
    // MARK: - Initialization
    
    init() { }
    
    // MARK: - Public Methods
    
    /// Attaches a player layer for video rendering
    /// - Parameter layer: The CustomPlayerLayer to attach
    func attach(layer: CustomPlayerLayer) {
        _layer = layer
    }
    
    /// Sets up the player with new media content
    /// - Parameter url: URL of the media to play
    func setContent(url: URL) {
        let player = CustomPlayerBase(url: url)
        _player = player
        
        configurePlayerCallbacks(player)
        
        if let _layer {
            player.attach(layer: _layer)
        }
        
        player.play()
    }
    
    /// Starts or resumes playback
    func play() {
        DispatchQueue.main.async { [self] in
            if isCompleted {
                _player?.seek(time: .zero)
            } else if isManuallyPaused {
                _player?.rate = baseRate
            } else {
                _player?.play()
            }
            
            onUpdate?()
        }
    }
    
    /// Pauses playback
    func pause() {
        DispatchQueue.main.async { [self] in
            baseRate = rate
            _player?.rate = 0.0
            
            isManuallyPaused = true
            onUpdate?()
        }
    }
    
    /// Seeks to a specific time in the media
    /// - Parameter time: Target time for seeking
    func seek(to time: CMTime) {
        _player?.seek(time: time)
    }
    
    /// Purges player resources
    func purge() {
        _player?.purge()
    }
    
    // MARK: - Private Methods
    
    private func configurePlayerCallbacks(_ player: CustomPlayerBase) {
        player.output = .init { [weak self] error in
            self?._player?.seek(time: self?.currentTime ?? .zero)
        } onDurationUpdate: { [weak self] duration in
            self?.duration = duration.seconds.rounded(.down)
        } onTimeUpdate: { [weak self] playerTime, _ in
            self?.currentTime = playerTime
            self?.onUpdate?()
        } onStatusUpdate: { [weak self] status in
            guard let self else { return }
            
            DispatchQueue.main.async {
                switch status {
                case .finished:
                    self.isCompleted = true
                    self.isBuffering = false
                case .playing:
                    self.isCompleted = false
                    self.isBuffering = false
                case .buffering:
                    self.isCompleted = false
                    self.isBuffering = true
                }
                
                self.onUpdate?()
            }
        }
    }
}
