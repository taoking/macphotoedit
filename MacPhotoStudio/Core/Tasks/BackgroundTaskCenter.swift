import Foundation

enum BackgroundTaskKind: String, Sendable, CaseIterable {
    case scan
    case metadataExtraction
    case thumbnailGeneration
    case previewGeneration
    case duplicateHashing
    case photoBatchEdit
    case photoExport
    case videoExport
    case videoProxyGeneration
}

enum BackgroundTaskState: String, Sendable, Equatable {
    case queued
    case running
    case paused
    case cancelled
    case failed
    case completed

    var isTerminal: Bool {
        switch self {
        case .cancelled, .failed, .completed:
            return true
        case .queued, .running, .paused:
            return false
        }
    }
}

struct StudioBackgroundTask: Identifiable, Sendable, Equatable {
    let id: UUID
    let kind: BackgroundTaskKind
    let title: String
    fileprivate(set) var state: BackgroundTaskState
    fileprivate(set) var progress: Double
    let createdAt: Date
    fileprivate(set) var updatedAt: Date
}

actor BackgroundTaskCenter {
    private var tasks: [UUID: StudioBackgroundTask] = [:]

    func enqueue(kind: BackgroundTaskKind, title: String, id: UUID = UUID(), now: Date = .now) -> StudioBackgroundTask {
        let task = StudioBackgroundTask(
            id: id,
            kind: kind,
            title: title,
            state: .queued,
            progress: 0,
            createdAt: now,
            updatedAt: now
        )
        tasks[id] = task
        return task
    }

    func start(_ id: UUID, now: Date = .now) throws {
        try transition(id, from: [.queued, .paused], to: .running, now: now)
    }

    func pause(_ id: UUID, now: Date = .now) throws {
        try transition(id, from: [.running], to: .paused, now: now)
    }

    func cancel(_ id: UUID, now: Date = .now) throws {
        try transition(id, from: [.queued, .running, .paused], to: .cancelled, now: now)
    }

    func complete(_ id: UUID, now: Date = .now) throws {
        try transition(id, from: [.running], to: .completed, now: now)
    }

    func fail(_ id: UUID, now: Date = .now) throws {
        try transition(id, from: [.running], to: .failed, now: now)
    }

    func updateProgress(_ progress: Double, for id: UUID, now: Date = .now) throws {
        guard var task = tasks[id], task.state == .running else {
            throw StudioError.invalidTaskTransition
        }
        task.progress = min(max(progress, 0), 1)
        task.updatedAt = now
        tasks[id] = task
    }

    func task(for id: UUID) -> StudioBackgroundTask? {
        tasks[id]
    }

    func allTasks() -> [StudioBackgroundTask] {
        tasks.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func transition(
        _ id: UUID,
        from allowedStates: Set<BackgroundTaskState>,
        to newState: BackgroundTaskState,
        now: Date
    ) throws {
        guard var task = tasks[id], allowedStates.contains(task.state), !task.state.isTerminal else {
            throw StudioError.invalidTaskTransition
        }
        task.state = newState
        if newState == .completed {
            task.progress = 1
        }
        task.updatedAt = now
        tasks[id] = task
    }
}
