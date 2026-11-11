import Foundation

/// How much the agent asks of the model in one go: how long a reply may run, how long a file is asked to stay,
/// and how much a plan may list.
struct DevBudget: Equatable, Sendable {
    /// The most tokens one reply may run to, when a step doesn't set its own.
    var reply: Int
    /// The lines the page's markup is asked to stay under.
    var pageLines: Int
    /// The lines the app's own style sheet is asked to stay under.
    var styleLines: Int
    /// The most actions and parts a plan may list.
    var planActions: Int
    var planParts: Int
    /// The tokens the plan's reply may take, and the characters kept of each of its lines.
    var planReply: Int
    var planLine: Int

    /// The most the plain model's one reply may run to, with the harness off. It holds a whole app, so it
    /// gets the room of two files.
    var oneReply: Int { max(8_192, reply * 2) }

    /// What v1 and v2 work to, at any context window: one reply of 4,096 tokens, a page under 90 lines and a
    /// style sheet under 40. The plan's numbers are v2's. v1 has smaller ones of its own, in `planApp`.
    static let small = DevBudget(reply: 4_096, pageLines: 90, styleLines: 40, planActions: 10, planParts: 8, planReply: 600, planLine: 600)

    /// v3's, which follows the context window. Up to 8K it is `small`, so there v3 asks what v2 asks. From
    /// 16K a reply and the files may be larger, and from 32K larger again. A reply is still cut to what the
    /// window has left once the request is in it (`DevAgent.complete`).
    static func roomy(context: Int) -> DevBudget {
        switch context {
        case ..<12_000:
            return small
        case ..<24_000:
            return DevBudget(reply: 6_144, pageLines: 160, styleLines: 90, planActions: 14, planParts: 10, planReply: 800, planLine: 900)
        default:
            return DevBudget(reply: 12_288, pageLines: 260, styleLines: 160, planActions: 18, planParts: 12, planReply: 1_000, planLine: 1_200)
        }
    }

    /// The budget a version works to at a context window.
    static func of(_ version: DevHarnessVersion, context: Int) -> DevBudget {
        version == .v3 ? roomy(context: context) : small
    }
}

/// Dev harness v3. It is v2 with room that follows the context window.
///
/// v1 and v2 write each file of an app in one reply of at most 4,096 tokens, and ask for a page under 90
/// lines and a style sheet under 40, whatever the context window is. That suits a small window and a small
/// app. With 32K to work in, an app with several pages still had to fit the same reply: the reply was cut
/// off, the model was asked for "a much shorter version", and parts of the request were lost. A larger
/// window bought nothing.
///
/// v3 keeps every step of v2 and changes only the sizes, by `DevBudget.roomy`:
/// - a reply may run longer from 16K, and longer again from 32K;
/// - the page and the style sheet are asked to stay under more lines;
/// - the plan may list more actions and parts, and more of each of its lines is kept.
///
/// Up to 8K the sizes are v2's, so there the two ask the model the same things. The sizes are ceilings, not
/// targets: a small app is still asked for as a small app.
///
/// With v3 chosen, the harness-off side gets the same room. Its one reply holds the whole app, so its cap
/// rises too (`DevBudget.oneReply`). Otherwise a comparison would measure the cap, not the harness.
///
/// Nothing here changes v1 or v2: their sizes are `DevBudget.small`, the numbers they always had.
extension DevAgent {
    var isV3: Bool { setup.version == .v3 }

    var budget: DevBudget { DevBudget.of(setup.version, context: setup.context) }

    /// v2's plan, with as many actions and parts as the budget allows. With the small budget it is v2's
    /// request word for word.
    func planAppV3(_ job: DevJob, data: [String]) async -> AppPlan {
        let budget = budget
        let system = """
        You plan small web apps that run as one page in a browser, offline. Reply in exactly this form and nothing else:
        NAME: the app's name, 1 to 4 words
        ACTIONS: everything the user can do, separated by ;
        PARTS: the parts of the page, top to bottom, separated by ;
        DATA: what the app keeps track of, and the fields of each thing
        Cover everything the request asks for and add nothing it doesn't: 3 to \(budget.planActions) actions and 3 to \(budget.planParts) parts, a few words each.
        """
        let reply = await complete(system: system, user: (data + ["App: \(job.request)"]).joined(separator: "\n\n"), temperature: 0.2, limit: budget.planReply)
        return AppPlan.parse(reply.text, limit: budget.planLine)
    }
}
