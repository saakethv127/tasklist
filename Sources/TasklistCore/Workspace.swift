import Foundation

public struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isComplete: Bool
    public var parentID: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, notes: String = "", isComplete: Bool = false, parentID: UUID? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isComplete = isComplete
        self.parentID = parentID
        self.createdAt = Date()
    }
}

public struct TaskTab: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var tasks: [TaskItem]
    // Optional so task files created before tab customization still decode.
    public var colorHex: String?
    public var iconID: String?

    public init(id: UUID = UUID(), name: String, tasks: [TaskItem] = [], colorHex: String? = nil, iconID: String? = nil) {
        self.id = id
        self.name = name
        self.tasks = tasks
        self.colorHex = colorHex
        self.iconID = iconID
    }

    public func children(of id: UUID?) -> [TaskItem] { tasks.filter { $0.parentID == id } }

    public func descendants(of id: UUID) -> Set<UUID> {
        var found: Set<UUID> = [id]
        var pending = [id]
        while let next = pending.popLast() {
            for child in children(of: next) where !found.contains(child.id) {
                found.insert(child.id)
                pending.append(child.id)
            }
        }
        found.remove(id)
        return found
    }

    public func breadcrumb(for task: TaskItem) -> String {
        var names = [name]
        var parents: [String] = []
        var current = task.parentID
        var visited: Set<UUID> = [task.id]
        while let id = current, !visited.contains(id), let parent = tasks.first(where: { $0.id == id }) {
            visited.insert(id)
            parents.insert(parent.title, at: 0)
            current = parent.parentID
        }
        names += parents
        return names.joined(separator: " › ")
    }
}

public struct SearchResult: Identifiable, Equatable, Sendable {
    public var tabID: UUID
    public var taskID: UUID?
    public var title: String
    public var context: String
    public var isComplete: Bool
    public var id: UUID { taskID ?? tabID }
}

public struct Workspace: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var tabs: [TaskTab]
    public var selectedTabID: UUID

    public init(tabs: [TaskTab] = [TaskTab(name: "Inbox")], selectedTabID: UUID? = nil) {
        let nonempty = tabs.isEmpty ? [TaskTab(name: "Inbox")] : tabs
        self.tabs = nonempty
        self.selectedTabID = selectedTabID.flatMap { id in nonempty.contains(where: { $0.id == id }) ? id : nil } ?? nonempty[0].id
    }

    public var selectedTab: TaskTab { tabs.first(where: { $0.id == selectedTabID }) ?? tabs[0] }

    @discardableResult public mutating func addTab(name: String) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let tab = TaskTab(name: clean)
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.id
    }

    public mutating func deleteTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty { tabs = [TaskTab(name: "Inbox")] }
        if selectedTabID == id { selectedTabID = tabs[min(index, tabs.count - 1)].id }
    }

    @discardableResult public mutating func addTask(title: String, tabID: UUID, parentID: UUID? = nil) -> UUID? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        if let parentID, !tabs[index].tasks.contains(where: { $0.id == parentID }) { return nil }
        let task = TaskItem(title: clean, parentID: parentID)
        tabs[index].tasks.append(task)
        return task.id
    }

    public mutating func updateTask(id: UUID, tabID: UUID, _ update: (inout TaskItem) -> Void) {
        guard let ti = tabs.firstIndex(where: { $0.id == tabID }), let i = tabs[ti].tasks.firstIndex(where: { $0.id == id }) else { return }
        update(&tabs[ti].tasks[i])
    }

    public mutating func deleteTask(id: UUID, tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let ids = tabs[index].descendants(of: id).union([id])
        tabs[index].tasks.removeAll { ids.contains($0.id) }
    }

    public func search(_ query: String) -> [SearchResult] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        func matches(_ text: String) -> Bool { words.allSatisfy { text.localizedStandardContains($0) } }
        return tabs.flatMap { tab in
            var results: [SearchResult] = []
            if matches(tab.name) {
                results.append(SearchResult(tabID: tab.id, title: tab.name, context: "Tab · \(tab.tasks.count) items", isComplete: false))
            }
            results += tab.tasks.filter { matches("\($0.title) \($0.notes) \(tab.breadcrumb(for: $0))") }.map {
                SearchResult(tabID: tab.id, taskID: $0.id, title: $0.title, context: tab.breadcrumb(for: $0), isComplete: $0.isComplete)
            }
            return results
        }
    }

    public func validate() throws {
        guard version == 1 else { throw StorageError.unsupportedVersion(version) }
        guard !tabs.isEmpty, Set(tabs.map(\.id)).count == tabs.count, tabs.contains(where: { $0.id == selectedTabID }) else { throw StorageError.invalidData }
        var allIDs = Set<UUID>()
        for tab in tabs {
            guard !tab.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StorageError.invalidData }
            for task in tab.tasks {
                guard allIDs.insert(task.id).inserted else { throw StorageError.invalidData }
                var seen: Set<UUID> = [task.id]
                var parent = task.parentID
                while let id = parent {
                    guard seen.insert(id).inserted, let item = tab.tasks.first(where: { $0.id == id }) else { throw StorageError.invalidData }
                    parent = item.parentID
                }
            }
        }
    }
}

public enum StorageError: LocalizedError {
    case invalidData
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidData: return "The saved task file is invalid. Your original file has been left untouched."
        case .unsupportedVersion(let version): return "This task file uses a newer format (\(version)). Please update Tasklist."
        }
    }
}

public struct WorkspaceStorage {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Workspace {
        guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
        let data = try Data(contentsOf: url)
        let workspace = try JSONDecoder().decode(Workspace.self, from: data)
        try workspace.validate()
        return workspace
    }
    public func save(_ workspace: Workspace) throws {
        try workspace.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspace)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }
}

// Session-only task navigation; nil represents the task list.
public struct TaskNavigationHistory {
    public private(set) var entries: [UUID?] = [nil]
    public private(set) var index = 0
    public init() {}
    public var current: UUID? { entries[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < entries.count }
    public mutating func reset(to id: UUID? = nil) { entries = id.map { [nil, $0] } ?? [nil]; index = entries.count - 1 }
    public mutating func visit(_ id: UUID?) {
        guard id != current else { return }
        entries = Array(entries.prefix(index + 1))
        entries.append(id)
        index += 1
    }
    public mutating func back() { if canGoBack { index -= 1 } }
    public mutating func forward() { if canGoForward { index += 1 } }
    public mutating func removeMissing(validIDs: Set<UUID>) {
        let old = entries
        let oldIndex = index
        entries = []
        index = 0
        for (i, id) in old.enumerated() where id == nil || validIDs.contains(id!) {
            if entries.last != .some(id) { entries.append(id) }
            if i <= oldIndex { index = max(0, entries.count - 1) }
        }
        if entries.isEmpty { entries = [nil]; index = 0 }
    }
}

// Direction locks after a small dead zone. A gesture commits once at full fill;
// reversals below the threshold retract it, and vertical scrolling is untouched.
public struct TaskSwipeGesture {
    public private(set) var direction = 0 // +1 back, -1 forward
    public private(set) var progress = 0.0
    public private(set) var committed = false
    private var x = 0.0
    private var y = 0.0
    private var rejected = false
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func update(dx: Double, dy: Double, canBack: Bool, canForward: Bool) -> Bool {
        guard !rejected else { return false }
        guard !committed else { return true }
        x += dx; y += dy
        if direction == 0 {
            guard max(abs(x), abs(y)) >= 8 else { return false }
            guard abs(x) > abs(y) * 1.35 else { rejected = true; return false }
            direction = x > 0 ? 1 : -1
            guard direction == 1 ? canBack : canForward else { direction = 0; rejected = true; return false }
        }
        progress = min(1, max(0, x * Double(direction) / 90))
        if progress >= 1 { committed = true }
        return true
    }
}
