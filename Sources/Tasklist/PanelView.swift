import SwiftUI
#if SWIFT_PACKAGE
import TasklistCore
#endif

private let neutralAccent = Color(white: 0.74)

struct PanelView: View {
    @ObservedObject var store: AppStore
    private enum Field: Hashable { case add, search, subtask, notes }
    @FocusState private var focusedField: Field?
    private var accent: Color { store.tab.themeColor }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                if store.isSearching { searchField; searchBody }
                else {
                    tabStrip
                    if let task = store.detail { detailBody(task) }
                    else { addField; listBody }
                }
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .blur(radius: store.prompt == nil ? 0 : 3)
            .allowsHitTesting(store.prompt == nil)
            .accessibilityHidden(store.prompt != nil)
            if store.prompt != nil { PromptView(store: store) }
        }
        .frame(width: 400, height: 560)
        .preferredColorScheme(.dark)
        .tint(accent)
        .foregroundStyle(.primary)
        .onAppear { focusEntry() }
        .onChange(of: store.focusRequest) { _, _ in
            focusEntry()
        }
        .onChange(of: store.isSearching) { _, _ in focusEntry() }
        .onChange(of: store.detailID) { _, _ in focusEntry() }
        .onChange(of: store.query) { _, _ in store.searchIndex = 0 }
        .popover(isPresented: $store.showHelp, arrowEdge: .top) { helpView }
        .popover(isPresented: Binding(get: { store.appearanceTabID != nil }, set: { if !$0 { store.appearanceTabID = nil } }), arrowEdge: .trailing) {
            if let id = store.appearanceTabID { TabAppearanceView(store: store, tabID: id) }
        }
        .onChange(of: store.appearanceTabID) { _, id in
            if id == nil { store.flush() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist").font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
            Text("Tasklist").font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()
            iconButton("magnifyingglass", "Search everything · ⌘K") { store.beginSearch() }
            Menu {
                Button("New tab…", action: { store.beginPrompt(.newTab) })
                Button("Tab appearance…  ⌘⇧A", action: { store.customizeTab(store.tab.id) })
                Button("Rename tab…", action: { store.beginPrompt(.renameTab(store.tab.id)) })
                Button("Delete tab…", action: { store.beginPrompt(.deleteTab(store.tab.id)) })
                Divider()
                Toggle("Show completed", isOn: $store.showCompleted)
                Button("Undo last deletion", action: store.undoDelete).disabled(store.undoWorkspace == nil)
                Divider()
                Button("Keyboard shortcuts", action: { store.showHelp = true })
                Button("Show local data file", action: store.revealData)
                Divider()
                Button("Quit Tasklist") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 26, height: 26) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .tint(neutralAccent)
            .help("Tab actions and settings").accessibilityLabel("Tab actions and settings")
            iconButton("minus", "Hide · ⌘⌥;") { store.hidePanel?() }
        }
        .padding(.bottom, 14)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(store.workspace.tabs) { tab in
                            Button { store.selectTab(tab.id) } label: {
                                HStack(spacing: 6) {
                                    TabIcon(id: tab.iconID).foregroundStyle(tab.themeColor).frame(width: 13, height: 13)
                                    Text(tab.name).lineLimit(1)
                                    Text("\(tab.tasks.filter { !$0.isComplete && $0.parentID == nil }.count)")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.system(size: 12, weight: store.tab.id == tab.id ? .semibold : .medium))
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .background(store.tab.id == tab.id ? tab.themeColor.opacity(0.13) : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(store.tab.id == tab.id ? tab.themeColor.opacity(0.28) : .clear, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain).id(tab.id)
                            .accessibilityLabel("\(tab.name) tab")
                            .accessibilityAddTraits(store.tab.id == tab.id ? .isSelected : [])
                            .contextMenu {
                                Button("Appearance…") { store.customizeTab(tab.id) }
                                Button("Rename…") { store.beginPrompt(.renameTab(tab.id)) }
                                Button("Delete…") { store.beginPrompt(.deleteTab(tab.id)) }
                            }
                        }
                    }
                }
                .onChange(of: store.workspace.selectedTabID) { _, id in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            iconButton("plus", "New tab · ⌘T") { store.beginPrompt(.newTab) }
            iconButton("paintpalette", "Tab color and icon · ⌘⇧A") { store.customizeTab(store.tab.id) }
        }
        .padding(.bottom, 13)
    }

    private var addField: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").foregroundStyle(accent)
            TextField("Add a task…", text: $store.draft)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($focusedField, equals: .add).onSubmit(store.addTask)
                .accessibilityLabel("Add a task")
            if !store.draft.isEmpty {
                Button(action: store.addTask) { Image(systemName: "arrow.turn.down.left").foregroundStyle(accent) }
                    .buttonStyle(.plain).accessibilityLabel("Create task")
            } else { keycap("↵") }
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(focusedField == .add ? 0.2 : 0.08), lineWidth: 0.5))
        .padding(.bottom, 14)
    }

    private var listBody: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(store.tab.tasks.filter { !$0.isComplete }.count) remaining")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if !store.tab.tasks.isEmpty {
                    Button { store.showCompleted.toggle() } label: {
                        Text(store.showCompleted ? "Hide completed" : "Show completed").font(.system(size: 10))
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if store.visibleRows.isEmpty {
                emptyState(symbol: store.tab.tasks.isEmpty ? "sparkle" : "checkmark.circle", title: store.tab.tasks.isEmpty ? "A little room to think." : "All clear.", subtitle: store.tab.tasks.isEmpty ? "Add your first task above.\nKeep the big picture. Break it into small steps." : "Your completed tasks are tucked away.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(store.visibleRows, id: \.task.id) { row in
                                taskRow(row.task, depth: row.depth).id(row.task.id)
                            }
                        }.padding(.bottom, 8)
                    }
                    .onChange(of: store.selectedTaskID) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func taskRow(_ task: TaskItem, depth: Int = 0) -> some View {
        let children = store.tab.children(of: task.id)
        return HStack(alignment: .center, spacing: 9) {
            if depth > 0 { Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(.tertiary) }
            Button { store.toggle(task) } label: {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: depth > 0 ? 15 : 18, weight: .light))
                    .foregroundStyle(task.isComplete ? accent : Color.secondary.opacity(0.65))
                    .frame(width: 22, height: 28)
            }.buttonStyle(.plain).accessibilityLabel("\(task.isComplete ? "Reopen" : "Complete") \(task.title)")
            Button { store.openTask(task.id) } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title.isEmpty ? "Untitled task" : task.title)
                            .font(.system(size: depth > 0 ? 12 : 13, weight: depth > 0 ? .regular : .medium))
                            .strikethrough(task.isComplete).foregroundStyle(task.isComplete ? .secondary : .primary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        if !children.isEmpty {
                            Label("\(children.filter(\.isComplete).count)/\(children.count) subtasks", systemImage: "list.bullet.indent")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 2)
                    if !task.notes.isEmpty { Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(task.parentID == nil ? "task" : "subtask"): \(task.title)")
        }
        .padding(.vertical, 7).padding(.horizontal, 9)
        .padding(.leading, CGFloat(min(depth, 3)) * 12)
        .background(store.selectedTaskID == task.id ? accent.opacity(0.10) : .primary.opacity(depth == 0 ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Open details") { store.openTask(task.id) }
            Button("Add subtask") { store.openTask(task.id); store.focusEntry() }
            Button(task.isComplete ? "Mark incomplete" : "Complete") { store.toggle(task) }
            Divider()
            Button("Delete…") { store.beginPrompt(.deleteTask(task.id)) }
        }
    }

    private func detailBody(_ task: TaskItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: store.back) {
                    Label(task.parentID == nil ? "All tasks" : "Parent task", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Back · ⌘⌥←")
                Spacer()
                Text(task.parentID == nil ? "TASK" : "SUBTASK").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.tertiary)
                iconButton("trash", "Delete task · ⌘⌫") { store.beginPrompt(.deleteTask(task.id)) }
            }.padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(alignment: .top, spacing: 10) {
                        Button { store.toggle(task) } label: {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .light)).foregroundStyle(task.isComplete ? accent : .secondary)
                        }.buttonStyle(.plain).padding(.top, 3).accessibilityLabel(task.isComplete ? "Reopen task" : "Complete task")
                        TextField("Task title", text: Binding(get: { store.detail?.title ?? "" }, set: { store.updateTask(task.id, title: $0) }), axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 20, weight: .semibold, design: .rounded))
                            .lineLimit(1...4).accessibilityLabel("Task title")
                    }
                    descriptionSection(task)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            sectionLabel("SUBTASKS")
                            Spacer()
                            let children = store.tab.children(of: task.id)
                            Text("\(children.filter(\.isComplete).count) / \(children.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        ForEach(store.tab.children(of: task.id)) { child in taskRow(child, depth: 1) }
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(accent)
                            TextField("Add a subtask…", text: $store.subtaskDraft).textFieldStyle(.plain)
                                .font(.system(size: 12)).focused($focusedField, equals: .subtask).onSubmit(store.addSubtask)
                                .accessibilityLabel("Add a subtask")
                            Button(action: store.addSubtask) { Image(systemName: "plus.circle.fill").foregroundStyle(accent) }
                                .buttonStyle(.plain).accessibilityLabel("Create subtask").disabled(store.subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(11).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(.bottom, 14)
            }
        }.frame(maxHeight: .infinity)
    }

    private func descriptionSection(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("DESCRIPTION")
                Spacer()
                Button { store.editingNotes.toggle() } label: {
                    Text(store.editingNotes ? "Done" : "Edit").font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel(store.editingNotes ? "Preview description" : "Edit description")
            }
            if store.editingNotes {
                TextEditor(text: Binding(get: { store.detail?.notes ?? "" }, set: { store.updateTask(task.id, notes: $0) }))
                    .focused($focusedField, equals: .notes)
                    .onAppear { DispatchQueue.main.async { focusedField = .notes } }
                    .font(.system(size: 12)).scrollContentBackground(.hidden)
                    .frame(minHeight: 105, maxHeight: 160).padding(7)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Description markdown")
                Text("Markdown: **bold**, *italic*, [link](https://…)").font(.system(size: 9)).foregroundStyle(.tertiary)
            } else if task.notes.isEmpty {
                Button { store.editingNotes = true } label: {
                    Text("Add notes, links, or a little context…")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading).padding(11)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel("Add description")
            } else {
                MarkdownNotes(text: task.notes)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(accent)
            TextField("Search all tabs, tasks, and notes…", text: $store.query)
                .textFieldStyle(.plain).font(.system(size: 13)).focused($focusedField, equals: .search)
                .accessibilityLabel("Search everything")
            Button { store.back() } label: { keycap("esc") }.buttonStyle(.plain).accessibilityLabel("Close search")
        }.padding(12).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 14)
    }

    private var searchBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(store.query.isEmpty ? "EVERYTHING" : "\(store.searchResults.count) RESULTS")
            if store.searchResults.isEmpty {
                emptyState(symbol: "magnifyingglass", title: "Nothing here yet.", subtitle: "Try another word or search a tab name.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { index, result in
                                Button { store.openSearchResult(result) } label: {
                                    HStack(spacing: 10) {
                                        let resultTab = store.workspace.tabs.first { $0.id == result.tabID }
                                        Group {
                                            if result.taskID == nil { TabIcon(id: resultTab?.iconID).frame(width: 17, height: 17) }
                                            else { Image(systemName: result.isComplete ? "checkmark.circle.fill" : "circle").font(.system(size: 16)) }
                                        }.foregroundStyle(resultTab?.themeColor ?? neutralAccent).frame(width: 22)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            Text(result.context).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        if index == store.searchIndex { keycap("↵") }
                                    }.padding(10).contentShape(Rectangle())
                                        .background(index == store.searchIndex ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).id(result.id)
                            }
                        }
                    }.onChange(of: store.searchIndex) { _, index in
                        if store.searchResults.indices.contains(index) { proxy.scrollTo(store.searchResults[index].id) }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            if let error = store.storageError ?? store.hotkeyError {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(3).padding(.top, 6)
            }
            HStack(spacing: 5) {
                Circle().fill(store.storageError == nil ? accent : .red).frame(width: 4, height: 4)
                Text(store.storageError == nil ? "On your Mac" : "Save needs attention").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if store.isSearching { Text("↑↓ navigate   ↵ open").font(.system(size: 10)).foregroundStyle(.tertiary) }
                else if store.detailID != nil { Text("⌘⌥← back").font(.system(size: 10)).foregroundStyle(.tertiary) }
                else { Text("⌘K search").font(.system(size: 10)).foregroundStyle(.tertiary) }
                Button { store.showHelp = true } label: { Image(systemName: "questionmark.circle").font(.system(size: 11)).foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Keyboard shortcuts").accessibilityLabel("Keyboard shortcuts")
            }.padding(.vertical, 12)
        }
    }

    private var helpView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make yourself at home.").font(.system(size: 16, weight: .semibold, design: .rounded))
            ForEach([("Show / hide", "⌘⌥;"), ("Search everything", "⌘K"), ("Previous / next tab", "⌘← / →"), ("New tab", "⌘T"), ("Tab appearance", "⌘⇧A"), ("Delete current tab", "⌘W"), ("List / task detail", "⌘⌥← / →"), ("Focus quick add", "⌘N"), ("Select / open task", "↑↓ / ↵"), ("Delete selected task", "⌘⌫"), ("Confirm / cancel", "↵ / esc")], id: \.0) { label, keys in
                HStack { Text(label); Spacer(minLength: 20); Text(keys).foregroundStyle(.secondary) }.font(.system(size: 12))
            }
            Text("Right-click a task or tab for more actions.\nDescriptions support Markdown links, emphasis, lists, and headings.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(22).frame(width: 320)
    }

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 31, weight: .ultraLight)).foregroundStyle(accent.opacity(0.75))
            Text(title).font(.system(size: 17, weight: .medium, design: .rounded))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Spacer()
            Spacer().frame(height: 15)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionLabel(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary) }
    private func focusEntry() {
        focusedField = nil
        // Wait until SwiftUI has installed the field for the new navigation state.
        DispatchQueue.main.async {
            guard store.prompt == nil, store.appearanceTabID == nil else { return }
            focusedField = store.isSearching ? .search : (store.detailID == nil ? .add : .subtask)
        }
    }
    private func keycap(_ text: String) -> some View { Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).padding(.horizontal, 4).padding(.vertical, 2).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4)) }
    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 26, height: 26).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

private struct PromptView: View {
    @ObservedObject var store: AppStore
    private var accent: Color { store.tab.themeColor }
    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: store.isDeletePrompt ? "trash" : "rectangle.stack.badge.plus")
                    .font(.system(size: 24, weight: .light)).foregroundStyle(store.isDeletePrompt ? .red : accent)
                Text(store.promptTitle).font(.system(size: 19, weight: .semibold, design: .rounded))
                Text(store.promptMessage).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !store.isDeletePrompt {
                    PromptTextField(text: $store.promptText, selectAll: {
                        if case .renameTab = store.prompt { return true }
                        return false
                    }()).frame(height: 24)
                }
                HStack {
                    Button("Cancel  esc") { store.prompt = nil; store.focusEntry() }.buttonStyle(.bordered)
                    Spacer()
                    Button(store.isDeletePrompt ? "Delete  ↵" : "Save  ↵", action: store.confirmPrompt)
                        .buttonStyle(.borderedProminent).tint(store.isDeletePrompt ? .red : accent)
                        .disabled(!store.isDeletePrompt && store.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.top, 4)
            }.padding(22).frame(width: 330)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }
    }
}

// Focus synchronously when the field joins the window. Deferring SwiftUI focus
// can select or discard the first character when someone types immediately.
private struct PromptTextField: NSViewRepresentable {
    @Binding var text: String
    var selectAll: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ImmediateFocusField {
        let field = ImmediateFocusField(string: text)
        field.selectAllInitially = selectAll
        field.placeholderString = "Tab name"
        field.setAccessibilityLabel("Tab name")
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: ImmediateFocusField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PromptTextField
        init(_ parent: PromptTextField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
    }
    final class ImmediateFocusField: NSTextField {
        var selectAllInitially = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.makeFirstResponder(self)
            let length = (stringValue as NSString).length
            currentEditor()?.selectedRange = selectAllInitially ? NSRange(location: 0, length: length) : NSRange(location: length, length: 0)
        }
    }
}

private struct MarkdownNotes: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let heading = line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ")
                let bullet = line.hasPrefix("- ") || line.hasPrefix("* ")
                let content = heading ? String(line.drop(while: { $0 == "#" || $0 == " " })) : (bullet ? "• " + line.dropFirst(2) : line)
                Text((try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content))
                    .font(.system(size: heading ? 14 : 12, weight: heading ? .semibold : .regular))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.environment(\.openURL, OpenURLAction { url in
            guard ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
    }
}

private extension TaskTab {
    var themeColor: Color {
        guard let hex = colorHex, hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return neutralAccent }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

private struct TabIcon: View {
    static let choices: [(id: String, name: String)] = [
        ("list", "List"), ("briefcase", "Work"), ("home", "Home"), ("star", "Star"),
        ("code", "Code"), ("book", "Book"), ("heart", "Heart"), ("flag", "Flag"),
        ("folder", "Folder"), ("bolt", "Bolt"), ("calendar", "Calendar"), ("coffee", "Coffee")
    ]
    let id: String?
    var body: some View {
        let name = id?.hasPrefix("lucide:") == true
            ? IconCatalog.icon(for: id).map { "Lucide-" + $0.id } ?? "TabIcon-list"
            : "TabIcon-" + (Self.choices.contains(where: { $0.id == id }) ? id! : "list")
        #if SWIFT_PACKAGE
        Image(name, bundle: .module).resizable().scaledToFit().accessibilityHidden(true)
        #else
        Image(name).resizable().scaledToFit().accessibilityHidden(true)
        #endif
    }
}

private struct TabAppearanceView: View {
    @ObservedObject var store: AppStore
    let tabID: UUID
    @State private var iconQuery = ""
    @State private var results = IconCatalog.all
    @FocusState private var searchFocused: Bool
    private var tab: TaskTab? { store.workspace.tabs.first { $0.id == tabID } }
    private let palette: [(name: String, hex: String)] = [
        ("Neutral", "BDBDBD"), ("Red", "DC4545"), ("Orange", "C96B24"), ("Gold", "B38A16"),
        ("Green", "328264"), ("Teal", "24878F"), ("Blue", "3478D4"), ("Indigo", "6560C8"),
        ("Purple", "9555BC"), ("Pink", "C9548C"), ("Brown", "947158"), ("Silver", "87929E")
    ]
    var body: some View {
        if let tab {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    TabIcon(id: tab.iconID).foregroundStyle(tab.themeColor).frame(width: 20, height: 20)
                    Text(tab.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button("Done") { store.appearanceTabID = nil }.buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Color").font(.system(size: 12, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(palette, id: \.hex) { item in
                            let selected = (tab.colorHex ?? "BDBDBD") == item.hex
                            Button { store.setTabAppearance(tabID, colorHex: item.hex) } label: {
                                Circle().fill(TaskTab(name: "", colorHex: item.hex).themeColor)
                                    .frame(width: 25, height: 25)
                                    .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(selected ? tab.themeColor.opacity(0.6) : .clear, lineWidth: 1))
                            }.buttonStyle(.plain).help(item.name).accessibilityLabel("\(item.name) tab color")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    Button { store.openCustomTabColor(tabID) } label: {
                        HStack {
                            Text("Custom color…")
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).fill(tab.themeColor).frame(width: 24, height: 16)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
                        }.font(.system(size: 12)).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Custom tab color")
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Icon").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(results.count) icons").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search icons…", text: $iconQuery).textFieldStyle(.plain)
                            .focused($searchFocused).accessibilityLabel("Search tab icons")
                            .onSubmit { if let first = results.first { store.setTabAppearance(tabID, iconID: first.storedID) } }
                        if !iconQuery.isEmpty {
                            Button { iconQuery = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).accessibilityLabel("Clear icon search")
                        }
                    }.font(.system(size: 12)).padding(9).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                                ForEach(results) { item in
                                    let selected = tab.iconID == item.storedID
                                    Button { store.setTabAppearance(tabID, iconID: item.storedID) } label: {
                                        TabIcon(id: item.storedID).frame(width: 18, height: 18)
                                            .foregroundStyle(selected ? tab.themeColor : .secondary)
                                            .frame(width: 34, height: 34)
                                            .background(selected ? tab.themeColor.opacity(0.13) : .primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? tab.themeColor.opacity(0.3) : .clear, lineWidth: 1))
                                    }.buttonStyle(.plain).help(item.name).accessibilityLabel("\(item.name) tab icon")
                                        .accessibilityAddTraits(selected ? .isSelected : []).id(item.id)
                                }
                            }.padding(.trailing, 2)
                            if results.isEmpty {
                                Text("No icons found. Try another word.").font(.system(size: 12)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                            }
                        }
                        .frame(height: 160)
                        .onChange(of: iconQuery) { _, query in
                            results = IconCatalog.search(query)
                            if let first = results.first { DispatchQueue.main.async { proxy.scrollTo(first.id, anchor: .top) } }
                        }
                    }
                    Text("Selected: \(IconCatalog.icon(for: tab.iconID)?.name ?? TabIcon.choices.first(where: { $0.id == (tab.iconID ?? "list") })?.name ?? "List")")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("Changes save automatically for this tab.").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(18).frame(width: 300).preferredColorScheme(.dark).tint(neutralAccent)
                .onAppear { DispatchQueue.main.async { searchFocused = true } }
        }
    }
}
