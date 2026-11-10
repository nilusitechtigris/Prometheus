import AppKit
import SwiftUI

/// Dev mode: the project's files, an editor over a Terminal, and the coding agent, all in the window.
struct DevWorkspaceView: View {
    @Environment(DevSession.self) private var dev
    @AppStorage("devFilesWidth") private var filesWidth = 200.0
    @AppStorage("devAgentWidth") private var agentWidth = 340.0
    @AppStorage("devTerminalHeight") private var terminalHeight = 240.0

    var body: some View {
        VStack(spacing: 0) {
            // One side of a comparison filling the window takes the bar's room too.
            if !dev.compareFillsWindow {
                DevTopBar()
                Forge.rule()
            }
            if dev.showsCompare {
                DevCompareView()
            } else if dev.project == nil {
                DevWelcome()
            } else {
                // Sized by hand: a split view shares out the width by itself and doesn't remember it.
                HStack(spacing: 0) {
                    if !dev.previewFills {
                        DevFilesColumn().frame(width: filesWidth)
                        DevDivider(size: $filesWidth, range: 150...360, axis: .horizontal, growsTowardEnd: true)
                    }
                    VStack(spacing: 0) {
                        DevEditorPane().frame(maxHeight: .infinity)
                        if !dev.previewFills {
                            DevDivider(size: $terminalHeight, range: 100...560, axis: .vertical, growsTowardEnd: false)
                            DevTerminalPane().frame(height: terminalHeight)
                        }
                    }
                    .frame(minWidth: 300, maxWidth: .infinity)
                    if !dev.previewFills {
                        DevDivider(size: $agentWidth, range: 260...560, axis: .horizontal, growsTowardEnd: false)
                        DevAgentColumn().frame(width: agentWidth)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in dev.refreshFromDisk() }
        .overlay(alignment: .top) {
            if let failure = dev.failureText {
                ErrorBanner(text: failure) { dev.failureText = nil }
                    .padding(.horizontal, 20)
                    .padding(.top, 52)
            }
        }
    }
}

/// A line between two panes that drags to resize them.
private struct DevDivider: View {
    @Binding var size: Double
    let range: ClosedRange<Double>
    let axis: Axis
    /// Whether dragging toward the right or bottom makes the pane larger.
    let growsTowardEnd: Bool
    @State private var start: Double?
    @State private var hovering = false

    var body: some View {
        (hovering ? Palette.accent.opacity(0.6) : Forge.line)
            .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            .overlay {
                Color.clear
                    .frame(width: axis == .horizontal ? 9 : nil, height: axis == .vertical ? 9 : nil)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        if inside {
                            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let begin = start ?? size
                            start = begin
                            let moved = Double(axis == .horizontal ? drag.translation.width : drag.translation.height)
                            size = min(max(begin + (growsTowardEnd ? moved : -moved), range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in start = nil })
            }
            .zIndex(1)
    }
}

// MARK: - Top bar

private struct DevTopBar: View {
    @Environment(DevSession.self) private var dev

    var body: some View {
        HStack(spacing: 10) {
            Label("Dev", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.uiHeadline)
                .foregroundStyle(Palette.accent)
            if let project = dev.project {
                Menu {
                    Button("New Project…") { dev.newProject() }
                    Button("Open Folder…") { dev.chooseFolder() }
                    Button("Show in Finder") { dev.revealInFinder() }
                    let others = dev.recents.filter { $0 != project.root.path }
                    if !others.isEmpty {
                        Divider()
                        ForEach(others, id: \.self) { path in
                            Button((path as NSString).lastPathComponent) { dev.open(URL(fileURLWithPath: path)) }
                        }
                    }
                    Divider()
                    Button("Close Project") { dev.closeProject() }
                } label: {
                    Text(project.name).font(.uiCallout.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(project.root.path)
            }
            Spacer(minLength: 8)
            if !dev.comparisons.isEmpty || dev.isComparing {
                Button {
                    withAnimation(Motion.quick) {
                        dev.showsCompare.toggle()
                        dev.compareFills = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        if dev.isComparing { ProgressView().controlSize(.mini) } else { Image(systemName: "square.split.2x1") }
                        Text(dev.showsCompare ? "Close Compare" : "Compare")
                    }
                    .font(.uiCallout.weight(dev.showsCompare ? .semibold : .regular))
                    .foregroundStyle(dev.showsCompare ? Palette.accent : Forge.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
                .help("The same request built with the harness off and on, side by side")
            }
            GlassGroup(spacing: 6) {
                FrameworkPickerButton(compact: true)
                ModelPickerButton(narrow: true)
                ContextPickerButton(compact: true)
            }
            .fixedSize()
            Button {
                withAnimation(Motion.quick) { dev.isOn = false }
            } label: {
                Label("Back to Chat", systemImage: "bubble.left")
                    .font(.uiCallout)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(interactive: true)
            .help("Leave Dev mode. Your project stays open here.")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - With no project open

private struct DevWelcome: View {
    @Environment(DevSession.self) private var dev
    @State private var request = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("Start a project").font(Brand.display(26))
            Text("The agent builds web apps and Python programs with a model on this Mac: it plans, writes each file, tries the result and fixes what fails. Pages play in Preview and programs run in a sandbox, with no network and nothing outside the folder.")
                .font(.uiBody)
                .foregroundStyle(Forge.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            HStack(spacing: 10) {
                Button("New Project…") { dev.newProject() }
                    .buttonStyle(AccentButtonStyle())
                Button("Open Folder…") { dev.chooseFolder() }
                    .buttonStyle(OutlineButtonStyle())
            }
            DevCompareStarter(request: $request)
                .frame(width: 460)
                .padding(.top, 10)
            if !dev.recents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Forge.label("Recent").padding(.bottom, 2)
                    ForEach(dev.recents, id: \.self) { path in
                        Button {
                            dev.open(URL(fileURLWithPath: path))
                        } label: {
                            Label((path as NSString).lastPathComponent, systemImage: "folder")
                                .font(.uiCallout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(path)
                    }
                }
                .frame(width: 280)
                .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Files

private struct DevFilesColumn: View {
    @Environment(DevSession.self) private var dev
    @State private var creating = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    private var visible: [DevEntry] {
        dev.entries.filter { entry in
            !dev.collapsed.contains { entry.path.hasPrefix($0 + "/") }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Forge.label("Files")
                Spacer()
                if !dev.testFiles.isEmpty {
                    Button(action: dev.runTests) { Image(systemName: "checkmark.diamond") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Forge.dim)
                        .help("Run the tests")
                }
                Button {
                    creating = true
                    nameFocused = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Forge.dim)
                .help("New file")
                Button(action: dev.refreshFromDisk) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Forge.dim)
                    .help("Reload the file list")
            }
            .font(.uiCaption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if creating {
                TextField("name.py", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.geistMono(12))
                    .focused($nameFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Forge.card)
                    .onSubmit {
                        dev.newFile(named: newName)
                        newName = ""
                        creating = false
                    }
                    .onExitCommand {
                        newName = ""
                        creating = false
                    }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { entry in
                        DevFileRow(entry: entry)
                    }
                }
                .padding(.vertical, 2)
            }
            if dev.entries.isEmpty {
                Text("Nothing here yet. Ask the agent to write something.")
                    .font(.uiCaption)
                    .foregroundStyle(Forge.faint)
                    .multilineTextAlignment(.center)
                    .padding(16)
                Spacer()
            }
        }
        .background(Forge.black.opacity(0.35))
    }
}

private struct DevFileRow: View {
    @Environment(DevSession.self) private var dev
    let entry: DevEntry
    @State private var hovering = false

    private var isOpen: Bool { entry.path == dev.openPath }

    var body: some View {
        HStack(spacing: 5) {
            if entry.isFolder {
                Image(systemName: dev.collapsed.contains(entry.path) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Forge.faint)
                    .frame(width: 12)
            }
            Image(systemName: entry.isFolder ? "folder" : entry.isPython ? "curlybraces" : entry.isPage ? "globe" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(entry.isRunnable ? Palette.accent : Forge.dim)
            Text(entry.name)
                .font(.uiCallout)
                .foregroundStyle(isOpen ? Forge.ink : Forge.dim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            if entry.isRunnable, hovering || isOpen {
                Button {
                    dev.run(entry.path)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(dev.isWorking && !entry.isPage)
                .help(entry.isPage ? "Open \(entry.name) in Preview" : dev.isWorking ? "The agent is working on this folder" : "Run \(entry.name) in the Terminal")
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 12 + 10)
        .padding(.trailing, 6)
        .frame(height: 26)
        .background(isOpen ? Palette.accent.opacity(0.12) : hovering ? Color.white.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if entry.isFolder {
                if dev.collapsed.contains(entry.path) { dev.collapsed.remove(entry.path) } else { dev.collapsed.insert(entry.path) }
            } else {
                dev.openFile(entry.path)
            }
        }
        .contextMenu {
            if entry.isRunnable { Button(entry.isPage ? "Open in Preview" : "Run") { dev.run(entry.path) } }
            Button("Show in Finder") { dev.revealInFinder(entry.path) }
            Divider()
            Button("Move to Trash", role: .destructive) { dev.trash(entry.path) }
                .disabled(dev.isWorking)
        }
    }
}

// MARK: - Editor

private struct DevEditorPane: View {
    @Environment(DevSession.self) private var dev

    var body: some View {
        @Bindable var dev = dev
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let page = dev.previewPath {
                    Button {
                        dev.closePreview()
                    } label: {
                        Label("Code", systemImage: "chevron.left")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .controlSize(.small)
                    .help("Back to the code")
                    Text(page).font(.geistMono(12)).foregroundStyle(Forge.dim).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button {
                        dev.previewFills.toggle()
                    } label: {
                        Image(systemName: dev.previewFills ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Forge.dim)
                    .help(dev.previewFills ? "Show the other panes" : "Fill the window")
                    Button {
                        dev.preview(page)
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(AccentButtonStyle(compact: true))
                    .help("Start the page again (⌘R)")
                } else if let path = dev.openPath {
                    Text(path).font(.geistMono(12)).foregroundStyle(Forge.dim).lineLimit(1).truncationMode(.middle)
                    if dev.isDirty {
                        Circle().fill(Palette.warning).frame(width: 7, height: 7).help("Unsaved changes")
                    }
                    Spacer(minLength: 4)
                    if dev.isDirty {
                        Button("Save", action: dev.save)
                            .buttonStyle(OutlineButtonStyle())
                            .controlSize(.small)
                    }
                    if path.hasSuffix(".py") || DevWeb.isPage(path) {
                        Button {
                            dev.runOpenFile()
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(AccentButtonStyle(compact: true))
                        .disabled(dev.isWorking && !DevWeb.isPage(path))
                        .help(DevWeb.isPage(path) ? "Open this page in Preview (⌘R)" : dev.isWorking ? "The agent is working on this folder" : "Run this file in the Terminal (⌘R)")
                    }
                } else {
                    Forge.label("Editor", color: Forge.faint)
                    Spacer()
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 12)
            Forge.rule()
            if let page = dev.previewPath, let project = dev.project {
                DevPreviewView(project: project, path: page, loadID: dev.previewLoad,
                               onMessage: { dev.pageSaid($0) }, onCrash: { dev.pageCrashed() })
            } else if dev.openPath == nil {
                Text("Choose a file, or ask the agent to write one.")
                    .font(.uiCallout)
                    .foregroundStyle(Forge.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dev.unreadable {
                Text("This file isn't text, or it's too large to show here.")
                    .font(.uiCallout)
                    .foregroundStyle(Forge.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CodeEditor(text: $dev.text, isEditable: !dev.isWorking, isPython: dev.openPath?.hasSuffix(".py") == true,
                           jump: dev.jump, errorLine: dev.errorLine)
                    .id(dev.openPath)
            }
        }
    }
}

// MARK: - Terminal

private struct DevTerminalPane: View {
    @Environment(DevSession.self) private var dev
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Terminal", systemImage: "terminal").font(.uiCaption.weight(.medium)).foregroundStyle(Forge.dim)
                if dev.isRunning {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                if dev.isRunning {
                    Button(action: dev.stopRun) {
                        Label("Stop", systemImage: "stop.fill").font(.uiCaption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.critical)
                    .help("Stop the program")
                } else if !dev.runs.isEmpty {
                    Button("Clear", action: dev.clearTerminal)
                        .buttonStyle(.plain)
                        .font(.uiCaption)
                        .foregroundStyle(Forge.dim)
                }
            }
            .frame(height: 30)
            .padding(.horizontal, 12)
            Forge.rule()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if dev.runs.isEmpty {
                            Text("Click ▶ on a Python file to run it here. Python shows text only, and can read and write this folder, with no network. For graphics and games, ask the agent for a game or a page, which plays in Preview.")
                                .font(.uiCaption)
                                .foregroundStyle(Forge.faint)
                        }
                        ForEach(dev.runs) { run in
                            DevRunView(run: run)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: dev.runs.last?.output.count) { proxy.scrollTo("end", anchor: .bottom) }
                // So someone can start typing their moves straight away.
                .onChange(of: dev.isRunning) { if dev.isRunning { inputFocused = true } }
                .onChange(of: dev.runs.last?.result) { proxy.scrollTo("end", anchor: .bottom) }
            }
            Forge.rule()
            HStack(spacing: 8) {
                Text(dev.isRunning ? ">" : "$").font(.geistMono(12)).foregroundStyle(Palette.accent)
                TextField(dev.isRunning ? "Type input for the program, then press Return" : "python \(dev.openPath.flatMap { $0.hasSuffix(".py") ? $0 : nil } ?? "main.py")", text: $input)
                    .textFieldStyle(.plain)
                    .font(.geistMono(12))
                    .focused($inputFocused)
                    .onSubmit(submit)
            }
            .frame(height: 30)
            .padding(.horizontal, 12)
        }
        .background(Forge.black.opacity(0.55))
    }

    private func submit() {
        let line = input
        input = ""
        if dev.isRunning {
            dev.sendInput(line)
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            dev.runCommand(line)
        }
        inputFocused = true
    }
}

private struct DevRunView: View {
    @Environment(DevSession.self) private var dev
    let run: DevTerminalRun

    private var shown: String {
        run.output.count > DevSession.outputShown ? "…\n" + run.output.suffix(DevSession.outputShown) : run.output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("$ \(run.command)")
                .font(.geistMono(12).weight(.medium))
                .foregroundStyle(Palette.accent)
                .lineLimit(2)
                .truncationMode(.middle)
            if !shown.isEmpty {
                Text(shown)
                    .font(.geistMono(12))
                    .foregroundStyle(Forge.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if run.isPage {
                if run.failure == nil {
                    Label("Open in Preview", systemImage: "globe").font(.uiCaption).foregroundStyle(Forge.dim)
                } else if let result = run.result {
                    ending(result)
                }
            } else if let result = run.result, run.arguments.first != nil {
                ending(result)
            }
            if run.failure?.kind == "ModuleNotFoundError" {
                Text("Programs here have Python's standard library only, since the sandbox can't see packages you've installed elsewhere.")
                    .font(.uiCaption)
                    .foregroundStyle(Forge.dim)
            }
            if run.failure?.isSandboxLimit == true {
                Text("The sandbox blocked this: programs here can't use the network or touch files outside this folder.")
                    .font(.uiCaption)
                    .foregroundStyle(Forge.dim)
            }
        }
    }

    @ViewBuilder
    private func ending(_ result: DevRunResult) -> some View {
        HStack(spacing: 8) {
            if result.stoppedByUser {
                Label("Stopped", systemImage: "stop.circle").foregroundStyle(Forge.dim)
            } else if let limit = result.limit {
                Label("Stopped: it \(limit)", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.warning)
            } else if result.succeeded {
                Label(run.output.isEmpty ? "Finished, and it printed nothing" : "Finished", systemImage: "checkmark.circle")
                    .foregroundStyle(run.output.isEmpty ? Forge.dim : Palette.good)
            } else {
                Label(run.isPage ? "The page has an error" : "Exit code \(result.exitCode)", systemImage: "xmark.circle").foregroundStyle(Palette.critical)
            }
            Text(Format.seconds(result.seconds)).foregroundStyle(Forge.faint)
            if let failure = run.failure {
                if let file = failure.file, let line = failure.line {
                    Button("\(file):\(line)") { dev.openFile(file, line: line) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Forge.dim)
                        .underline()
                        .help("Show this line in the editor")
                }
                Button {
                    dev.fix(run)
                } label: {
                    Label("Fix with Agent", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
                .disabled(!dev.canSend)
                .help(dev.blockedReason ?? "Ask the agent to fix this")
            }
        }
        .font(.uiCaption)
    }
}

// MARK: - Agent

private struct DevAgentColumn: View {
    @Environment(DevSession.self) private var dev

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Agent", systemImage: "sparkles").font(.uiCaption.weight(.medium)).foregroundStyle(Forge.dim)
                Spacer()
                DevHarnessSwitch()
                if !dev.messages.isEmpty, !dev.isWorking {
                    Button("Clear", action: dev.clearConversation)
                        .buttonStyle(.plain)
                        .font(.uiCaption)
                        .foregroundStyle(Forge.dim)
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 12)
            Forge.rule()
            if dev.messages.isEmpty {
                DevSuggestions()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(dev.messages) { message in
                                if message.isUser {
                                    DevUserBubble(text: message.text)
                                } else {
                                    DevReplyView(message: message, isLive: dev.isWorking && message.id == dev.messages.last?.id)
                                }
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(12)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: dev.messages.last?.steps.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: dev.writing.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: dev.isWorking) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            Forge.rule()
            DevComposer()
        }
        .background(Forge.black.opacity(0.35))
    }
}

private struct DevSuggestions: View {
    @Environment(DevSession.self) private var dev

    private var suggestions: [String] {
        guard let open = dev.openPath, open.hasSuffix(".py") else {
            if dev.entries.contains(where: \.isPage) {
                return ["Add a dark mode switch", "Let me sort the list by ", "Make it look more "]
            }
            return ["Make a habit tracker web app", "Make a web app where ", "Make a game where ", "Write a Python program that "]
        }
        let name = (open as NSString).lastPathComponent
        return ["Explain what \(name) does", "Add tests for \(name)", "Add error handling to \(name)"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dev.harnessOn ? "Tell the agent what to build or change. It plans, writes each file, tries the result and fixes what fails before it comes back."
                               : "The harness is off: the model gets one go, and its reply is saved as it came, with nothing run or checked. Press ⧉ to build a request both ways.")
                .font(.uiCallout)
                .foregroundStyle(Forge.dim)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    dev.draft = suggestion
                } label: {
                    Text(suggestion.trimmingCharacters(in: .whitespaces) + (suggestion.hasSuffix(" ") ? "…" : ""))
                        .font(.uiCallout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Forge.card, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DevUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 28)
            Text(text)
                .font(.uiCallout)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Palette.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct DevReplyView: View {
    @Environment(DevSession.self) private var dev
    let message: DevMessage
    let isLive: Bool

    /// While working every step shows. Afterwards only what's worth reading again does.
    private var steps: [DevStep] {
        isLive ? message.steps : message.steps.filter { $0.kind != .stage }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(steps) { DevStepRow(step: $0) }
                }
            }
            if isLive {
                if !dev.writing.isEmpty {
                    Text(dev.writing.suffix(900).split(separator: "\n", omittingEmptySubsequences: false).suffix(8).joined(separator: "\n"))
                        .font(.geistMono(11))
                        .foregroundStyle(Forge.faint)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(dev.stage ?? "Working").font(.uiCaption).foregroundStyle(Forge.dim)
                }
            }
            if !message.text.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let worked = message.worked {
                        Image(systemName: worked ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(worked ? Palette.good : Palette.warning)
                    }
                    if message.worked == nil {
                        MarkdownView(text: message.text)
                    } else {
                        Text(message.text).font(.uiCallout).textSelection(.enabled)
                    }
                }
            }
            if !message.changes.isEmpty {
                ForEach(message.changes) { DevChangeRow(change: $0, undone: message.undone) }
                HStack(spacing: 10) {
                    if message.undone {
                        Text("Undone").font(.uiCaption).foregroundStyle(Forge.faint)
                    } else {
                        Button("Undo") { dev.undo(message) }
                            .buttonStyle(.plain)
                            .font(.uiCaption)
                            .foregroundStyle(dev.canUndo(message) ? Forge.dim : Forge.faint)
                            .disabled(!dev.canUndo(message) || dev.isWorking)
                            .help(dev.canUndo(message) ? "Put these files back as they were" : "The files have changed since")
                    }
                }
            }
            if let seconds = message.seconds, seconds > 0 {
                HStack(spacing: 6) {
                    Text(Format.seconds(seconds))
                    if let calls = message.calls, calls > 0 { Text("· \(calls) model \(calls == 1 ? "call" : "calls")") }
                    if message.harness == false { Text("· harness off") }
                }
                .font(.uiCaption2)
                .foregroundStyle(Forge.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DevStepRow: View {
    let step: DevStep
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                if step.output?.isEmpty == false { open.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 12)
                    Text(step.text)
                        .font(step.kind == .run ? .geistMono(11) : .uiCaption)
                        .foregroundStyle(Forge.dim)
                        .lineLimit(open ? nil : 2)
                        .multilineTextAlignment(.leading)
                    if step.output?.isEmpty == false {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Forge.faint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open, let output = step.output {
                Text(output)
                    .font(.geistMono(11))
                    .foregroundStyle(Forge.dim)
                    .textSelection(.enabled)
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Forge.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var symbol: String {
        switch step.kind {
        case .stage: return "circle.fill"
        case .note: return "info.circle"
        case .run: return step.passed == true ? "checkmark" : "xmark"
        }
    }

    private var color: Color {
        switch step.kind {
        case .stage: return Forge.faint
        case .note: return Palette.warning
        case .run: return step.passed == true ? Palette.good : Palette.critical
        }
    }
}

private struct DevChangeRow: View {
    @Environment(DevSession.self) private var dev
    let change: DevChange
    let undone: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    open.toggle()
                } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Forge.faint)
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show what changed")
                Button {
                    dev.openFile(change.path)
                } label: {
                    Text(change.path)
                        .font(.geistMono(11))
                        .foregroundStyle(undone ? Forge.faint : Forge.ink)
                        .strikethrough(undone)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                let counts = change.counts
                Text("+\(counts.added)").foregroundStyle(Palette.good)
                Text("−\(counts.removed)").foregroundStyle(Palette.critical)
            }
            .font(.geistMono(11))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            if open { DevDiffView(change: change) }
        }
        .background(Forge.card, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// What a change added and removed, and the lines around them.
private struct DevDiffView: View {
    struct Line: Identifiable {
        let id: Int
        let text: String
        let sign: Character
    }

    let change: DevChange

    private var lines: [Line] {
        let old = (change.before ?? "").components(separatedBy: "\n")
        let new = change.after.components(separatedBy: "\n")
        let difference = new.difference(from: old)
        var removed = Set<Int>(), added = Set<Int>()
        for item in difference {
            switch item {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var result: [(String, Character)] = []
        var oldIndex = 0, newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count, removed.contains(oldIndex) {
                result.append((old[oldIndex], "-"))
                oldIndex += 1
            } else if newIndex < new.count, added.contains(newIndex) {
                result.append((new[newIndex], "+"))
                newIndex += 1
            } else {
                if newIndex < new.count { result.append((new[newIndex], " ")) }
                oldIndex += 1
                newIndex += 1
            }
        }
        let changed = result.indices.filter { result[$0].1 != " " }
        let shown = result.indices.filter { index in changed.contains { abs($0 - index) <= 2 } }
        return shown.prefix(120).map { Line(id: $0, text: result[$0].0, sign: result[$0].1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                Text("\(String(line.sign)) \(line.text)")
                    .font(.geistMono(11))
                    .foregroundStyle(line.sign == "+" ? Palette.good : line.sign == "-" ? Palette.critical : Forge.dim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.sign == "+" ? Palette.good.opacity(0.08) : line.sign == "-" ? Palette.critical.opacity(0.08) : .clear)
            }
        }
        .padding(6)
    }
}

private struct DevComposer: View {
    @Environment(DevSession.self) private var dev
    @FocusState private var focused: Bool

    private var canSend: Bool { dev.canSend && !dev.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canCompare: Bool { dev.canCompare && !dev.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        @Bindable var dev = dev
        VStack(alignment: .leading, spacing: 5) {
            if let reason = dev.blockedReason {
                Text(reason).font(.uiCaption2).foregroundStyle(Palette.warning)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(dev.isWorking ? "The agent is working…" : dev.harnessOn ? "Tell the agent what to do" : "Ask the model (harness off)", text: $dev.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.uiCallout)
                    .lineLimit(1...7)
                    .focused($focused)
                    .onSubmit { dev.send() }
                    .padding(.vertical, 4)
                if dev.isWorking {
                    Button(action: dev.stopAgent) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.primary.opacity(0.85)))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    }
                    .buttonStyle(.plain)
                    .help("Stop the agent. Nothing it was working on gets saved.")
                } else {
                    Button {
                        withAnimation(Motion.quick) { dev.compare() }
                    } label: {
                        Image(systemName: "square.split.2x1")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(canCompare ? 0.1 : 0.04)))
                            .foregroundStyle(canCompare ? Forge.ink : Forge.faint)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCompare)
                    .help("Compare: build this twice in new folders, with the harness off and on, and score both")
                    Button {
                        dev.send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(canSend ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(.quaternary)))
                            .foregroundStyle(Palette.onAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send (↩)")
                }
            }
        }
        .padding(10)
        .onAppear { focused = true }
    }
}

/// Turns Dev mode on, from the chat's row of controls.
struct DevPill: View {
    @Environment(DevSession.self) private var dev
    var compact = false

    var body: some View {
        Button {
            withAnimation(Motion.quick) { dev.isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                if !compact { Text("Dev") }
            }
            .font(.uiCallout.weight(dev.isOn ? .semibold : .regular))
            .foregroundStyle(dev.isOn ? Palette.accent : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .help("Dev mode: open a project folder and build it with the agent")
        .accessibilityLabel("Dev mode")
    }
}

/// Picks how the agent's requests are handled: off, or one of the harness's versions. Off, the model gets one
/// go at a request and its reply is saved as it came, which is what the harness is measured against.
private struct DevHarnessSwitch: View {
    @Environment(DevSession.self) private var dev

    var body: some View {
        HStack(spacing: 4) {
            Text("Harness").font(.uiCaption2).foregroundStyle(Forge.faint)
            HStack(spacing: 0) {
                segment("Off", version: nil)
                ForEach(DevHarnessVersion.allCases) { segment($0.short, version: $0) }
            }
            .padding(2)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Forge.line, lineWidth: 1))
        }
        .disabled(dev.isWorking || dev.isComparing)
        .help(dev.harnessOn ? "Harness \(dev.harnessVersion.title): the agent \(dev.harnessVersion.summary). Click Off to see what the model does alone."
                            : "Harness off: one reply from the model, saved as it came, with nothing run or checked.")
    }

    private func segment(_ title: String, version: DevHarnessVersion?) -> some View {
        let selected = version == nil ? !dev.harnessOn : dev.harnessOn && dev.harnessVersion == version
        let on = version != nil
        return Button {
            withAnimation(Motion.quick) {
                dev.harnessOn = on
                if let version { dev.harnessVersion = version }
            }
        } label: {
            Text(title)
                .font(.uiCaption2.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? (on ? Palette.onAccent : Forge.ink) : Forge.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(selected ? (on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.white.opacity(0.16))) : AnyShapeStyle(Color.clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(version.map { "\($0.title): \($0.summary)" } ?? "One reply from the model, with nothing run or checked")
        .accessibilityLabel("Harness \(version?.title ?? "off")")
    }
}

