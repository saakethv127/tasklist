import Foundation
import Testing
@testable import TasklistCore

@Test func nestedTasksRemainIsolatedAndDeleteWithTheirParent() throws {
    var data = Workspace()
    let inbox = data.selectedTabID
    let root = try unwrap(data.addTask(title: "Plan release", tabID: inbox))
    let child = try unwrap(data.addTask(title: "Review", tabID: inbox, parentID: root))
    let grandchild = try unwrap(data.addTask(title: "Check links", tabID: inbox, parentID: child))
    let unrelated = try unwrap(data.addTask(title: "Keep this", tabID: inbox))
    let other = try unwrap(data.addTab(name: "Personal"))
    let otherTask = try unwrap(data.addTask(title: "Read", tabID: other))
    let invalid = data.addTask(title: "Invalid parent", tabID: other, parentID: root)
    #expect(invalid == nil)
    #expect(data.tabs[0].descendants(of: root) == [child, grandchild])
    data.deleteTask(id: root, tabID: inbox)
    #expect(data.tabs[0].tasks.map(\.id) == [unrelated])
    #expect(data.tabs[1].tasks.map(\.id) == [otherTask])
    try data.validate()
}

@Test func deleteTabsMaintainsValidSelectionAndLastTab() throws {
    var data = Workspace()
    let inbox = data.selectedTabID
    let work = try unwrap(data.addTab(name: "Work"))
    data.deleteTab(id: inbox)
    #expect(data.selectedTabID == work)
    data.deleteTab(id: work)
    #expect(data.tabs.count == 1)
    #expect(data.selectedTab.name == "Inbox")
    let blank = data.addTab(name: "  \n ")
    #expect(blank == nil)
    try data.validate()
}

@Test func searchIncludesTabsNestedTasksNotesAndCompletedItems() throws {
    var data = Workspace()
    let tab = try unwrap(data.addTab(name: "Engineering"))
    let root = try unwrap(data.addTask(title: "Launch", tabID: tab))
    let child = try unwrap(data.addTask(title: "Documentation", tabID: tab, parentID: root))
    data.updateTask(id: child, tabID: tab) { $0.notes = "Read [Swift](https://swift.org)"; $0.isComplete = true }
    #expect(data.search("swift").map(\.taskID) == [child])
    #expect(data.search("engineering").contains { $0.taskID == nil && $0.tabID == tab })
    #expect(data.search("launch documentation").map(\.taskID) == [child])
    #expect(data.search("SWIFT").first?.isComplete == true)
    #expect(data.search("unfindable").isEmpty)
}

@Test func atomicPersistenceRoundTripsUnicodeNotesAndSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = WorkspaceStorage(url: directory.appendingPathComponent("tasks.json"))
    var data = try storage.load()
    let tab = try unwrap(data.addTab(name: "旅行 ✨"))
    let task = try unwrap(data.addTask(title: "Book café", tabID: tab))
    data.updateTask(id: task, tabID: tab) { $0.notes = "## Plan\n- **Coffee**\n[Map](https://example.com)" }
    try storage.save(data)
    #expect(try storage.load() == data)
    data.updateTask(id: task, tabID: tab) { $0.isComplete = true }
    try storage.save(data)
    #expect(try storage.load() == data)
}

@Test func corruptAndFutureDataAreRejectedWithoutModification() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("tasks.json")
    let storage = WorkspaceStorage(url: url)
    let corrupt = Data("not json".utf8)
    try corrupt.write(to: url)
    #expect(throws: (any Error).self) { try storage.load() }
    #expect(try Data(contentsOf: url) == corrupt)
    var future = Workspace()
    future.version = 99
    let encoded = try JSONEncoder().encode(future)
    try encoded.write(to: url)
    #expect(throws: (any Error).self) { try storage.load() }
    #expect(try Data(contentsOf: url) == encoded)
}

@Test func rejectsCyclesOrOrphans() throws {
    var data = Workspace()
    let tab = data.selectedTabID
    let task = try unwrap(data.addTask(title: "Task", tabID: tab))
    data.updateTask(id: task, tabID: tab) { $0.parentID = task }
    #expect(throws: (any Error).self) { try data.validate() }
    data.updateTask(id: task, tabID: tab) { $0.parentID = UUID() }
    #expect(throws: (any Error).self) { try data.validate() }
}

@Test func searchLatencyForLargePersonalWorkspace() throws {
    let tabs = (0..<10).map { index in
        TaskTab(name: "Tab \(index)", tasks: (0..<100).map { TaskItem(title: "Task \($0)", notes: "Some useful detail for item \($0)") })
    }
    let data = Workspace(tabs: tabs)
    let start = ContinuousClock.now
    for _ in 0..<10 { #expect(data.search("detail 42").count == 10) }
    let duration = start.duration(to: .now)
    print("Search benchmark: 10 searches across 1,000 tasks: \(duration)")
    #expect(duration < .seconds(2))
}

private func unwrap<T>(_ value: T?) throws -> T { try #require(value) }

@Test func legacyTaskFilesAndIndependentTabAppearanceRoundTrip() throws {
    var original = Workspace()
    _ = original.addTask(title: "Keep my task", tabID: original.selectedTabID)
    _ = original.addTab(name: "Work")
    // The previous app's JSON has no appearance keys at all.
    let legacy = try JSONEncoder().encode(original)
    var data = try JSONDecoder().decode(Workspace.self, from: legacy)
    #expect(data.tabs[0].colorHex == nil)
    #expect(data.tabs[0].iconID == nil)
    data.tabs[1].colorHex = "3478D4"
    data.tabs[1].iconID = "briefcase"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = WorkspaceStorage(url: directory.appendingPathComponent("tasks.json"))
    try storage.save(data)
    let restored = try storage.load()
    #expect(restored == data)
    #expect(restored.tabs[0] == original.tabs[0])
    #expect(restored.tabs[1].colorHex == "3478D4")
    #expect(restored.tabs[1].iconID == "briefcase")
}

@Test func lucideCatalogSupportsNamesTagsCategoriesAndStableIDs() throws {
    #expect(IconCatalog.all.count == 2019)
    #expect(Set(IconCatalog.all.map(\.id)).count == IconCatalog.all.count)
    #expect(IconCatalog.search("CLOUD-download").first?.id == "cloud-download")
    #expect(IconCatalog.search("airplane").contains { $0.id == "plane" })
    #expect(IconCatalog.search("home").contains { $0.id == "house" })
    #expect(IconCatalog.search("food beverage").contains { $0.id == "coffee" })
    #expect(IconCatalog.search("  \n ").count == 2019)
    #expect(IconCatalog.search("zzzznonexistentzzzz").isEmpty)
    #expect(IconCatalog.icon(for: "lucide:coffee")?.name == "Coffee")
    #expect(IconCatalog.icon(for: "lucide:unknown") == nil)
    #expect(IconCatalog.icon(for: "coffee") == nil) // Legacy SVG ID stays separate.
    var workspace = Workspace()
    workspace.tabs[0].iconID = "lucide:plane"
    let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    #expect(IconCatalog.icon(for: decoded.tabs[0].iconID)?.id == "plane")
}

@Test func iconSearchRemainsFastAcrossTheFullCollection() {
    _ = IconCatalog.search("warm up")
    let start = ContinuousClock.now
    for _ in 0..<100 { #expect(!IconCatalog.search("cloud").isEmpty) }
    let elapsed = start.duration(to: .now)
    print("Icon search benchmark: 100 searches across \(IconCatalog.all.count) icons: \(elapsed)")
    #expect(elapsed < .seconds(2))
}
