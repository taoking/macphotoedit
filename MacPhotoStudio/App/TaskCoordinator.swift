import Foundation

/// Owns the lifecycle of background work submitted by the UI layer. It keeps
/// worker cancellation separate from `BackgroundTaskCenter` state transitions,
/// leaving `ApplicationModel` to publish snapshots and coordinate result UI.
@MainActor
final class TaskCoordinator {
    private let taskCenter: BackgroundTaskCenter
    private var workers: [UUID: Task<Void, Never>] = [:]

    init(taskCenter: BackgroundTaskCenter = BackgroundTaskCenter()) {
        self.taskCenter = taskCenter
    }

    func enqueue(kind: BackgroundTaskKind, title: String) async -> StudioBackgroundTask {
        await taskCenter.enqueue(kind: kind, title: title)
    }

    func start(_ taskID: UUID) async throws {
        try await taskCenter.start(taskID)
    }

    func updateProgress(_ progress: Double, for taskID: UUID) async throws {
        try await taskCenter.updateProgress(progress, for: taskID)
    }

    func complete(_ taskID: UUID) async throws {
        try await taskCenter.complete(taskID)
    }

    func fail(_ taskID: UUID) async throws {
        try await taskCenter.fail(taskID)
    }

    func cancel(_ taskID: UUID) async throws {
        try await taskCenter.cancel(taskID)
    }

    func allTasks() async -> [StudioBackgroundTask] {
        await taskCenter.allTasks()
    }

    func register(worker: Task<Void, Never>, for taskID: UUID) {
        workers[taskID] = worker
    }

    func releaseWorker(for taskID: UUID) {
        workers[taskID] = nil
    }

    func cancelWorker(for taskID: UUID) {
        workers[taskID]?.cancel()
    }
}
