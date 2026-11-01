import Foundation

/// Minimal timer-driven reader, replacing Stats' Reader + Repeater + DB stack.
/// `read()` runs on a private serial queue; callers hop to main for UI work.
class Reader<T> {
    private(set) var interval: TimeInterval
    private let queue: DispatchQueue
    private let handler: (T) -> Void
    private var timer: DispatchSourceTimer?

    init(label: String, interval: TimeInterval = 1, handler: @escaping (T) -> Void) {
        self.interval = interval
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.handler = handler
    }

    deinit {
        self.timer?.cancel()
    }

    func start() {
        self.queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.interval, leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in
                self?.read()
            }
            timer.resume()
            self.timer = timer
        }
    }

    /// Also used for sleep: cancelling drops the baseline, so wake-up jumps are ignored.
    func stop() {
        self.queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.reset()
        }
    }

    func read() {}

    /// Subclasses drop any stored baseline here.
    func reset() {}

    func emit(_ value: T) {
        self.handler(value)
    }

    func setInterval(_ value: TimeInterval) {
        self.onQueue { [weak self] in
            guard let self else { return }
            self.interval = value
            self.timer?.schedule(deadline: .now() + value, repeating: value, leeway: .milliseconds(50))
        }
    }

    /// Runs the block on the reader's serial queue (state is queue-confined).
    func onQueue(_ block: @escaping () -> Void) {
        self.queue.async(execute: block)
    }
}
