import Foundation

/// Every user-facing string, in one place — the design is half copy (DESIGN.md §10),
/// and this catalog is what scripts/dev/design_lint.py lints for the forbidden
/// lexicon (D-11: never "remaining", "overdue", "pending review", "streak") and
/// debt language. The ratified lexicon lives here verbatim.
enum Copy {
    // Home — the three doors (ORBIT.md §18)
    static let searchPlaceholders = [
        "Sarah…", "who do I know at Google?", "the guy from Greece at the picnic",
    ]  // one box, three shapes — teaching by rotation
    static let todayEmpty = "Orbit only speaks here when there's a reason."
    static let setAsideFooter = { (n: Int) in "\(n) set aside · whenever you want them" }

    // Capture
    static let captureIdle = "What happened?"
    static let captureRecording = "Listening…"
    static let typedNotePlaceholder = "Or type a small thing worth keeping…"

    // Transcript review — the review that makes audio deletion safe (§7.5)
    static let transcriptTitle = "Here's what I heard"
    static let transcriptHint = "Fix anything — names especially. Once you confirm, the transcript is the record."
    static let audioDeletionNotice = "This deletes the recording — the transcript stays."
    static let audioRetainedNotice = "Kept until the full model has heard it — then the recording is deleted."
    static let confirmTranscript = "Looks right — save this"
    static let reRecord = "Re-record"

    // Proposal review
    static let reviewTitle = "Does this look right?"
    static let yes = "Yes"
    static let no = "No"
    static let later = "Later"
    static let editAction = "Edit"
    static let saved = "Saved"
    static let skipped = "Skipped"
    static let setAside = "Set aside"
    static let doneForNow = "Done for now"
    static let notNow = "Not now"
    static let rejectionReasonPrompt = "Optional — why not?"
    static let rejectionReasons = ["Not true", "Wrong person", "Not worth keeping"]

    // Desk / Deck (ratified lexicon, §10.6)
    static let walkMeIn = "✦ Walk me in · 60-second refresher"
    static let heroTag = "If you remember one thing"
    static let openTag = "Open"
    static let oweTag = "You owe"
    static let owedToYouTag = "Owed to you"
    static let sinceTag = { (pronoun: String) in "Since you last saw \(pronoun)" }
    static let worthHavingBack = "Worth having back"
    static let timeline = "Timeline"
    static let reach = { (pronoun: String) in "Reach \(pronoun)" }
    static let goBePresent = "Go be present."   // serif — the tool's one memory-voice sentence
    static let deckEndTag = "That's everything"

    // Hearsay & uncertainty (§9/§10: attribution explicit, hedges survive)
    static let toldYou = { (name: String) in "\(name) told you this" }
    static let notYetConfirmed = { (name: String) in "\(name) told you this — not yet confirmed firsthand" }
    static let unverifiedContact = "unverified until first used"

    // Errors speak plain sans ink — no red exists (D-1/§9)
    static let extractionFailed = "Couldn't structure this one yet. The memo is safe — try again when you're back online."
    static let transcriptionFallback = "Quick model for now — the full one will re-listen before the recording is deleted."

    /// The full catalog, for D-11 tests (design_lint.py covers source scanning;
    /// this lets the hosted test suite grade the same law without file access).
    /// Closures are sampled with representative arguments.
    static let allStrings: [String] =
        searchPlaceholders + rejectionReasons + [
            todayEmpty, setAsideFooter(3), captureIdle, captureRecording,
            typedNotePlaceholder, transcriptTitle, transcriptHint,
            audioDeletionNotice, audioRetainedNotice, confirmTranscript, reRecord,
            reviewTitle, yes, no, later, editAction, saved, skipped, setAside,
            doneForNow, notNow, rejectionReasonPrompt,
            walkMeIn, heroTag, openTag, oweTag, owedToYouTag, sinceTag("her"),
            worthHavingBack, timeline, reach("him"), goBePresent, deckEndTag,
            toldYou("Sana"), notYetConfirmed("Sana"), unverifiedContact,
            extractionFailed, transcriptionFallback,
        ]
}
