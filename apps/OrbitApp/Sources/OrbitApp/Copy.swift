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
    /// Home, top to bottom, per prototype/home-search-mockup.html: a kicker, the
    /// one search field with its teaching hint, the mic as the room's single
    /// large object, then Today, then a footer row.
    static func homeKicker(_ date: String) -> String { "Orbit · \(date)" }
    static let searchHint = "A name, a company, or a half-memory — same box."
    static let captureHint = "Hold nothing back — you'll review everything."
    static let todaySection = "Today"
    static let settingsLink = "settings"
    static func openBrief(_ name: String) -> String { "open \(name)'s brief ›" }
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
    /// Entity LINK cards are plumbing, not claims about a person — one section
    /// for all of them, so five places cost one "all yes" instead of five
    /// headers (§7.10 still requires each to be reviewed; it never required
    /// each to be its own screenful).
    static let contextGroupTitle = "Places, schools, and topics"
    /// The `kind` the extractor already assigned, said plainly.
    static func entityKindLine(_ kind: String, partOf: String?) -> String {
        let readable = kind.replacingOccurrences(of: "_", with: " ")
        guard let partOf else { return readable }
        return "\(readable) · part of \(partOf)"
    }
    /// Inline correction: transcription mishears names, and a voice note never
    /// contains the full formal name of anything. This is the only door the real
    /// name can come through.
    static let renameTitle = "What should this be called?"
    static let renameHint = "Fixing it here fixes it everywhere in this review. The way you said it is kept, so saying it that way again still finds this."
    static let renameSave = "Use this name"
    static let renameTapHint = "Tap the name to correct it"

    /// A card can depend on another (an assertion about Pittsburgh needs the
    /// Pittsburgh card). Accepting it early queues it — correct, and invisible,
    /// so the tap read as broken. The retry is automatic; this just says so.
    static let cardWaitingOnDependency = "Waiting on the place or person this mentions — say yes to that card and this saves itself."
    static let cardCouldNotSave = "That didn't save, and nothing was written. Worth trying again."

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
    /// The roster: an index, not a ranking (P6). No count in the header — a
    /// number over a list of people is a score with extra steps.
    static let rosterTitle = "Everyone you've saved"
    static let rosterEmpty = "Nobody yet. The mic is the way in."
    /// §7.3 in a roster row: said in words, never a badge (D-2).
    static let knownOfShort = "known through others"

    /// Retiring: the whole removal story. Nothing is destroyed, so the copy
    /// says so plainly rather than borrowing the weight of a delete.
    static let removePersonAction = "Remove this person"
    static func removePersonTitle(_ name: String) -> String { "Remove \(name)?" }
    static let retirePersonAction = "Stop showing them"
    static let retirePersonHint = "They leave your list and your searches. Everything you recorded about them stays exactly where it is, and you can bring them back whenever you like."

    /// Handles are typed, not spoken (ORBIT.md §Contact Points): they span
    /// platforms and a transcriber mangles them.
    static let addContactAction = "Add a way to reach them"
    static let addContactTitle = "How do you reach them?"
    static let addContactHint = "Typed by hand, so this one is taken as read \u{2014} no unverified mark."
    static let addContactSave = "Keep it"
    static func contactKindLabel(_ kind: String) -> String {
        switch kind {
        case "phone": return "Phone"
        case "email": return "Email"
        case "instagram": return "Instagram"
        case "linkedin": return "LinkedIn"
        case "x": return "X"
        case "website": return "Website"
        default: return "Other"
        }
    }
    static let reachEmpty = "No way to reach them saved yet."

    /// A date is only as sharp as the sentence it came from. `date_precision`
    /// has been in the ledger since M0 and was rendered nowhere, so a day the
    /// extractor inferred from "a couple of weeks ago" read exactly like a day
    /// someone actually stated (P4 — stored uncertainty must stay visible).
    static func whenLine(_ display: String, precision: String, era: String?) -> String {
        let hedge: String
        switch precision {
        case "exact": hedge = display
        case "month", "year": hedge = "\(display) — no exact day was said"
        default: hedge = "around \(display) — worked out, not stated"
        }
        guard let era, !era.isEmpty else { return hedge }
        return "\(era) · \(hedge)"
    }
    static let editWhenLabel = "When (YYYY, YYYY-MM, or YYYY-MM-DD)"
    static let editWhenHint = "Say only as much as you know — a year or a month is a real answer, and Orbit will stop showing a day you never gave it."

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
    static let portraitPaused = "Paused — take your time."
    static let portraitDone = "That's the portrait"
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
    static let settingsHint = "One extraction endpoint. The key stays in this phone's keychain."
    static let openAIKeyLabel = "OpenAI key"
    static let saveKeys = "Save"
    static let keySaved = "Saved to the keychain"

    /// FN-5: whether the full-model listener is actually here was inferable only
    /// from a stalled-download notice that needs three failures to appear. State
    /// you can only infer is state you cannot check.
    static let modelSectionTitle = "The listener"
    static let modelPresent = "The full model is on this phone. Recordings are deleted once it has heard them."
    /// The model landing is not the end of the story: memos transcribed by the
    /// floor still hold their audio until the re-listen pass reaches them, and
    /// saying "nothing is waiting" while recordings sit there is the exact
    /// inference FN-5 exists to remove.
    static func modelPresentCatchingUp(_ retained: Int) -> String {
        let kept = retained == 1 ? "1 recording is" : "\(retained) recordings are"
        return "The full model is on this phone. \(kept) still waiting to be re-heard, "
            + "and deleted once that's done."
    }
    static func modelAbsent(_ retained: Int, failures: Int) -> String {
        let kept = retained == 1 ? "1 recording is being kept"
                                 : "\(retained) recordings are being kept"
        let why = failures == 0
            ? "It downloads quietly in the background."
            : (failures == 1 ? "One attempt has failed so far."
                             : "\(failures) attempts have failed so far.")
        return "Still downloading the full model, so \(kept) until it can hear them. \(why)"
    }
    static let modelAbsentNothingKept = "The full model isn't here yet. Nothing is waiting on it."

    // Resume doors (J-11) — plain lines, never badges
    static func waitingFooter(_ n: Int) -> String {
        n == 1 ? "1 memo waiting · tap to pick it up"
               : "\(n) memos waiting · tap to pick one up"
    }
    // Work in flight. Between the mic and the review the app used to look idle
    // while it was busy — these say which of the two slow steps is running.
    static let workingTranscribing = "Turning this into words."
    static let workingExtracting = "Reading it back for names, facts, and threads."
    static let workingHint = "This can take a moment. You can leave it running."
    static let collapseWork = "Leave it running"

    // A capture can structure to nothing: every claim in it was already turned
    // down for this same memo (INV-7 suppresses *rejected* claims, not accepted
    // ones), or there was nothing in it to structure. Either way there is no
    // review to hold, and an empty review screen is not an answer (D-8).
    static let nothingNewInCapture = "Nothing new in that one — you'd already said no to everything it turned up."
    static let nothingToStructure = "Nothing to file from that one. The memo is kept as it is."

    // The waiting list (long-press the footer): the exit for a memo that can't
    // be picked up. Plain lines, no counts dressed as badges (D-2/D-9).
    static let waitingListTitle = "Memos waiting"
    static let waitingListHint = "Tap one to pick it up, or let it go if it's no use."
    static let letGo = "Let it go"
    static let waitingStageNeedsTranscription = "Not yet turned into words"
    static let waitingStageNeedsReview = "Words ready to read over"
    static let waitingStageNeedsSync = "Read over — not yet structured"
    static let waitingStageNeedsProposalReview = "Structured — waiting on your yes or no"
    static let memoDiscardFailed = "That one couldn't be let go — it's already further along than it looked."

    // Correcting something already saved (FN-13/FN-15). Until these existed,
    // review was the only moment anything could be fixed: say yes and the fact
    // was frozen, with re-recording the only way back.
    static let deskRenameTitle = "What should this person be called?"
    static let deskRenameHint = "This changes the name everywhere. Nothing else about them moves."
    static let factFixAction = "Fix this"
    static let factFixTitle = "What should this say?"
    static let factFixHint = "Your words stay exactly as you said them — this corrects what Orbit filed under them."
    static let saveCorrection = "Save the correction"
    static let correctionSaved = "Corrected"

    static let keepNote = "Keep this"
    static let micUnavailable = "The mic isn't available right now — the note field below still works."
    static let micDenied = "Orbit needs microphone access: Settings › Orbit › Microphone. The note field below still works."

    // Transcription notices — the recording is always safe; every line says so
    static let transcriptionUnavailable = "Nothing on this phone can turn that into words yet. The recording is safe and waiting."
    static let speechDenied = "Orbit needs speech recognition: Settings › Orbit › Speech Recognition. The recording is safe and waiting."
    static let transcriptionOffDeviceRefused = "This phone can't transcribe without sending the audio away, so Orbit stopped. The recording is safe and stays here."
    static let memoAudioMissing = "That recording is no longer on this phone, so there's nothing left to transcribe."
    /// FN-5: said only once the download is clearly stuck AND recordings are
    /// actually piling up behind it — never as a progress report.
    static let modelDownloadStalled = "The better listener hasn't finished downloading, so your recordings are being kept until it can hear them. Wi-Fi and free space are the usual reasons."
    static let transcriptionNoSpeech = "That recording came out silent, so there are no words to find in it. Nothing else went wrong."
    /// No "yet", no "waiting" — this one will never succeed, and a line that
    /// implies otherwise sends him back to tap it again tomorrow.
    static let transcriptionAudioUnreadable = "That recording didn't save properly — the file has nothing readable in it. Nothing can be recovered from this one."
    /// The reason travels with the failure — a named error can be looked up; a
    /// generic line sends the user (and us) guessing.
    static func transcriptionFailed(_ detail: String) -> String {
        "Transcription stopped — \(detail). The recording is safe and waiting."
    }

    // Edit sheet (P5: accept with edits; the quote itself is untouchable)
    static let editValueLabel = "The mapped value"
    static let editSinceLabel = "Since (YYYY-MM or YYYY-MM-DD)"
    static let editOrbitLabel = "Orbit (inner · close · active · extended · outer)"
    static let saveEdited = "Save with edits"

    // Known-of framing (§7.3): known through others, never met
    static let knownOfBanner = "Known through others — not yet met in person."

    // Store failure — visible, plain, nothing pretends to work
    static let storeFailureTitle = "Orbit couldn't open its memory."
    static let storeFailureBody = "Nothing is being saved right now. Restarting usually clears this; if it persists, the database file needs attention before anything else happens."

    // Errors speak plain sans ink — no red exists (D-1/§9)
    static let extractionFailed = "Couldn't structure this one yet. The memo is safe — try again when you're back online."
    static let transcriptionFallback = "Quick model for now — the full one will re-listen before the recording is deleted."

    /// The full catalog, for D-11 tests (design_lint.py covers source scanning;
    /// this lets the hosted test suite grade the same law without file access).
    /// Closures are sampled with representative arguments.
    static let allStrings: [String] =
        searchPlaceholders + rejectionReasons + [
            todayEmpty, setAsideFooter(3), captureIdle, captureRecording,
            homeKicker("Saturday, July 25"), searchHint, captureHint,
            todaySection, settingsLink, openBrief("Sarah"),
            typedNotePlaceholder, transcriptTitle, transcriptHint,
            audioDeletionNotice, audioRetainedNotice, confirmTranscript, reRecord,
            reviewTitle, contextGroupTitle, entityKindLine("school", partOf: nil),
            renameTitle, renameHint, renameSave, renameTapHint,
            cardWaitingOnDependency, cardCouldNotSave,
            entityKindLine("place", partOf: "New York"),
            yes, no, later, editAction, saved, skipped, setAside,
            doneForNow, notNow, rejectionReasonPrompt,
            walkMeIn, heroTag, openTag, oweTag, owedToYouTag, sinceTag("her"),
            worthHavingBack, timeline, reach("him"), goBePresent, deckEndTag,
            toldYou("Sana"), notYetConfirmed("Sana"), unverifiedContact,
            addContactAction, addContactTitle, addContactHint, addContactSave,
            rosterTitle, rosterEmpty, knownOfShort,
            removePersonAction, removePersonTitle("Sana"), retirePersonAction,
            retirePersonHint,
            contactKindLabel("instagram"), reachEmpty,
            extractionFailed, transcriptionFallback,
            portraitTitle, portraitHint, skipPrompt, firstMetAction, firstMetSet,
            portraitPaused, portraitDone,
            stateCardTag, suggestedPrefix, onboardingNamePrompt, onboardingBegin,
            onboardingPortraitInvite,
            settingsTitle, settingsHint, openAIKeyLabel,
            modelSectionTitle, modelPresent, modelPresentCatchingUp(1),
            modelPresentCatchingUp(3), modelAbsent(3, failures: 2),
            modelAbsentNothingKept,
            saveKeys, keySaved,
            waitingFooter(1), waitingFooter(3), keepNote, micUnavailable, micDenied,
            waitingListTitle, waitingListHint, letGo, waitingStageNeedsTranscription,
            waitingStageNeedsReview, waitingStageNeedsSync,
            waitingStageNeedsProposalReview, memoDiscardFailed,
            workingTranscribing, workingExtracting, workingHint, collapseWork,
            nothingNewInCapture, nothingToStructure,
            transcriptionUnavailable, speechDenied, transcriptionOffDeviceRefused,
            memoAudioMissing, modelDownloadStalled,
            deskRenameTitle, deskRenameHint, factFixAction, factFixTitle,
            factFixHint, saveCorrection, correctionSaved, transcriptionNoSpeech, transcriptionAudioUnreadable,
            transcriptionFailed("kAFAssistantErrorDomain 1700"),
            editValueLabel, editSinceLabel, editOrbitLabel, saveEdited,
            knownOfBanner, storeFailureTitle, storeFailureBody,
        ] + portraitPrompts
}
