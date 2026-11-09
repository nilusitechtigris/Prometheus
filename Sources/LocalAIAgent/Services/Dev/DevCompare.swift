import Foundation

/// One line of a scorecard. Nil when the line doesn't apply, such as using a page with nothing to use.
struct DevScoreLine: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var passed: Bool?
    var detail: String?
    var id: String { name }
}

struct DevCompareFile: Codable, Equatable, Sendable {
    var path: String
    var lines: Int
}

/// One way of building it: the harness off or on.
struct DevCompareSide: Codable, Equatable, Sendable {
    var folder: String
    var harness: Bool
    var seconds: Double?
    var calls: Int?
    var files: [DevCompareFile] = []
    var page: String?
    var score: [DevScoreLine] = []
    /// What the agent or the one reply said at the end.
    var text = ""
    var finished = false
    var stopped = false

    var passed: Int { score.filter { $0.passed == true }.count }
    var total: Int { score.filter { $0.passed != nil }.count }
    var picture: String { (folder as NSString).deletingLastPathComponent + "/\(harness ? "harness-on" : "harness-off").png" }
}

/// The same request built twice on the same model, with the harness off and on, in folders of their own.
struct DevComparison: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var request: String
    var date = Date()
    var model: String
    var framework: String
    var context: Int
    var folder: String
    var off: DevCompareSide
    var on: DevCompareSide
}

enum DevCompare {
    /// Where new projects and comparisons go unless someone picks another place.
    static var projectsRoot: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return documents.appendingPathComponent("Prometheus Projects", isDirectory: true)
    }

    static var comparisonsRoot: URL { projectsRoot.appendingPathComponent("Comparisons", isDirectory: true) }

    static func folderName(for request: String, date: Date) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HHmm"
        let words = request.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { !["a", "an", "the", "me", "make", "create", "build", "write", "please", "with", "for", "and", "that", "of"].contains($0) }
        let name = words.prefix(5).joined(separator: "-")
        return "\(format.string(from: date)) \(name.isEmpty ? "app" : name)"
    }

    // MARK: - Saving

    private static var file: URL {
        ConversationStore.directory.appendingPathComponent("Dev", isDirectory: true).appendingPathComponent("comparisons.json")
    }

    static func load() -> [DevComparison] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([DevComparison].self, from: data) else {
            ConversationStore.setAside(file)
            return []
        }
        return list
    }

    static func save(_ list: [DevComparison]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Array(list.prefix(100))) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Running

    /// Loads the model before the clock starts, so the side that goes first doesn't pay for it.
    static func warmUp(_ setup: DevSetup) async {
        let request = ChatRequest(model: setup.model, messages: [ChatTurn(role: "user", content: "Reply with OK.")], temperature: 0,
                                  contextLength: setup.context, maxTokens: 4, think: setup.think)
        do {
            for try await _ in setup.backend.chat(request) { if Task.isCancelled { break } }
        } catch {}
    }

    // MARK: - Grading

    /// Scores what a folder holds with the same checks for both sides, whatever either one claimed.
    /// A page is opened, played and used out of sight. A program is run with sample input.
    @MainActor
    static func grade(folder: URL, request: String, picture: URL?) async -> (page: String?, files: [DevCompareFile], score: [DevScoreLine]) {
        let project = DevProject(root: folder)
        let entries = project.entries().filter { !$0.isFolder }
        let files = entries.map { entry in
            DevCompareFile(path: entry.path, lines: project.read(entry.path).map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0)
        }
        let pages = entries.filter(\.isPage).map(\.path)
        if let page = pages.first(where: { $0 == "index.html" }) ?? pages.first {
            let kind: DevPageKind = DevAgent.isGame(request) ? .game : .app
            let report = await DevPageCheck.run(folder: folder, page: page, kind: kind, picture: picture)
            var score = [
                DevScoreLine(name: "Shows something", passed: report.hasContent && !report.rawTemplate,
                             detail: report.rawTemplate ? "It shows template tags that only a server fills in." : report.hasContent ? nil : "The page is blank."),
                DevScoreLine(name: "Opens without errors", passed: report.loaded, detail: report.loaded ? nil : report.failure?.title),
                DevScoreLine(name: "Styled", passed: report.styled, detail: report.styled ? nil : "It shows in the browser's plain default look."),
                DevScoreLine(name: "Works offline", passed: report.offline, detail: report.offline ? nil : "It asks the internet for something, which isn't there."),
            ]
            if kind == .game {
                score.append(DevScoreLine(name: "Plays", passed: report.loaded ? (report.moved || report.responded) && report.listens : false))
            } else if report.controls > 0 {
                let works = report.used ?? (report.loaded ? report.responded : false)
                score.append(DevScoreLine(name: "Works when used", passed: works, detail: works ? nil : report.failure?.kind == "Output" ? report.failure?.message : "Filling it in and pressing its buttons changed nothing."))
            } else {
                score.append(DevScoreLine(name: "Works when used", passed: nil, detail: "It has nothing to use."))
            }
            score.append(DevScoreLine(name: "Fits the window", passed: report.fits, detail: report.fits ? nil : "Something on it is wider than the window."))
            return (page, files, score)
        }
        let programs = entries.filter(\.isPython).map(\.path).filter { !$0.hasPrefix("test_") }
        if let program = programs.first(where: { $0 == "main.py" }) ?? programs.first, let text = project.read(program) {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-compare-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.copyItem(at: folder, to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }
            let result = await DevRunner.run([program], in: copy, input: DevAgent.sampleInput(for: text))
            let failure = result.succeeded ? nil : DevFailure.parse(result.output)
            let ranOut = failure?.kind == "EOFError"
            return (nil, files, [
                DevScoreLine(name: "Runs without errors", passed: result.succeeded || ranOut, detail: result.succeeded || ranOut ? nil : (failure?.title ?? result.limit ?? "exit code \(result.exitCode)")),
                DevScoreLine(name: "Shows something", passed: !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ])
        }
        return (nil, files, [DevScoreLine(name: "Wrote a page or a program", passed: false)])
    }
}

/// A request made for testing the harness, from docs/dev-mode-test-prompts.md, which explains each one.
struct DevPrompt: Identifiable, Sendable {
    var group: String
    var title: String
    var text: String
    var id: String { title }
}

extension DevCompare {
    /// The same prompts as docs/dev-mode-test-prompts.md, so they're a click away on the Compare page.
    static let prompts: [DevPrompt] = [
        DevPrompt(group: "Demo", title: "Smoothie bar (the main test)", text: "Build a smoothie bar ordering web app called Juicy, with a bright, colourful look and lively animations.\n\nLayout: a header with a colourful gradient, the app's name, and a cart button showing how many drinks are in the cart. Under it, filter buttons for All, Fruity, Green and Protein, and a Surprise me button. Below them, two columns: a grid of drink cards on the left, and the cart with the order form on the right.\n\nDrinks: six cards, each in its own colour: Mango Sunrise (orange, Fruity, $5.50), Berry Blast (purple, Fruity, $6.00), Tropical Kiss (pink, Fruity, $6.50), Green Machine (green, Green, $6.00), Matcha Glow (teal, Green, $6.50) and Peanut Power (brown, Protein, $7.00). Each card shows a big emoji, the name, a one-line description, the price, a choice of Small, Medium or Large with Medium chosen to start with (Small is $1 less, Large $1 more), and an Add button. Surprise me picks a random drink, highlights its card and adds it to the cart.\n\nCart: each line shows the drink in its colour, its size, the quantity with minus and plus buttons, the line price and a remove button. Below the lines, show the subtotal, 10% off once the subtotal reaches $20, and the total. When the cart is empty, show a friendly message instead.\n\nOrder form: a name field, a pickup time (As soon as possible, In 15 minutes or In 30 minutes) and a Place order button. Don't place an order with an empty cart or an empty name, and say why next to the field. Placing an order empties the cart, shows a thank-you message with an order number, and adds the order to a Recent orders list, newest first.\n\nBehaviour: the filters, the cart and the totals update straight away, and the cart and the recent orders are still there after a reload.\n\nMotion: cards rise and fade into place when the page opens and when the filter changes; a card lifts with a deeper shadow on hover; the cart count pops when a drink is added; the total counts up to its new value; the highlighted card pulses; and a placed order sets off a burst of confetti in a fixed layer that covers the window, hides anything outside it and is removed when the burst ends. Keep each animation under a second, and only fade when the system asks for reduced motion.\n\nLook: rounded cards with soft shadows, each drink's colour on its card and its cart line, white text on strong colours, one font, clear labels on every field, and a layout that stacks into one column in a narrow window."),
        DevPrompt(group: "Demo", title: "Budget dashboard (calmer)", text: "Build a personal budget web app with a clean, modern dashboard look.\n\nLayout: a header with the app's name and the current month. Under it, three summary cards side by side for Balance, Income and Spending, each with a big number. Below them, two columns: a card on the left with a form to add a transaction, and the list of transactions on the right.\n\nForm: a description, an amount, a category (Food, Transport, Home, Fun or Other) and a choice of Income or Spending, with Spending chosen to start with, and an Add button. Don't add a transaction with an empty description or an amount of zero, and say why next to the field.\n\nList: newest first. Each row shows the description, the category as a coloured badge, the date, and the amount in green for income or red for spending, with a delete button. Above the list, buttons show All, Income or Spending. When the list is empty, show a friendly message instead.\n\nBehaviour: the cards and the list update straight away, and everything is still there after a reload.\n\nLook: plenty of white space, rounded cards with soft shadows, one accent colour, clear labels on every field, and a layout that stacks into one column in a narrow window."),
        DevPrompt(group: "Quick", title: "Habit tracker", text: "Make a habit tracker web app. I type a habit and add it, and each habit shows as a row with a checkbox for today, a streak count and a delete button. Show how many habits are done today at the top."),
        DevPrompt(group: "Quick", title: "Tip calculator", text: "Make a tip calculator web app with the bill amount, a tip of 10, 15 or 20 percent or a custom percent, and the number of people. Show the tip, the total and what each person pays, updating as I type."),
        DevPrompt(group: "Quick", title: "Quiz", text: "Make a quiz web app with five multiple choice questions about space. Show one question at a time with four answer buttons, tell me whether I was right, and show my score at the end with a button to play again."),
        DevPrompt(group: "Quick", title: "Recipe box", text: "Make a recipe box web app. A form takes a recipe's name, its ingredients and the minutes it takes. Show the recipes as cards, and add a search box that filters them by name as I type."),
        DevPrompt(group: "Quick", title: "Pomodoro timer", text: "Make a pomodoro timer web app with a 25 minute work timer and a 5 minute break, big digits, start, pause and reset buttons, and a count of the work sessions finished today."),
        DevPrompt(group: "Quick", title: "Kanban board", text: "Make a kanban board web app with To do, Doing and Done columns. I add a card to To do, and each card has buttons to move it left or right and to delete it. Show how many cards each column has."),
        DevPrompt(group: "Traps", title: "Sales chart (trap)", text: "Make a sales dashboard web app that shows these monthly sales as a bar chart: Jan 120, Feb 95, Mar 140, Apr 180, May 160, Jun 210. Add cards for the total, the best month and the monthly average."),
        DevPrompt(group: "Traps", title: "Guestbook (trap)", text: "Make a guestbook web app where visitors leave their name and a message, and everyone's messages show newest first."),
        DevPrompt(group: "Traps", title: "Coffee shop page (trap)", text: "Make a landing page for a coffee shop called Ember Roast, with a menu and prices, the opening hours, a contact form that thanks the visitor, and an icon for each section."),
    ]
}
