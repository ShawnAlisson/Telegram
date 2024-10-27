import Foundation
import AVFoundation

/// Type aliases for commonly used types
typealias Resolution = M3U8.MasterPlaylist.Stream.Resolution
typealias Stream = M3U8.MasterPlaylist.Stream
typealias MediaTag = M3U8.MasterPlaylist.MediaTag

/// A base class for handling HLS video playback with resolution switching capabilities
class CustomPlayerBase {
    // MARK: - Types
    
    /// Struct containing callback closures for player events
    struct Output {
        var onError: (any Error) -> Void
        var onDurationUpdate: (CMTime) -> Void
        var onTimeUpdate: (CMTime, Double) -> Void
        var onStatusUpdate: (PlaybackStatus) -> Void
        
        /// Empty output with no-op callbacks
        static var empty: Output {
            .init(
                onError: { _ in },
                onDurationUpdate: { _ in },
                onTimeUpdate: { _, _ in },
                onStatusUpdate: { _ in }
            )
        }
    }
    
    /// Internal state management for the player
    private struct PlayerState {
        var master: M3U8.MasterPlaylist?
        var streams: [Resolution: [Stream]] = [:]
        var selectedStream: Stream?
        var activeVideoSession: DownloadSession?
        var activeAudioSession: DownloadSession?
        var useAutomaticResolution = true
    }
    
    // MARK: - Properties
    
    var loadedProgress: (duration: TimeInterval, offset: TimeInterval)?
    var duration: TimeInterval?
    var output: Output = .empty
    
    var volume: Float {
        get { audioRenderer.volume }
        set { audioRenderer.volume = newValue }
    }
    
    var rate: Float {
        get { synchronizer.rate }
        set { synchronizer.rate = newValue }
    }
    
    var availableResolutions: [Int] {
        state.streams.keys.map { $0.short }
    }
    
    var currentResolution: Int? {
        state.selectedStream?.resolution?.short
    }
    
    // MARK: - Private Properties
    
    private let loader: PlaylistLoader
    private weak var videoLayer: CustomVideoRendering?
    private let audioRenderer: CustomAudioRendering
    private let synchronizer: AVSampleBufferRenderSynchronizer
    private var synchronizerTimeObserver: Any?
    private var state = PlayerState()
    private let updatesQueue = DispatchQueue(label: "TGPlayer.Updates", qos: .userInitiated)
    
    // MARK: - Initialization
    
    /// Initializes a new CustomPlayerBase instance
    /// - Parameters:
    ///   - url: The URL of the HLS stream
    ///   - urlSession: URLSession to use for network requests (defaults to shared session)
    init(url: URL, urlSession: URLSession = .shared) {
        loader = .init(url: url, urlSession: urlSession)
        audioRenderer = CustomAudioRenderer()
        synchronizer = AVSampleBufferRenderSynchronizer()
        setupSynchronizer()
    }
    
    // MARK: - Public Methods
    
    /// Purges all cached content and stops playback
    func purge() {
        stop()
        ContentDataProviderCache.shared.removeAll()
    }
    
    /// Attaches a video layer for rendering
    /// - Parameter layer: The CustomPlayerLayer to attach
    func attach(layer: CustomPlayerLayer) {
        videoLayer = layer
        
        layer.observeStatus { [weak self] status in
            self?.synchronizer.rate = status == .playing ? 1.0 : 0.0
            self?.output.onStatusUpdate(status)
        }
        
        layer.observeQualityDownchangeRequest { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if self?.state.useAutomaticResolution == true {
                    self?.dropResolution()
                }
            }
        }
    }
    
    /// Seeks to a specific time in the media
    /// - Parameter time: The target time to seek to
    func seek(time: CMTime) {
        stop()
        if let stream = state.selectedStream {
            play(from: stream, startTime: time)
        }
    }
    
    /// Sets a specific resolution manually
    /// - Parameter value: The resolution value to set
    func setManualResolution(_ value: Int) {
        state.useAutomaticResolution = false
        set(resolution: value)
    }
    
    /// Enables automatic resolution switching
    func setAutomaticResolution() {
        state.useAutomaticResolution = true
    }
    
    /// Starts playback of the media
    func play() {
        guard videoLayer != nil else { return }
        
        loader.load { [weak self] result in
            guard let self else { return }
            
            switch result {
            case .success(let playlist):
                switch playlist {
                case .media:
                    self.output.onError(CustomPlayerError(message: "Only master-based hls supported"))
                case .master(let master):
                    handleMasterPlaylist(master)
                }
            case .failure(let error):
                self.output.onError(error)
            }
        }
    }
}

// MARK: - Private Extensions

private extension CustomPlayerBase {
    func set(resolution: Int) {
        guard let newSelectedStream = state.streams.first(where: { $0.key.short == resolution })?.value.first else {
            return
        }
        
        state.selectedStream = newSelectedStream
        stop()
        play(from: newSelectedStream, startTime: synchronizer.currentTime())
    }
    
    func dropResolution() {
        let availableResolutions = availableResolutions.sorted(by: >)
        
        guard let current = currentResolution,
              let currentIndex = availableResolutions.firstIndex(where: { $0 == current }) else {
            return
        }
        
        if let nextResolution = currentIndex + 1 < availableResolutions.count ? availableResolutions[currentIndex + 1] : nil {
            print("Drop resolution to \(nextResolution)")
            set(resolution: nextResolution)
        }
    }
    
    func setupSynchronizer() {
        synchronizer.setRate(0.0, time: .zero)
        synchronizerTimeObserver = synchronizer.addPeriodicTimeObserver(
            forInterval: .init(seconds: 1.0),
            queue: updatesQueue
        ) { [weak self] time in
            let progress = if let duration = self?.duration, duration > 0.0 {
                time.seconds / duration
            } else {
                0.0
            }
            
            self?.output.onTimeUpdate(time, progress)
        }
    }
    
    func handleMasterPlaylist(_ playlist: M3U8.MasterPlaylist) {
        let availableStreams = playlist.streams
        var streams: [Resolution: [Stream]] = [:]
        
        for availableStream in availableStreams {
            if let resolution = availableStream.resolution {
                streams[resolution] = (streams[resolution] ?? []) + [availableStream]
            }
        }
        
        let defaultStream = availableStreams.first(where: { $0.resolution?.short == 720 }) ?? availableStreams.first
        
        state.master = playlist
        state.streams = streams
        state.selectedStream = defaultStream
        
        if let defaultStream {
            play(from: defaultStream, startTime: .zero)
        }
    }
    
    func handlePlaylist(
        uri: String,
        startTime: CMTime,
        playlist: M3U8.MediaPlaylist,
        targets: [(any CustomTargetRendering)]
    ) -> DownloadSession {
        targets.forEach {
            $0.prepare(startTimeOffset: playlist.getSegmentOffset(containing: startTime))
        }
        
        let playlistResultQueue = DispatchQueue(label: "TGPlayer.PlaylistResultQueue", qos: .userInitiated)
        
        let downloadSession = loader.loadSegments(
            sessionID: uri.hashValue.description,
            streamURI: uri,
            playlist: playlist,
            startTime: startTime,
            resultQueue: playlistResultQueue
        ) { [weak self] idx, url, segmentTimeOffset, duration in
            guard let self else { return }
            
            let offsetInSegment = startTime.seconds - segmentTimeOffset.seconds
            
            self.updatesQueue.async {
                if let progress = self.loadedProgress {
                    self.loadedProgress = (progress.duration + duration.seconds, progress.offset)
                } else {
                    self.loadedProgress = (duration.seconds, startTime.seconds)
                }
            }
            
            targets.forEach {
                $0.enqueueFile(
                    withURL: url,
                    timeOffset: offsetInSegment > 0 ? .init(seconds: offsetInSegment) : .zero
                )
            }
            
            if idx == playlist.segments.count - 1 {
                targets.forEach { $0.complete() }
            }
        }
        
        downloadSession.start()
        return downloadSession
    }
    
    func handleAudioMediaPlaylist(audioURI: String, startTime: CMTime, playlist: M3U8.MediaPlaylist) {
        state.activeAudioSession = handlePlaylist(
            uri: audioURI,
            startTime: startTime,
            playlist: playlist,
            targets: [audioRenderer]
        )
    }
    
    func handleVideoMediaPlaylist(
        stream: Stream,
        startTime: CMTime,
        playlist: M3U8.MediaPlaylist,
        videoIncludesAudio: Bool = false
    ) {
        let totalDuration = playlist.segments.reduce(into: 0) { partialResult, segment in
            partialResult += Double(segment.duration ?? 0)
        }
        self.duration = totalDuration
        updatesQueue.async { [output] in
            output.onDurationUpdate(.init(seconds: totalDuration))
        }
        
        var targets: [CustomTargetRendering] = []
        
        if let videoLayer {
            targets.append(videoLayer)
        }
        
        if videoIncludesAudio {
            targets.append(audioRenderer)
        }
        
        state.activeVideoSession = handlePlaylist(
            uri: stream.uri,
            startTime: startTime,
            playlist: playlist,
            targets: targets
        )
    }
    
    func stop() {
        synchronizer.rate = 0.0
        loadedProgress = nil
        
        state.activeAudioSession?.stop()
        state.activeVideoSession?.stop()
        
        state.activeAudioSession = nil
        state.activeVideoSession = nil
        
        videoLayer?.cancel()
        audioRenderer.cancel()
    }
    
    func play(from stream: Stream, startTime: CMTime) {
        let group = DispatchGroup()
        var hasSeparateAudioStream = false
        
        if let audioStream = state.master?.mediaTags.first(where: { $0.groupID == stream.audio }),
           let audioURI = audioStream.uri {
            hasSeparateAudioStream = true
            
            group.enter()
            loader.loadMedia(uri: audioURI) { [weak self] playlist in
                guard let self else { return }
                
                switch playlist {
                case .success(let playlist):
                    self.handleAudioMediaPlaylist(audioURI: audioURI, startTime: startTime, playlist: playlist)
                    group.leave()
                case .failure(let error):
                    group.leave()
                    self.output.onError(CustomPlayerError(message: "Unable to load media playlist: \(error)"))
                }
            }
        }
        
        group.enter()
        loader.loadMedia(uri: stream.uri) { [weak self] playlist in
            guard let self else { return }
            
            switch playlist {
            case .success(let playlist):
                self.handleVideoMediaPlaylist(
                    stream: stream,
                    startTime: startTime,
                    playlist: playlist,
                    videoIncludesAudio: !hasSeparateAudioStream
                )
                group.leave()
            case .failure(let error):
                group.leave()
                self.output.onError(CustomPlayerError(message: "Unable to load media playlist: \(error)"))
            }
        }
        
        group.notify(queue: .main) { [self] in
            synchronizer.setRate(synchronizer.rate, time: startTime)
            
            if !synchronizer.renderers.contains(where: { $0 === videoLayer }), let videoLayer {
                synchronizer.addRenderer(videoLayer)
            }
            
            if !synchronizer.renderers.contains(where: { $0 === audioRenderer }) {
                synchronizer.addRenderer(audioRenderer)
            }
        }
    }
}

// MARK: - Supporting Types

/// Custom error type for player-related errors
struct CustomPlayerError: Error {
    let message: String
}

// MARK: - CMTime Extension

extension CMTime {
    /// Initializes a CMTime instance from seconds
    /// - Parameter seconds: The duration in seconds
    init(seconds: TimeInterval) {
        self = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    }
}
