import SwiftUI
#if SWIFT_PACKAGE
import TasklistCore
#endif

private let neutralAccent = Color(white: 0.74)

struct PanelView: View {
    @ObservedObject var store: AppStore
    private enum Field: Hashable { case add, search, subtask, notes }
    @FocusState private var focusedField: Field?
    @State private var hoveredMoveTaskID: UUID?
    @State private var hoveredTaskID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var rowGestureActive = false
    @State private var rowGestureID: UUID?
    @State private var rowGesture = TaskRowDragGesture()
    @State private var taskRowFrames: [UUID: CGRect] = [:]
    @State private var dragFrames: [UUID: CGRect] = [:]
    @State private var dragSiblings: [UUID] = []
    @State private var dragBranches: [UUID: UUID] = [:]
    @State private var dragTranslation: CGFloat = 0
    @State private var dragBlockHeight: CGFloat = 0
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var tabDragFrames: [UUID: CGRect] = [:]
    @State private var tabDragID: UUID?
    @State private var tabDragTarget: UUID?
    @State private var tabDragTranslation: CGFloat = 0
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
            swipeIndicator

        }
        .frame(width: 400, height: 560)
        .coordinateSpace(name: "taskReorder")
        .onPreferenceChange(TaskRowFrames.self) { taskRowFrames = $0 }
        .preferredColorScheme(.dark)
        .tint(accent)
        .foregroundStyle(.primary)
        .onAppear { focusEntry() }
        .onChange(of: store.focusRequest) { _, _ in
            focusEntry()
        }
        .onChange(of: store.isSearching) { _, _ in cancelTaskInteraction(); focusEntry() }
        .onChange(of: store.detailID) { _, _ in cancelTaskInteraction(); focusEntry() }
        .onChange(of: store.workspace.selectedTabID) { _, _ in cancelTaskInteraction() }
        .onChange(of: store.prompt != nil) { _, showing in if showing { cancelTaskInteraction() } }
        .onChange(of: rowGestureActive) { _, active in
            // GestureState also resets when a drag is cancelled without onEnded.
            if !active { cancelTaskInteraction() }
        }
        .onDisappear { cancelTaskInteraction() }
        .onChange(of: store.query) { _, _ in store.searchIndex = 0 }
        .popover(isPresented: $store.showHelp, arrowEdge: .top) { helpView }
        .popover(isPresented: Binding(get: { store.appearanceTabID != nil }, set: { if !$0 { store.appearanceTabID = nil } }), arrowEdge: .trailing) {
            if let id = store.appearanceTabID { TabAppearanceView(store: store, tabID: id) }
        }
        .onChange(of: store.appearanceTabID) { _, id in
            if id == nil { store.flush() }
        }
    }

    private var swipeIndicator: some View {
        let progress = store.swipeProgress
        let back = store.swipeDirection == 1
        // Draw only the exposed half, then mirror the entire indicator. Trimming
        // a full circle independently on each edge hid different progress ranges.
        return ZStack {
            Circle().fill(Color(white: 0.16))
            Circle().trim(from: 0, to: 0.5)
                .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                .rotationEffect(.degrees(-90)).padding(5)
            Circle().trim(from: 0, to: 0.5 * progress)
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(5)
            Image(systemName: "arrow.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5 + 0.5 * progress))
                .offset(x: 17)
        }
        .frame(width: 76, height: 76)
        .offset(x: -38)
        .frame(width: 38, height: 76, alignment: .leading)
        .clipped()
        .scaleEffect(x: 0.8 + 0.2 * progress, y: 0.8 + 0.2 * progress, anchor: .leading)
        .scaleEffect(x: back ? 1 : -1, y: 1)
        .shadow(color: .black.opacity(0.25), radius: 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: back ? .leading : .trailing)
        .opacity(min(1, progress * 8))
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
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
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: TabFrames.self, value: [tab.id: geometry.frame(in: .named("tabReorder"))])
                            })
                            .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("tabReorder"))
                                .onChanged { value in
                                    if tabDragID == nil {
                                        tabDragFrames = tabFrames
                                        tabDragID = tab.id
                                    }
                                    tabDragTranslation = value.translation.width
                                    updateTabDrag(tab.id)
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                                        if let target = tabDragTarget { store.reorderTab(tab.id, relativeTo: target) }
                                        tabDragID = nil
                                        tabDragTarget = nil
                                        tabDragTranslation = 0
                                    }
                                })
                            .offset(x: tabDragOffset(tab.id))
                            .zIndex(tabDragID == tab.id ? 1 : 0)
                            .shadow(color: .black.opacity(tabDragID == tab.id ? 0.25 : 0), radius: 5, y: 2)
                            .animation(tabDragID == tab.id ? nil : .spring(response: 0.24, dampingFraction: 0.86), value: tabDragTarget)
                            .help("Click to switch tabs; drag to reorder")
                            .accessibilityLabel("\(tab.name) tab")
                            .accessibilityAddTraits(store.tab.id == tab.id ? .isSelected : [])
                            .contextMenu {
                                Button("Appearance…") { store.customizeTab(tab.id) }
                                Button("Rename…") { store.beginPrompt(.renameTab(tab.id)) }
                                Button("Delete…") { store.beginPrompt(.deleteTab(tab.id)) }
                            }
                        }
                    }
                    .coordinateSpace(name: "tabReorder")
                    .onPreferenceChange(TabFrames.self) { tabFrames = $0 }
                }
                .onChange(of: store.workspace.selectedTabID) { _, id in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            iconButton("plus", "New tab · ⌘T") { store.beginPrompt(.newTab) }
            iconButton("paintpalette", "Tab color and icon · ⌘⇧A") { store.customizeTab(store.tab.id) }
        }
        .padding(.bottom, 13)
    }

    private func updateTabDrag(_ id: UUID) {
        let ids = store.workspace.tabs.map(\.id)
        guard let origin = ids.firstIndex(of: id), let frame = tabDragFrames[id] else { return }
        let center = frame.midX + tabDragTranslation
        var destination = origin
        if tabDragTranslation > 0 {
            for index in ids.indices where index > origin {
                if let other = tabDragFrames[ids[index]], center > other.midX { destination = index }
            }
        } else {
            for index in ids.indices.reversed() where index < origin {
                if let other = tabDragFrames[ids[index]], center < other.midX { destination = index }
            }
        }
        tabDragTarget = destination == origin ? nil : ids[destination]
    }

    private func tabDragOffset(_ id: UUID) -> CGFloat {
        guard let source = tabDragID else { return 0 }
        if id == source { return tabDragTranslation }
        let ids = store.workspace.tabs.map(\.id)
        guard let target = tabDragTarget, let origin = ids.firstIndex(of: source),
              let destination = ids.firstIndex(of: target), let index = ids.firstIndex(of: id),
              let frame = tabDragFrames[source] else { return 0 }
        if destination > origin && index > origin && index <= destination { return -(frame.width + 5) }
        if destination < origin && index >= destination && index < origin { return frame.width + 5 }
        return 0
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
                        LazyVStack(spacing: 2) {
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

    private func taskRow(_ task: TaskItem, depth: Int = 0, showsDisclosure: Bool = true) -> some View {
        let children = store.tab.children(of: task.id)
        let collapsed = store.collapsedTaskIDs.contains(task.id)
        return HStack(spacing: 5) {
            HStack(alignment: .center, spacing: 6) {

                if showsDisclosure {
                    if !children.isEmpty {
                        Button { store.toggleExpansion(task.id) } label: {
                            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(width: 20, height: 26).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help(collapsed ? "Expand subtasks" : "Collapse subtasks")
                            .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") subtasks: \(task.title)")
                    } else {
                        Color.clear.frame(width: 20, height: 1)
                    }
                }
                Button { store.toggle(task) } label: {
                    Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: depth > 0 ? 15 : 18, weight: .light))
                        .foregroundStyle(task.isComplete ? accent : Color.secondary.opacity(0.65))
                        .frame(width: 22, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("\(task.isComplete ? "Reopen" : "Complete") \(task.title)")
                Button { store.openTask(task.id) } label: {
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(task.title.isEmpty ? "Untitled task" : task.title)
                                .font(.system(size: depth > 0 ? 12 : 13, weight: depth > 0 ? .regular : .medium))
                                .strikethrough(task.isComplete).foregroundStyle(task.isComplete ? .secondary : .primary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            if !children.isEmpty {
                                Text("\(children.filter(\.isComplete).count)/\(children.count)")
                                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                                    .accessibilityLabel("\(children.filter(\.isComplete).count) of \(children.count) subtasks complete")
                            }
                        }
                        Spacer(minLength: 2)
                        if !task.notes.isEmpty { Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open \(task.parentID == nil ? "task" : "subtask"): \(task.title)")
                    .help("Click to open; drag vertically to reorder; drag right and release to delete")
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .padding(.leading, CGFloat(min(depth, 3)) * 12)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("taskReorder"))
                .updating($rowGestureActive) { _, active, _ in active = true }
                .onChanged { value in updateTaskInteraction(task, translation: value.translation) }
                .onEnded { value in finishTaskInteraction(task, translation: value.translation) })
            .background(store.selectedTaskID == task.id ? accent.opacity(0.10) : Color.primary.opacity(hoveredTaskID == task.id ? 0.075 : 0), in: RoundedRectangle(cornerRadius: 10))
            .onHover { hovering in
                if hovering { hoveredTaskID = task.id }
                else if hoveredTaskID == task.id { hoveredTaskID = nil }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(store.draggedTaskID == task.id ? accent.opacity(0.65) : .clear, lineWidth: 1))
            .background(store.draggedTaskID == task.id ? Color(white: 0.19) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .background(isDeletingTask(task.id) ? Color(white: 0.17) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .offset(x: isDeletingTask(task.id) ? rowGesture.offset : 0)
            .background(alignment: .leading) { deleteReveal(task.id) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(store.draggedTaskID == task.id ? 0.3 : 0), radius: 8, y: 3)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: TaskRowFrames.self, value: [task.id: geometry.frame(in: .named("taskReorder"))])
            })
            .contextMenu {
                if showsDisclosure && !children.isEmpty {
                    Button(collapsed ? "Expand subtasks" : "Collapse subtasks") { store.toggleExpansion(task.id) }
                }
                Button("Open details") { store.openTask(task.id) }
                Button("Add subtask") { store.openTask(task.id); store.focusEntry() }
                Button(task.isComplete ? "Mark incomplete" : "Complete") { store.toggle(task) }
                Divider()
                Button("Delete…") { store.beginPrompt(.deleteTask(task.id)) }
            }
            if task.parentID == nil { moveTaskMenu(task, compact: true) }
        }
        .transition(.asymmetric(insertion: .opacity, removal: reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)))
        .offset(y: taskDragOffset(task.id))
        .zIndex(isLiftedTask(task.id) ? 1 : 0)
        .animation(isLiftedTask(task.id) ? nil : .spring(response: 0.24, dampingFraction: 0.86), value: store.dropTargetID)
    }

    private var rowSpring: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82) }

    private func isDeletingTask(_ id: UUID) -> Bool {
        rowGestureID == id && rowGesture.mode == .delete
    }

    private func deleteReveal(_ id: UUID) -> some View {
        let active = isDeletingTask(id)
        let offset = active ? rowGesture.offset : 0
        let progress = min(1, offset / TaskRowDragGesture.deleteThreshold)
        let armed = active && rowGesture.isArmed
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(armed ? 0.20 : 0.08))
            Image(systemName: armed ? "trash.fill" : "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 30, height: 30)
                .background(Color.red.opacity(armed ? 0.18 : 0), in: Circle())
                .scaleEffect(reduceMotion ? 1 : (armed ? 1.12 : 0.55 + 0.45 * progress))
                .rotationEffect(.degrees(reduceMotion || armed ? 0 : -18 * (1 - progress)))
                .offset(x: min(20, max(0, (offset - 30) / 2)))
                .animation(rowSpring, value: armed)
        }
        .frame(width: max(0, offset))
        .opacity(min(1, progress * 3))
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func updateTaskInteraction(_ task: TaskItem, translation: CGSize) {
        if rowGestureID == nil { rowGestureID = task.id }
        guard rowGestureID == task.id else { return }
        if rowGesture.update(x: translation.width, y: translation.height) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if rowGesture.mode == .reorder {
            if store.draggedTaskID != task.id { beginTaskDrag(task) }
            dragTranslation = translation.height
            updateTaskDrag(task)
        }
    }

    private func finishTaskInteraction(_ task: TaskItem, translation: CGSize) {
        guard rowGestureID == task.id else { return }
        updateTaskInteraction(task, translation: translation)
        let reordering = rowGesture.mode == .reorder
        let target = store.dropTargetID
        let shouldDelete = rowGesture.isArmed
        withAnimation(rowSpring) {
            _ = rowGesture.finish(x: translation.width, y: translation.height)
            if shouldDelete { store.deleteTask(task.id) }
            else if reordering, let target { store.reorderTask(task.id, relativeTo: target) }
            resetTaskInteraction()
        }
    }

    private func resetTaskInteraction() {
        rowGestureID = nil
        rowGesture = TaskRowDragGesture()
        store.draggedTaskID = nil
        store.dropTargetID = nil
        dragTranslation = 0
    }

    private func cancelTaskInteraction() {
        guard rowGestureID != nil else { return }
        withAnimation(rowSpring) { resetTaskInteraction() }
    }

    private func beginTaskDrag(_ task: TaskItem) {
        dragFrames = taskRowFrames
        dragSiblings = store.tab.children(of: task.parentID).map(\.id).filter { dragFrames[$0] != nil }
        dragBranches = [:]
        for sibling in dragSiblings {
            for member in store.tab.descendants(of: sibling).union([sibling]) { dragBranches[member] = sibling }
        }
        let frames = dragFrames.filter { dragBranches[$0.key] == task.id }.map(\.value)
        dragBlockHeight = (frames.map(\.maxY).max() ?? 0) - (frames.map(\.minY).min() ?? 0) + 2
        dragTranslation = 0
        store.dropTargetID = nil
        store.draggedTaskID = task.id
    }

    private func updateTaskDrag(_ task: TaskItem) {
        guard let origin = dragSiblings.firstIndex(of: task.id), let frame = dragFrames[task.id] else { return }
        let center = frame.midY + dragTranslation
        var destination = origin
        if dragTranslation > 0 {
            for index in dragSiblings.indices where index > origin {
                if let other = dragFrames[dragSiblings[index]], center > other.midY { destination = index }
            }
        } else {
            for index in dragSiblings.indices.reversed() where index < origin {
                if let other = dragFrames[dragSiblings[index]], center < other.midY { destination = index }
            }
        }
        store.dropTargetID = destination == origin ? nil : dragSiblings[destination]
    }

    private func isLiftedTask(_ id: UUID) -> Bool {
        guard let source = store.draggedTaskID else { return false }
        return dragBranches[id] == source
    }

    private func taskDragOffset(_ id: UUID) -> CGFloat {
        guard let source = store.draggedTaskID, let branch = dragBranches[id] else { return 0 }
        if branch == source { return dragTranslation }
        guard let target = store.dropTargetID,
              let origin = dragSiblings.firstIndex(of: source),
              let destination = dragSiblings.firstIndex(of: target),
              let index = dragSiblings.firstIndex(of: branch) else { return 0 }
        if destination > origin && index > origin && index <= destination { return -dragBlockHeight }
        if destination < origin && index >= destination && index < origin { return dragBlockHeight }
        return 0
    }

    private func moveTaskMenu(_ task: TaskItem, compact: Bool) -> some View {
        Menu {
            ForEach(store.workspace.tabs.filter { $0.id != store.tab.id }) { destination in
                Button(destination.name) { store.moveTask(task.id, to: destination.id) }
            }
            if store.workspace.tabs.count < 2 { Text("Create another tab first") }
        } label: {
            if compact {
                Image(systemName: "rectangle.2.swap").font(.system(size: 11)).frame(width: 22, height: 24)
            } else {
                Label("Move", systemImage: "rectangle.2.swap").font(.system(size: 11))
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 2 : 5)
        .padding(.vertical, compact ? 0 : 3)
        .frame(height: compact ? (taskRowFrames[task.id]?.height ?? 32) : nil)
        .background(hoveredMoveTaskID == task.id ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: compact ? 10 : 6))
        .onHover { hoveredMoveTaskID = $0 ? task.id : nil }
        .help("Move task and all subtasks to another tab")
        .accessibilityLabel("Move \(task.title) to another tab")
    }

    private func detailBody(_ task: TaskItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: store.back) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Back · ⌘⌥←")
                Spacer()
                Text(task.parentID == nil ? "TASK" : "SUBTASK").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.tertiary)
                if task.parentID == nil { moveTaskMenu(task, compact: false) }
                iconButton("trash", "Delete task · ⌘⌫") { store.beginPrompt(.deleteTask(task.id)) }
            }.padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Button { store.toggle(task) } label: {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .light)).foregroundStyle(task.isComplete ? accent : .secondary)
                        }.buttonStyle(.plain).accessibilityLabel(task.isComplete ? "Reopen task" : "Complete task")
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
                        VStack(spacing: 2) {
                            ForEach(store.tab.children(of: task.id)) { child in
                                taskRow(child, showsDisclosure: false)
                            }
                        }
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
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading).padding(11)
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
            ForEach([("Show / hide", "⌘⌥;"), ("Search everything", "⌘K"), ("Previous / next tab", "⌘← / →"), ("New tab", "⌘T"), ("Tab appearance", "⌘⇧A"), ("Delete current tab", "⌘W"), ("History back / forward", "⌘⌥← / →"), ("Focus quick add", "⌘N"), ("Select / open task", "↑↓ / ↵"), ("Delete selected task", "⌘⌫"), ("Confirm / cancel", "↵ / esc")], id: \.0) { label, keys in
                HStack { Text(label); Spacer(minLength: 20); Text(keys).foregroundStyle(.secondary) }.font(.system(size: 12))
            }
            Text("Swipe right to go back; left to go forward.\nRight-click a task or tab for more actions.\nDescriptions support Markdown links, emphasis, lists, and headings.")
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


private struct TaskRowFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TabFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
