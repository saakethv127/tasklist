import Foundation
import Testing
@testable import TasklistCore

@Test func rowDeletionRequiresThresholdAtRelease() {
    var gesture = TaskRowDragGesture()
    let result1 = gesture.update(x: 5, y: 1)
    #expect(!result1)
    #expect(gesture.mode == .undecided)
    let result2 = gesture.update(x: 50, y: 2)
    #expect(!result2)
    #expect(gesture.mode == .delete)
    #expect(!gesture.isArmed)
    let result3 = gesture.update(x: 96, y: 3)
    #expect(result3)
    #expect(gesture.isArmed)
    let result4 = gesture.update(x: 130, y: 3)
    #expect(!result4) // no repeated haptics above threshold
    #expect(gesture.offset > 96 && gesture.offset < 130)
    let result5 = gesture.finish(x: 60, y: 3)
    #expect(!result5) // final release position cancels
    #expect(gesture.mode == .undecided)
    #expect(gesture.offset == 0)
    let result6 = gesture.finish(x: 100, y: 2)
    #expect(result6)
    let result7 = gesture.finish(x: 0, y: 0)
    #expect(!result7) // no stale armed state
}

@Test func rowDragLocksDirectionAndCanDisarm() {
    var gesture = TaskRowDragGesture()
    gesture.update(x: 2, y: 12)
    #expect(gesture.mode == .reorder)
    let result8 = gesture.finish(x: 150, y: 30)
    #expect(!result8) // vertical reorder cannot turn into delete
    gesture.update(x: -12, y: 2)
    #expect(gesture.mode == .ignored)
    let result9 = gesture.finish(x: 150, y: 2)
    #expect(!result9)
    gesture.update(x: 10, y: 10)
    #expect(gesture.mode == .undecided) // wait for an intentional direction
    let result10 = gesture.update(x: 100, y: 10)
    #expect(result10)
    let result11 = gesture.update(x: -5, y: 100)
    #expect(!result11)
    #expect(gesture.mode == .delete)
    #expect(gesture.offset == 0)
    #expect(!gesture.isArmed)
    let result12 = gesture.update(x: 100, y: 100)
    #expect(result12) // rearming gives another tick
    let result13 = gesture.finish(x: 96, y: 100)
    #expect(result13)
}

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

@Test func taskHistorySupportsRoundTripsAndBranches() {
    let task = UUID(), child = UUID(), sibling = UUID()
    var history = TaskNavigationHistory()
    history.visit(task); history.visit(child)
    history.back(); #expect(history.current == task)
    history.forward(); #expect(history.current == child)
    history.back(); history.back(); #expect(history.current == nil)
    #expect(!history.canGoBack)
    history.forward(); #expect(history.current == task)
    history.visit(sibling); #expect(!history.canGoForward)
    history.visit(sibling); #expect(history.entries.count == 3)
    history.removeMissing(validIDs: [task]); #expect(history.current == task)
    history.back(); #expect(history.current == nil)
    history.reset(); #expect(!history.canGoBack && !history.canGoForward)
}

@Test func swipeLocksDirectionCancelsAndCommitsOnlyOnce() {
    var swipe = TaskSwipeGesture()
    let consumed1 = swipe.update(dx: 2, dy: 0, canBack: true, canForward: true)
    #expect(!consumed1)
    let consumed2 = swipe.update(dx: 30, dy: 1, canBack: true, canForward: true)
    #expect(consumed2)
    #expect(swipe.direction == 1 && swipe.progress > 0 && !swipe.committed)
    _ = swipe.update(dx: -32, dy: 0, canBack: true, canForward: true)
    #expect(swipe.progress == 0 && !swipe.committed)
    swipe.reset()
    let consumed3 = swipe.update(dx: 3, dy: 20, canBack: true, canForward: true)
    #expect(!consumed3)
    let consumed4 = swipe.update(dx: 120, dy: 0, canBack: true, canForward: true)
    #expect(!consumed4)
    swipe.reset()
    let consumed5 = swipe.update(dx: 100, dy: 0, canBack: false, canForward: true)
    #expect(!consumed5)
    swipe.reset()
    let consumed6 = swipe.update(dx: -90, dy: 2, canBack: false, canForward: true)
    #expect(consumed6)
    #expect(swipe.direction == -1 && swipe.progress == 1 && swipe.committed)
    _ = swipe.update(dx: 300, dy: 0, canBack: true, canForward: true)
    #expect(swipe.direction == -1 && swipe.progress == 1 && swipe.committed)
}

@Test func siblingReorderingPreservesHierarchyAndRoundTrips() throws {
    var data = Workspace()
    let tab = data.selectedTabID
    let a = try unwrap(data.addTask(title: "A", tabID: tab))
    let b = try unwrap(data.addTask(title: "B", tabID: tab))
    let c = try unwrap(data.addTask(title: "C", tabID: tab, parentID: a))
    let d = try unwrap(data.addTask(title: "D", tabID: tab, parentID: a))
    let e = try unwrap(data.addTask(title: "E", tabID: tab, parentID: c))
    data.reorderTask(id: a, relativeTo: b, tabID: tab)
    #expect(data.selectedTab.children(of: nil).map(\.id) == [b, a])
    data.reorderTask(id: c, relativeTo: d, tabID: tab)
    #expect(data.selectedTab.children(of: a).map(\.id) == [d, c])
    #expect(data.selectedTab.descendants(of: a) == [c, d, e])
    let unchanged = data
    data.reorderTask(id: e, relativeTo: b, tabID: tab)
    #expect(data == unchanged)
    data.reorderTask(id: a, relativeTo: b, tabID: tab)
    #expect(data.selectedTab.children(of: nil).map(\.id) == [a, b])
    try data.validate()
    #expect(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(data)) == data)
}

@Test func onlyTopLevelTasksCanMoveWithTheirEntireTree() throws {
    var data = Workspace()
    let source = data.selectedTabID
    let parent = try unwrap(data.addTask(title: "Parent", tabID: source))
    let child = try unwrap(data.addTask(title: "Child", tabID: source, parentID: parent))
    let grandchild = try unwrap(data.addTask(title: "Grandchild", tabID: source, parentID: child))
    data.updateTask(id: child, tabID: source) { $0.notes = "Keep notes"; $0.isComplete = true }
    let originalChild = try unwrap(data.tabs[0].tasks.first { $0.id == child })
    let destination = try unwrap(data.addTab(name: "Destination"))
    let existing = try unwrap(data.addTask(title: "Existing", tabID: destination))
    let beforeRejectedMove = data
    let rejected = data.moveTask(id: child, from: source, to: destination)
    #expect(!rejected && data == beforeRejectedMove)
    let moved = data.moveTask(id: parent, from: source, to: destination)
    #expect(moved)
    #expect(data.tabs[0].tasks.isEmpty)
    #expect(data.tabs[1].children(of: nil).map(\.id) == [existing, parent])
    #expect(data.tabs[1].descendants(of: child) == [grandchild])
    #expect(data.tabs[1].tasks.first { $0.id == child } == originalChild)
    #expect(data.tabs[1].descendants(of: parent) == [child, grandchild])
    let unchanged = data
    let invalidMove = data.moveTask(id: parent, from: source, to: UUID())
    #expect(!invalidMove && data == unchanged)
    let movedBack = data.moveTask(id: parent, from: destination, to: source)
    #expect(movedBack && data.tabs[0].descendants(of: child) == [grandchild])
    try data.validate()
    #expect(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(data)) == data)
}

@Test func tabReorderingPreservesSelectionAndContents() throws {
    var data = Workspace()
    let first = data.selectedTabID
    _ = data.addTask(title: "Keep task", tabID: first)
    let second = try unwrap(data.addTab(name: "Second"))
    let third = try unwrap(data.addTab(name: "Third"))
    let contents = Dictionary(uniqueKeysWithValues: data.tabs.map { ($0.id, $0) })
    data.reorderTab(id: third, relativeTo: first)
    #expect(data.tabs.map(\.id) == [third, first, second])
    #expect(data.selectedTabID == third)
    data.reorderTab(id: third, relativeTo: second)
    #expect(data.tabs.map(\.id) == [first, second, third])
    #expect(Dictionary(uniqueKeysWithValues: data.tabs.map { ($0.id, $0) }) == contents)
    let unchanged = data
    data.reorderTab(id: UUID(), relativeTo: first)
    #expect(data == unchanged)
    try data.validate()
    #expect(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(data)) == data)
}
