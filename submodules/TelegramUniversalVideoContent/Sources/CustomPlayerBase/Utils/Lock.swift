import Darwin

/// A low-level lock implementation using os_unfair_lock
/// This lock is faster than a standard mutex for uncontended cases
/// but should be used carefully to avoid priority inversion
final class UnfairLock: @unchecked Sendable {
    // MARK: - Private Properties
    
    /// The underlying unfair lock pointer
    private let mutex: UnsafeMutablePointer<os_unfair_lock_s> = .allocate(capacity: 1)
    
    // MARK: - Lifecycle
    
    /// Initializes a new unfair lock
    init() {
        mutex.initialize(to: os_unfair_lock_s())
    }
    
    /// Cleans up the allocated memory for the lock
    deinit {
        mutex.deinitialize(count: 1)
        mutex.deallocate()
    }
    
    // MARK: - Public Methods
    
    /// Acquires the lock
    /// - Note: Blocks the current thread until the lock can be acquired
    func lock() {
        os_unfair_lock_lock(mutex)
    }
    
    /// Releases the lock
    /// - Warning: Must be called from the same thread that acquired the lock
    func unlock() {
        os_unfair_lock_unlock(mutex)
    }
    
    /// Executes a closure while holding the lock
    /// - Parameter body: The closure to execute
    /// - Returns: The value returned by the closure
    /// - Throws: Rethrows any error thrown by the closure
    @inlinable
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer {
            unlock()
        }
        return try body()
    }
}

/// A property wrapper that provides thread-safe access to a value
/// Usage:
/// ```
/// @ThreadSafe var counter: Int = 0
/// ```
@propertyWrapper
final class ThreadSafe<Value> {
    // MARK: - Private Properties
    
    /// The wrapped value that needs thread-safe access
    private var _wrappedValue: Value
    
    /// Lock used to ensure thread-safe access
    private let lock = UnfairLock()
    
    // MARK: - Initialization
    
    /// Creates a new thread-safe wrapper with an initial value
    /// - Parameter wrappedValue: The initial value to wrap
    init(wrappedValue: Value) {
        _wrappedValue = wrappedValue
    }
    
    /// Alternative initializer with more explicit parameter name
    /// - Parameter initialValue: The initial value to wrap
    init(initialValue: Value) {
        _wrappedValue = initialValue
    }
    
    // MARK: - Property Wrapper
    
    /// The thread-safe accessor for the wrapped value
    var wrappedValue: Value {
        get {
            lock.withLock { _wrappedValue }
        }
        set {
            lock.withLock { _wrappedValue = newValue }
        }
        _modify {
            lock.lock()
            defer { lock.unlock() }
            
            yield &_wrappedValue
        }
    }
}
