import Foundation

actor ScanControl {
    private var isPaused = false
    private var isCancelled = false

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func cancel() {
        isCancelled = true
        isPaused = false
    }

    func checkpoint() async throws {
        while isPaused && !isCancelled {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
        if isCancelled {
            throw CancellationError()
        }
    }
}
