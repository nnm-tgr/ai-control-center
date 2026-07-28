import Foundation

struct GitStatus: Sendable, Hashable {
    let branch: String
    let isDetachedHEAD: Bool
    let aheadCount: Int
    let behindCount: Int
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let hasConflicts: Bool
    let lastFetchedAt: Date?
    let stashCount: Int

    enum SyncStatus: Sendable {
        case upToDate
        case ahead(Int)
        case behind(Int)
        case diverged(ahead: Int, behind: Int)
    }

    var isClean: Bool {
        stagedCount == 0 && unstagedCount == 0 && untrackedCount == 0
    }

    var totalChanges: Int {
        stagedCount + unstagedCount + untrackedCount
    }

    var syncStatus: SyncStatus {
        switch (aheadCount, behindCount) {
        case (0, 0): .upToDate
        case (let a, 0) where a > 0: .ahead(a)
        case (0, let b) where b > 0: .behind(b)
        default: .diverged(ahead: aheadCount, behind: behindCount)
        }
    }
}
