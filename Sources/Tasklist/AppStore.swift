import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import TasklistCore
#endif

enum Prompt {
    case newTab, renameTab(UUID), deleteTab(UUID), deleteTask(UUID)
}

@MainActor final class AppStore: ObservableObject {
    @Published var workspace: Workspace
    @Published var detailID: UUID?
    @Published var selectedTaskID: UUID?
    @Published var isSearching = false
    @Published var query = ""
    @Published var draft = ""
    @Published var subtaskDraft = ""
    @Published var prompt: Prompt?
    @Published var promptText = ""
    @Published var searchIndex = 0
    @Published var showCompleted = true
    @Published var showHelp = false
    @Published var appearanceTabID: UUID?
    @Published var editingNotes = false
    @Published var focusRequest = 0
    @Published var storageError: String?
    @Published var hotkeyError: String?
    @Published var undoWorkspace: Workspace?
    var hidePanel: (() -> Void)?
    private let storage: WorkspaceStorage
    private var canSave = true
    private var isDirty = false
    private var saveWork: DispatchWorkItem?
    private lazy var tabColorPicker = TabColorPicker { [weak self] id, hex in
        self?.setTabAppearance(id, colorHex: hex)
    }

    init(url: URL) {
        storage = WorkspaceStorage(url: url)
        do { workspace = try storage.load() }
        catch {
            workspace = Workspace()
            canSave = false
            storageError = "Couldn’t load tasks: \(error.localizedDescription)"
        }
    }

    var tab: TaskTab { workspace.selectedTab }
    var detail: TaskItem? { tab.tasks.first { $0.id == detailID } }
    var searchResults: [SearchResult] { workspace.search(query) }
    var visibleRows: [(task: TaskItem, depth: Int)] {
        let childrenByParent = Dictionary(grouping: tab.tasks, by: \.parentID)
        func walk(_ parent: UUID?, _ depth: Int) -> [(TaskItem, Int)] {
            (childrenByParent[parent] ?? []).flatMap { task -> [(TaskItem, Int)] in
                let children = walk(task.id, depth + 1)
                // Keep completed parents visible if they contain unfinished children.
                guard showCompleted || !task.isComplete || !children.isEmpty else { return [] }
                return [(task, depth)] + children
            }
        }
        return walk(nil, 0)
    }

    func change(_ update: (inout Workspace) -> Void) {
        update(&workspace)
        scheduleSave()
    }
    func scheduleSave() {
        isDirty = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        guard canSave, isDirty else { return }
        do { try storage.save(workspace); isDirty = false; storageError = nil }
        catch { storageError = "Couldn’t save: \(error.localizedDescription)" }
    }
    func revealData() { NSWorkspace.shared.selectFile(storage.url.path, inFileViewerRootedAtPath: storage.url.deletingLastPathComponent().path) }
    func focusEntry() { focusRequest += 1 }
    func customizeTab(_ id: UUID) {
        showHelp = false
        appearanceTabID = id
    }
    func openCustomTabColor(_ id: UUID) {
        guard let tab = workspace.tabs.first(where: { $0.id == id }) else { return }
        appearanceTabID = nil
        DispatchQueue.main.async { self.tabColorPicker.show(for: tab) }
    }
    func setTabAppearance(_ id: UUID, colorHex: String? = nil, iconID: String? = nil) {
        change { data in
            guard let index = data.tabs.firstIndex(where: { $0.id == id }) else { return }
            if let colorHex { data.tabs[index].colorHex = colorHex }
            if let iconID { data.tabs[index].iconID = iconID }
        }
    }
    func selectTab(_ id: UUID) {
        change { $0.selectedTabID = id }
        isSearching = false
        query = ""
        detailID = nil
        selectedTaskID = nil
        editingNotes = false
        draft = ""
        subtaskDraft = ""
        focusEntry()
    }
    func switchTab(_ delta: Int) {
        let index = workspace.tabs.firstIndex { $0.id == tab.id } ?? 0
        selectTab(workspace.tabs[(index + delta + workspace.tabs.count) % workspace.tabs.count].id)
        isSearching = false
    }
    func addTask() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let tabID = tab.id
        change { selectedTaskID = $0.addTask(title: text, tabID: tabID) }
        draft = ""
    }
    func addSubtask() {
        guard let detailID else { return }
        let text = subtaskDraft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let tabID = tab.id
        change { _ = $0.addTask(title: text, tabID: tabID, parentID: detailID) }
        subtaskDraft = ""
    }
    func toggle(_ task: TaskItem) {
        let tabID = tab.id
        change { $0.updateTask(id: task.id, tabID: tabID) { $0.isComplete.toggle() } }
    }
    func updateTask(_ id: UUID, title: String? = nil, notes: String? = nil) {
        let tabID = tab.id
        change {
            $0.updateTask(id: id, tabID: tabID) {
                if let title { $0.title = title }
                if let notes { $0.notes = notes }
            }
        }
    }
    func openTask(_ id: UUID) {
        selectedTaskID = id
        detailID = id
        subtaskDraft = ""
        editingNotes = false
        isSearching = false
    }
    func back() {
        if isSearching { isSearching = false; query = ""; focusEntry(); return }
        if let parentID = detail?.parentID { openTask(parentID) }
        else { detailID = nil; editingNotes = false; focusEntry() }
    }
    func openSelected() {
        if let id = selectedTaskID ?? visibleRows.first?.task.id { openTask(id) }
    }
    func beginSearch() {
        appearanceTabID = nil
        isSearching = true
        query = ""
        searchIndex = 0
        focusEntry()
    }
    func openSearchResult(_ result: SearchResult) {
        selectTab(result.tabID)
        isSearching = false
        query = ""
        if let id = result.taskID { openTask(id) }
    }
    func beginPrompt(_ value: Prompt) {
        appearanceTabID = nil
        // End any editor before covering it. A modal must never allow typing into
        // the task title/notes behind it during SwiftUI's focus handoff.
        NSApp.keyWindow?.makeFirstResponder(nil)
        showHelp = false
        promptText = ""
        if case .renameTab(let id) = value { promptText = workspace.tabs.first { $0.id == id }?.name ?? "" }
        prompt = value
    }
    var promptTitle: String {
        switch prompt {
        case .newTab: return "New tab"
        case .renameTab: return "Rename tab"
        case .deleteTab: return "Delete this tab?"
        case .deleteTask: return "Delete this task?"
        case nil: return ""
        }
    }
    var isDeletePrompt: Bool {
        switch prompt { case .deleteTask, .deleteTab: return true; default: return false }
    }
    var promptMessage: String {
        switch prompt {
        case .deleteTab(let id):
            guard let target = workspace.tabs.first(where: { $0.id == id }) else { return "" }
            return "“\(target.name)” and its \(target.tasks.count) items will be removed. You can undo this from the menu."
        case .deleteTask(let id):
            guard let task = tab.tasks.first(where: { $0.id == id }) else { return "" }
            let count = tab.descendants(of: id).count
            return "“\(task.title)”\(count > 0 ? " and its \(count) subtasks" : "") will be removed. You can undo this from the menu."
        default: return "Give this list a short, memorable name."
        }
    }
    func confirmPrompt() {
        guard let value = prompt else { return }
        if !isDeletePrompt && promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { NSSound.beep(); return }
        switch value {
        case .newTab:
            change { _ = $0.addTab(name: promptText) }
            selectTab(workspace.selectedTabID)
        case .renameTab(let id):
            change { data in
                if let index = data.tabs.firstIndex(where: { $0.id == id }) { data.tabs[index].name = promptText.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        case .deleteTab(let id):
            undoWorkspace = workspace
            change { $0.deleteTab(id: id) }
            detailID = nil
            selectedTaskID = nil
        case .deleteTask(let id):
            undoWorkspace = workspace
            let parent = tab.tasks.first { $0.id == id }?.parentID
            let deleted = tab.descendants(of: id).union([id])
            let tabID = tab.id
            change { $0.deleteTask(id: id, tabID: tabID) }
            if let detailID, deleted.contains(detailID) { self.detailID = parent }
            if let selectedTaskID, deleted.contains(selectedTaskID) { self.selectedTaskID = nil }
        }
        prompt = nil
        if case .newTab = value {
            customizeTab(workspace.selectedTabID)
        } else {
            focusEntry()
        }
        flush()
    }
    func undoDelete() {
        guard let previous = undoWorkspace else { return }
        // Restore removed objects without rolling back text edits or newly added tasks.
        for (oldIndex, oldTab) in previous.tabs.enumerated() {
            if let index = workspace.tabs.firstIndex(where: { $0.id == oldTab.id }) {
                let existing = Set(workspace.tabs[index].tasks.map(\.id))
                for (taskIndex, task) in oldTab.tasks.enumerated() where !existing.contains(task.id) {
                    workspace.tabs[index].tasks.insert(task, at: min(taskIndex, workspace.tabs[index].tasks.count))
                }
            } else {
                workspace.tabs.insert(oldTab, at: min(oldIndex, workspace.tabs.count))
            }
        }
        workspace.selectedTabID = previous.selectedTabID
        undoWorkspace = nil
        detailID = nil
        selectedTaskID = nil
        scheduleSave()
        flush()
    }

    // A local monitor receives shortcuts even while a text editor is first responder.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if appearanceTabID != nil, event.keyCode == 53 {
            appearanceTabID = nil
            focusEntry()
            return true
        }
        // Let the icon search field handle Return and cursor movement itself.
        if appearanceTabID != nil, !flags.contains(.command) { return false }
        if prompt != nil {
            if event.keyCode == 53 { prompt = nil; focusEntry(); return true }
            if event.keyCode == 36 || event.keyCode == 76 { confirmPrompt(); return true }
            if !isDeletePrompt, !(NSApp.keyWindow?.firstResponder is NSTextView),
               flags.isSubset(of: .shift), let text = event.characters, !text.isEmpty,
               text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                promptText += text
                return true
            }
            // Prevent shortcuts that would change the target underneath the confirmation.
            return flags.contains(.command) && ["k", "t", "w"].contains(key) || [123,124,125,126].contains(event.keyCode) && flags.contains(.command)
        }
        if flags == [.command, .shift], key == "a" {
            if appearanceTabID != nil { appearanceTabID = nil; focusEntry() }
            else { customizeTab(tab.id) }
            return true
        }
        if flags == [.command, .option] {
            if event.keyCode == 123 { back(); return true }
            if event.keyCode == 124 { if detailID == nil { openSelected() }; return true }
        }
        if flags == .command {
            switch key {
            case "k": beginSearch(); return true
            case "t": beginPrompt(.newTab); return true
            case "w": beginPrompt(.deleteTab(tab.id)); return true
            case "f", "n": if isSearching { isSearching = false }; focusEntry(); return true
            default: break
            }
            if event.keyCode == 123 { switchTab(-1); return true }
            if event.keyCode == 124 { switchTab(1); return true }
            if event.keyCode == 51, let id = detailID ?? selectedTaskID { beginPrompt(.deleteTask(id)); return true }
        }
        if event.keyCode == 53 {
            if showHelp { showHelp = false }
            else if isSearching { back() }
            else if detailID != nil { back() }
            else { hidePanel?() }
            return true
        }
        if isSearching && flags.isEmpty {
            if event.keyCode == 125 || event.keyCode == 126 {
                searchIndex = max(0, min(searchResults.count - 1, searchIndex + (event.keyCode == 125 ? 1 : -1)))
                return true
            }
            if event.keyCode == 36, searchResults.indices.contains(searchIndex) { openSearchResult(searchResults[searchIndex]); return true }
        }
        if !isSearching && detailID == nil && flags.isEmpty && draft.isEmpty {
            let ids = visibleRows.map { $0.task.id }
            if event.keyCode == 125 || event.keyCode == 126 {
                guard !ids.isEmpty else { return true }
                let index = selectedTaskID.flatMap { ids.firstIndex(of: $0) } ?? (event.keyCode == 125 ? -1 : ids.count)
                selectedTaskID = ids[max(0, min(ids.count - 1, index + (event.keyCode == 125 ? 1 : -1)))]
                return true
            }
            if event.keyCode == 36, selectedTaskID != nil { openSelected(); return true }
        }
        return false
    }
}

@MainActor private final class TabColorPicker: NSObject {
    private var tabID: UUID?
    private let update: (UUID, String) -> Void
    init(update: @escaping (UUID, String) -> Void) { self.update = update }
    func show(for tab: TaskTab) {
        tabID = tab.id
        let rgb = UInt32(tab.colorHex ?? "BDBDBD", radix: 16) ?? 0xBDBDBD
        let panel = NSColorPanel.shared
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.level = .floating
        panel.title = "Color · \(tab.name)"
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
        panel.makeKey()
    }
    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let tabID, let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        func channel(_ value: CGFloat) -> Int { Int(min(255, max(0, (value * 255).rounded()))) }
        let hex = String(format: "%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
        update(tabID, hex)
    }
}
