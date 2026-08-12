import Foundation

// MARK: - TaskStatus

enum TaskStatus: String, CaseIterable, Sendable {
    case todo
    case inProgress
    case inReview
    case onHold
    case done

    var displayName: String {
        switch self {
        case .todo:       "To Do"
        case .inProgress: "In Progress"
        case .inReview:   "In Review"
        case .onHold:     "On Hold"
        case .done:       "Done"
        }
    }

    var iconName: String {
        switch self {
        case .todo:       "circle"
        case .inProgress: "arrow.clockwise.circle"
        case .inReview:   "eye.circle"
        case .onHold:     "pause.circle"
        case .done:       "checkmark.circle.fill"
        }
    }

    var isDone: Bool { self == .done }
    var isActive: Bool { self == .inProgress || self == .inReview }
}

extension TaskStatus: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Unknown values (e.g. "cancelled" from older builds) fall back to .todo
        self = TaskStatus(rawValue: raw) ?? .todo
    }
}

// MARK: - TaskNote

struct TaskNote: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), content: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - TaskPriority

enum TaskPriority: String, Codable, CaseIterable, Comparable, Sendable {
    case low, medium, high, urgent

    var displayName: String {
        switch self {
        case .low:    "Low"
        case .medium: "Med"
        case .high:   "High"
        case .urgent: "Urgent"
        }
    }

    private var order: Int {
        switch self { case .low: 0; case .medium: 1; case .high: 2; case .urgent: 3 }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

// MARK: - TaskScope

enum TaskScope: Equatable, Hashable, Sendable {
    case project(rootURL: URL)
    case group(groupID: UUID)
    case global
}

extension TaskScope {
    /// Stable string key used to identify a group bucket (for ordering / drag-drop).
    var groupKey: String {
        switch self {
        case .project(let url): return "project:\(url.path)"
        case .group(let id):    return "group:\(id.uuidString)"
        case .global:           return "global"
        }
    }
}

extension TaskScope: Codable {
    private enum CodingKeys: String, CodingKey { case kind, url, groupID }
    private enum Kind: String, Codable { case project, group, global }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .project(let url):
            try c.encode(Kind.project, forKey: .kind)
            try c.encode(url, forKey: .url)
        case .group(let id):
            try c.encode(Kind.group, forKey: .kind)
            try c.encode(id, forKey: .groupID)
        case .global:
            try c.encode(Kind.global, forKey: .kind)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .project: self = .project(rootURL: try c.decode(URL.self, forKey: .url))
        case .group:   self = .group(groupID: try c.decode(UUID.self, forKey: .groupID))
        case .global:  self = .global
        }
    }
}

// MARK: - TaskScopeFilter

enum TaskScopeFilter: Equatable, Sendable {
    case all
    case project(rootURL: URL)
    case group(groupID: UUID)
    case global

    func matches(_ scope: TaskScope) -> Bool {
        switch (self, scope) {
        case (.all, _):                                           true
        case (.project(let a), .project(let b)):                 a == b
        case (.group(let a), .group(let b)):                     a == b
        case (.global, .global):                                 true
        default:                                                  false
        }
    }

    var displayName: String {
        switch self {
        case .all:               "All"
        case .project(let url):  url.lastPathComponent
        case .group:             "Group"
        case .global:            "Global"
        }
    }
}

// MARK: - TaskGroup

struct TaskGroup: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, colorHex: String = "#5B5FC7", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

// MARK: - TaskCategory

struct TaskCategory: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, colorHex: String = "#5B5FC7", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    static let presetColors: [String] = [
        "#5B5FC7", "#4A90D9", "#2ECC7A", "#F5C842",
        "#F5813D", "#E85151", "#9B72CF", "#888888",
    ]
}

// MARK: - TaskItem

struct TaskItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var title: String
    var notes: [TaskNote]
    var status: TaskStatus
    var priority: TaskPriority
    var scope: TaskScope
    var parentID: UUID?
    var categoryID: UUID?
    var progress: Int
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: [TaskNote] = [],
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        scope: TaskScope = .global,
        parentID: UUID? = nil,
        categoryID: UUID? = nil,
        progress: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.scope = scope
        self.parentID = parentID
        self.categoryID = categoryID
        self.progress = min(max(progress, 0), 100)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
    }

    var isSubtask: Bool { parentID != nil }
    var isDone: Bool { status.isDone }

    // Handles three cases for the `notes` key:
    //   [TaskNote] array — current format
    //   String          — legacy format; converted to a single note entry
    //   absent          — newly created task; defaults to []
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try  c.decode(UUID.self,         forKey: .id)
        title      = try  c.decode(String.self,       forKey: .title)
        status     = try (c.decodeIfPresent(TaskStatus.self,   forKey: .status)   ?? .todo)
        priority   = try (c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium)
        scope      = try  c.decode(TaskScope.self,    forKey: .scope)
        parentID   = try  c.decodeIfPresent(UUID.self,         forKey: .parentID)
        categoryID = try  c.decodeIfPresent(UUID.self,         forKey: .categoryID)
        let raw    = try  c.decodeIfPresent(Int.self,          forKey: .progress)  ?? 0
        progress   = min(max(raw, 0), 100)
        createdAt  = try  c.decode(Date.self,         forKey: .createdAt)
        updatedAt  = try (c.decodeIfPresent(Date.self,         forKey: .updatedAt) ?? .now)
        dueDate    = try  c.decodeIfPresent(Date.self,         forKey: .dueDate)

        if let array = try? c.decode([TaskNote].self, forKey: .notes) {
            notes = array
        } else if let legacy = try? c.decode(String.self, forKey: .notes),
                  !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = [TaskNote(content: legacy)]
        } else {
            notes = []
        }
    }
}
