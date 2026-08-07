import Foundation

struct BatchItemFailure: Sendable, Equatable, Identifiable {
    let assetID: UUID
    let message: String

    var id: UUID { assetID }
}

struct BatchEditReport: Sendable, Equatable {
    let attempted: Int
    let succeeded: Int
    let failures: [BatchItemFailure]

    var failed: Int { failures.count }
}
