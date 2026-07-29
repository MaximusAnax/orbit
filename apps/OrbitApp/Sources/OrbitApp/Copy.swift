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
    static func setAsideFooter(_ n: Int) -> String { "\(n) set aside · whenever you want them" }

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
    static func sinceTag(_ pronoun: String) -> String { "Since you last saw \(pronoun)" }
    static let worthHavingBack = "Worth having back"
    static let timeline = "Timeline"
    static func reach(_ pronoun: String) -> String { "Reach \(pronoun)" }
    static let goBePresent = "Go be present."   // serif — the tool's one memory-voice sentence
    static let deckEndTag = "That's everything"

    // Hearsay & uncertainty (§9/§10: attribution explicit, hedges survive)
    static func toldYou(_ name: String) -> String { "\(name) told you this" }
    static func notYetConfirmed(_ name: String) -> String { "\(name) told you this — not yet confirmed firsthand" }
    static let unverifiedContact = "unverified until first used"

    // Portraits (§7.11) — skippable serif prompts, never queued, never bulk
    static let portraitTitle = "Paint a portrait"
    static let portraitHint = "Talk about them like you'd tell a friend. Pause anytime; skip any prompt."
    static let portraitPrompts = [
        "How did you meet?",
        "What's going on in their life right now?",
        "What do you always forget about them?",
        "What's a moment you two shared that stuck with you?",
    ]
    static let skipPrompt = "Skip"
    static let firstMetAction = "This is when we met"
    static let firstMetSet = "Marked as your first meeting"

    // PROPOSE_STATE review (§7.13) — his words, transported; mapping shown as suggestion
    static let stateCardTag = "In your words"
    static let suggestedPrefix = "suggested: "

    // Onboarding (§7.12) — quiet; one name, then the room
    static let onboardingNamePrompt = "What should Orbit call you?"
    static let onboardingBegin = "Begin"
    static let onboardingPortraitInvite = "A few people worth painting first — whenever you like."

    // Settings — the one quiet drawer; keys live in this phone's keychain only
    static let settingsTitle = "Keys"
    static let settingsHint = "One extraction endpoint, chosen by whichever key exists. Keys stay in this phone's keychain."
    static let anthropicKeyLabel = "Anthropic key"
    static let openAIKeyLabel = "OpenAI key"
    static let saveKeys = "Save"
    static let keySaved = "Saved to the keychain"

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
            portraitTitle, portraitHint, skipPrompt, firstMetAction, firstMetSet,
            stateCardTag, suggestedPrefix, onboardingNamePrompt, onboardingBegin,
            onboardingPortraitInvite,
            settingsTitle, settingsHint, anthropicKeyLabel, openAIKeyLabel,
            saveKeys, keySaved,
        ] + portraitPrompts
}
