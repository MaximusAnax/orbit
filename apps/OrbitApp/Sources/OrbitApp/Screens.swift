import SwiftUI
import OrbitCore
import OrbitDesign

// Screens are thin renderers over the view models; every color/radius/font
// resolves through Tokens (D-10). Both rooms come free via RoomBackground.

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @State private var searchText = ""
    @State private var showCapture = false
    @State private var showSettings = false
    @State private var showWaitingList = false
    /// Which query shape the search pill is teaching right now (§12).
    @State private var placeholderIndex = 0
    /// Slow enough to read, never animated into a carousel — motion in Orbit is
    /// a cut, not a slide (§8).
    private let placeholderRotation = Timer.publish(every: 4.5, on: .main, in: .common)
        .autoconnect()

    // Structure follows prototype/home-search-mockup.html, top to bottom:
    // kicker, search pill, teaching hint, the mic block, Today, footer row.
    // The mic sits ABOVE Today — it is the room's single large object and the
    // screen's centre of gravity, not something parked under a Spacer.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // `.kick` is uppercase and letter-spaced in the mockup; 11pt
                // rather than its 10 because §11.1 sets that as the floor.
                Text(Copy.homeKicker(app.todayDateLine).uppercased())
                    .interfaceVoice(size: 11, weight: .semibold)
                    .kerning(1.3)
                    .foregroundStyle(Tokens.inkFaint(room))
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("home.kicker")

                // Door 2: one field, three query shapes — no submit affordance exists (J-8)
                NavigationLink {
                    SearchView(initialQuery: searchText)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.inkFaint(room))
                        // DESIGN §12: the placeholder ROTATES through the three real
                        // query shapes — a name, a question, a fragment. The rotation
                        // is the teaching ("one box, three shapes"); a fixed string
                        // teaches only the first of them.
                        Text(Copy.searchPlaceholders[placeholderIndex])
                            .interfaceVoice(size: 13)
                            .foregroundStyle(Tokens.inkFaint(room))
                            .id(placeholderIndex)
                        Spacer()
                    }
                    .padding(.vertical, 12).padding(.horizontal, 16)
                    .background(Tokens.paper(room))
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPill))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusPill)
                        .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))
                }
                Text(Copy.searchHint)
                    .interfaceVoice(size: 10.5)
                    .foregroundStyle(Tokens.inkFaint(room))
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                // Door 1: the capture mic — the app's one large ember object (§12),
                // ringed in note stock the way the mockup lights it.
                VStack(spacing: 0) {
                    Button {
                        showCapture = true
                    } label: {
                        ZStack {
                            Circle().fill(Tokens.note(room)).frame(width: 112, height: 112)
                            Circle().fill(Tokens.ember(room)).frame(width: 92, height: 92)
                                .overlay(Image(systemName: "mic.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(Tokens.emberInk(room)))
                        }
                        .shadow(color: .black.opacity(0.18), radius: 11, y: 6)
                    }
                    .accessibilityLabel(Copy.captureIdle)
                    .accessibilityIdentifier("home.mic")

                    Text(Copy.captureIdle)
                        .interfaceVoice(size: 13, weight: .semibold)
                        .foregroundStyle(Tokens.ink(room))
                        .padding(.top, 16)
                    Text(Copy.captureHint)
                        .interfaceVoice(size: 11.5)
                        .foregroundStyle(Tokens.inkFaint(room))
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .padding(.bottom, 24)

                // "Today" — at most two reasoned items; collapses entirely when
                // empty (D-8), label included rather than heading nothing.
                if !app.todayItems.isEmpty {
                    SectionTag(Copy.todaySection)
                        .padding(.bottom, 9)
                    VStack(spacing: Tokens.gridGap) {
                        ForEach(app.todayItems) { item in
                            NavigationLink {
                                DeskView(personID: item.personID)
                            } label: {
                                PaperTile {
                                    HStack(alignment: .top, spacing: 11) {
                                        PortraitView(initial: item.initial, size: 38)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.reason).memoryVoice(size: 13.5)
                                                .foregroundStyle(Tokens.ink(room))
                                                .fixedSize(horizontal: false, vertical: true)
                                                .multilineTextAlignment(.leading)
                                            Text(item.sourceLine).interfaceVoice(size: 10.5)
                                                .foregroundStyle(Tokens.inkFaint(room))
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text(Copy.todayEmpty)
                        .interfaceVoice(size: 10.5)
                        .foregroundStyle(Tokens.inkFaint(room))
                        .padding(.horizontal, 6)
                }

                // The footer row: plain underlined text lines, centred, never
                // cards and never badges (D-2/D-9).
                VStack(spacing: 8) {
                    // Waiting memos: the J-11 resume door. Tap resumes the oldest;
                    // long-press opens the list, which is where a memo that can
                    // never be picked up can be let go instead of sitting here.
                    if let memo = app.waitingMemos.first {
                        // FN-15: the list existed behind a long-press and was
                        // proposed back to us as a missing feature the same
                        // evening it shipped — undiscoverable. The copy already
                        // says which case is which ("tap to pick it UP" vs
                        // "pick ONE up"), so the behaviour now matches the
                        // words: one memo resumes, several offer the choice.
                        Button {
                            if app.waitingMemos.count > 1 { showWaitingList = true }
                            else { app.resume(memo) }
                        } label: {
                            FooterLink(Copy.waitingFooter(app.waitingMemos.count))
                        }
                        .accessibilityIdentifier("home.waitingFooter")
                        // simultaneousGesture, not onLongPressGesture: a Button's own
                        // tap handling swallows a plain long-press modifier, which
                        // would leave the list unreachable on device while looking
                        // correct in source.
                        .simultaneousGesture(LongPressGesture().onEnded { _ in showWaitingList = true })
                        // the long-press is invisible, so VoiceOver gets a named action
                        .accessibilityAction(named: Text(Copy.waitingListTitle)) { showWaitingList = true }
                    }

                    // Why the last pick-up didn't get anywhere. Plain ink, no red
                    // (D-1), and it clears the moment something works.
                    if let notice = app.captureNotice {
                        Text(notice)
                            .interfaceVoice(size: 11)
                            .foregroundStyle(Tokens.inkMuted(room))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .accessibilityIdentifier("home.captureNotice")
                    }

                    HStack(spacing: 6) {
                        if app.setAsideCount > 0 {
                            Button { app.reopenSetAsides() } label: {
                                FooterLink(Copy.setAsideFooter(app.setAsideCount))
                            }
                            .accessibilityIdentifier("home.setAsideFooter")
                            Text("·").interfaceVoice(size: 11)
                                .foregroundStyle(Tokens.inkFaint(room))
                        }
                        Button { showSettings = true } label: {
                            FooterLink(Copy.settingsLink)
                        }
                        .accessibilityIdentifier("home.settings")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
            }
            .padding(.top, Tokens.screenPaddingTop)
            .padding(.horizontal, Tokens.screenPaddingSide)
            .padding(.bottom, 34)
        }
        .sheet(isPresented: $showCapture) { CaptureView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showWaitingList) { WaitingListView() }
        // a memo resumed from the footer works with no capture sheet open —
        // without this the tap looked like it did nothing for several seconds
        .fullScreenCover(isPresented: homeWorkingBinding) { WorkingView() }
        .fullScreenCover(item: homeTranscriptBinding) { vm in TranscriptReviewView(vm: vm) }
        .fullScreenCover(item: homeReviewBinding) { vm in ReviewView(vm: vm) }
        .onAppear { app.refreshAmbient() }
        .onReceive(placeholderRotation) { _ in
            placeholderIndex = (placeholderIndex + 1) % Copy.searchPlaceholders.count
        }
    }

    /// Read-only: collapsing is the only way out, and it goes through the model
    /// so the running work is redirected rather than cancelled.
    var homeWorkingBinding: Binding<Bool> {
        Binding(get: { !showCapture && !showWaitingList && app.isWorking }, set: { _ in })
    }

    // resume flows land here when no sheet is open — the waiting list counts,
    // since resuming from it sets pendingCapture while that sheet is still on
    // screen, and a cover racing a dismissing sheet lands on neither.
    var homeTranscriptBinding: Binding<TranscriptReviewViewModel?> {
        Binding(get: {
            guard !showCapture, !showWaitingList,
                  case .reviewingTranscript(let vm) = app.pendingCapture else { return nil }
            return vm
        }, set: { _ in })
    }

    var homeReviewBinding: Binding<ReviewViewModel?> {
        Binding(get: {
            guard !showCapture, !showWaitingList,
                  case .reviewingProposals(let vm) = app.pendingCapture else { return nil }
            return vm
        }, set: { _ in })
    }
}

/// Key entry (§7.9 seam's one visible knob): two secure fields, keychain-only
/// storage, provider chosen by whichever key exists.
/// What's happening between the mic and the review. Transcription and
/// extraction are the only two steps slow enough that the app looked idle while
/// it worked — capture fell back to the idle mic, and a memo resumed from the
/// footer showed nothing at all.
///
/// Collapsible on purpose: the work keeps running and its result lands in the
/// waiting footer, so a slow transcription never holds the screen hostage (P10).
struct WorkingView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room

    var body: some View {
        RoomBackground { _ in
            VStack(spacing: 16) {
                Spacer()
                // ember, the app's one accent — not a per-person progress ring (P6)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Tokens.ember(room))
                    .scaleEffect(1.4)
                Text(app.workingLine)
                    .interfaceVoice(size: 15)
                    .foregroundStyle(Tokens.ink(room))
                    .multilineTextAlignment(.center)
                Text(Copy.workingHint)
                    .interfaceVoice(size: 12)
                    .foregroundStyle(Tokens.inkFaint(room))
                    .multilineTextAlignment(.center)
                Spacer()
                TertiaryButton(Copy.collapseWork) { app.collapseWork() }
                    .accessibilityIdentifier("working.collapse")
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .accessibilityIdentifier("working")
    }
}

/// The waiting list — reached by long-pressing the home footer. Its reason to
/// exist is the memo that can never be picked up: a recording that didn't save
/// leaves an event that fails every resume, and without this it sits in the
/// footer forever. Letting one go is a lifecycle transition, not a row delete
/// (INV-5); the write layer refuses anything past `captured`, so memos that
/// can't be discarded simply don't offer it.
struct WaitingListView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss

    var body: some View {
        RoomBackground { _ in
            VStack(alignment: .leading, spacing: 14) {
                Text(Copy.waitingListTitle).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                    .padding(.top, 28)
                Text(Copy.waitingListHint).interfaceVoice(size: 12)
                    .foregroundStyle(Tokens.inkMuted(room))

                ScrollView {
                    VStack(spacing: Tokens.gridGap) {
                        ForEach(app.waitingMemos) { memo in
                            PaperTile {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(String(memo.capturedAt.prefix(10)))
                                            .interfaceVoice(size: 10.5)
                                            .foregroundStyle(Tokens.inkFaint(room))
                                        Text(Self.stageLine(memo.stage))
                                            .interfaceVoice(size: 13)
                                            .foregroundStyle(Tokens.ink(room))
                                    }
                                    Spacer()
                                    if memo.canDiscard {
                                        TertiaryButton(Copy.letGo) {
                                            app.discard(memo)
                                            if app.waitingMemos.isEmpty { dismiss() }
                                        }
                                        .accessibilityIdentifier("waitingList.letGo")
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismiss()
                                app.resume(memo)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .overlay(alignment: .topTrailing) {
            TertiaryButton(Copy.notNow) { dismiss() }.padding()
        }
        .accessibilityIdentifier("waitingList")
    }

    static func stageLine(_ stage: AppModel.WaitingMemo.Stage) -> String {
        switch stage {
        case .needsTranscription: return Copy.waitingStageNeedsTranscription
        case .needsTranscriptReview: return Copy.waitingStageNeedsReview
        case .needsSync: return Copy.waitingStageNeedsSync
        case .needsProposalReview: return Copy.waitingStageNeedsProposalReview
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss
    @State private var openAIKey = KeychainLite.read("openai-api-key") ?? ""
    @State private var saved = false

    var body: some View {
        RoomBackground { _ in
            VStack(alignment: .leading, spacing: 14) {
                Text(Copy.settingsTitle).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                    .padding(.top, 28)
                Text(Copy.settingsHint).interfaceVoice(size: 12)
                    .foregroundStyle(Tokens.inkMuted(room))

                keyField(Copy.openAIKeyLabel, text: $openAIKey, id: "settings.openAIKey")

                PrimaryButton(Copy.saveKeys) {
                    KeychainLite.write("openai-api-key",
                                       value: openAIKey.trimmingCharacters(in: .whitespaces))
                    saved = true
                }
                if saved {
                    Text(Copy.keySaved).interfaceVoice(size: 11.5)
                        .foregroundStyle(Tokens.inkMuted(room))
                }

                // FN-5: the §7.5 audio-retention gate is invisible otherwise —
                // you cannot tell whether recordings are piling up waiting for a
                // model that never arrived.
                SectionTag(Copy.modelSectionTitle)
                    .padding(.top, 10)
                Text(app.modelStatusLine).interfaceVoice(size: 11.5)
                    .foregroundStyle(Tokens.inkMuted(room))
                    .accessibilityIdentifier("settings.modelStatus")
                Spacer()
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .overlay(alignment: .topTrailing) {
            TertiaryButton(Copy.notNow) { dismiss() }.padding()
        }
    }

    func keyField(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).interfaceVoice(size: 11, weight: .semibold)
                .foregroundStyle(Tokens.inkFaint(room))
            SecureField("", text: text)
                .accessibilityIdentifier(id)
                .font(.system(size: 14))
                .padding(11)
                .background(Tokens.paper(room))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                    .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))
        }
    }
}

struct CaptureView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss
    @State private var typed = ""
    @State private var isRecording = false
    @State private var micFailed = false
    @State private var noteKept = false

    var body: some View {
        RoomBackground { _ in
            VStack(spacing: 20) {
                Text(Copy.captureIdle).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                    .padding(.top, 30)

                Button {
                    if isRecording {
                        isRecording = false
                        Task { await app.endRecording() }
                    } else {
                        // PERF-3 budget: mic tap → recording ≤ 300ms.
                        micFailed = !app.beginRecording()
                        isRecording = !micFailed
                    }
                } label: {
                    Circle().fill(Tokens.ember(room))
                        .frame(width: 110, height: 110)
                        .overlay(Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Tokens.emberInk(room)))
                }
                .accessibilityIdentifier("capture.mic")
                if isRecording {
                    Text(Copy.captureRecording).interfaceVoice(size: 12)
                        .foregroundStyle(Tokens.inkMuted(room))
                }
                if micFailed {
                    // plain ink, never red (D-1); the typed note is right below
                    Text(app.micFailure == .denied ? Copy.micDenied : Copy.micUnavailable)
                        .interfaceVoice(size: 12)
                        .foregroundStyle(Tokens.inkMuted(room))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Typed micro-note: the escape hatch for the seven-word fact (§7.11)
                VStack(alignment: .leading, spacing: 8) {
                    TextField(Copy.typedNotePlaceholder, text: $typed, axis: .vertical)
                        .accessibilityIdentifier("capture.typedNote")
                        .font(.custom(Tokens.serifFamily, size: 14))   // typed text IS the transcript → memory voice
                        .padding(12)
                        .background(Tokens.paper(room))
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                            .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))
                        .onSubmit { keepTypedNote() }
                    if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TertiaryButton(Copy.keepNote) { keepTypedNote() }
                    }
                    if noteKept {
                        Text(Copy.saved).interfaceVoice(size: 11)
                            .foregroundStyle(Tokens.inkFaint(room))
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .presentationDetents([.large])
        .onDisappear {
            if isRecording {
                isRecording = false
                app.cancelRecording()   // an open mic after dismiss is a privacy failure
            }
        }
        .overlay(alignment: .topTrailing) {
            TertiaryButton(Copy.notNow) { dismiss() }.padding()
        }
        // stopping the mic used to drop straight back to the idle capture screen,
        // which read as "nothing happened" while transcription ran
        .fullScreenCover(isPresented: workingBinding) { WorkingView() }
        .fullScreenCover(item: transcriptBinding) { vm in
            TranscriptReviewView(vm: vm)
        }
        .fullScreenCover(item: reviewBinding) { vm in
            ReviewView(vm: vm)
        }
    }

    func keepTypedNote() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try app.captureTypedNote(text: text)   // typed text IS the transcript (J-5)
            typed = ""
            noteKept = true
        } catch {
            // the note text stays right where it is — nothing typed is ever lost
        }
    }

    var workingBinding: Binding<Bool> {
        Binding(get: { app.isWorking }, set: { _ in })
    }

    var transcriptBinding: Binding<TranscriptReviewViewModel?> {
        Binding(get: {
            if case .reviewingTranscript(let vm) = app.pendingCapture { return vm }
            return nil
        }, set: { _ in })
    }

    var reviewBinding: Binding<ReviewViewModel?> {
        Binding(get: {
            if case .reviewingProposals(let vm) = app.pendingCapture { return vm }
            return nil
        }, set: { _ in })
    }
}

struct TranscriptReviewView: View {
    @ObservedObject var vm: TranscriptReviewViewModel
    @Environment(\.room) var room

    var body: some View {
        RoomBackground { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Copy.transcriptTitle).interfaceVoice(size: 20, weight: .bold)
                        .foregroundStyle(Tokens.ink(room))
                    Text(Copy.transcriptHint).interfaceVoice(size: 12)
                        .foregroundStyle(Tokens.inkMuted(room))

                    PaperTile {
                        // transcript body: memory voice (§12)
                        TextEditor(text: $vm.text)
                            .accessibilityIdentifier("transcript.editor")
                            .font(.custom(Tokens.serifFamily, size: 14))
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                    }

                    // name-match pass results: the pre-deletion safety net (§6)
                    ForEach(Array(vm.nameSuggestions.enumerated()), id: \.offset) { _, s in
                        NoteTile(tilted: false) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\u{201C}\(s.heard)\u{201D} — did you mean \(s.candidate)?")
                                        .interfaceVoice(size: 12.5, weight: .semibold)
                                        .foregroundStyle(Tokens.ink(room))
                                }
                                Spacer()
                                SecondaryButton(Copy.yes) { vm.applyFix(s) }
                            }
                        }
                    }

                    // §7.5: informational sticky, not a warning banner
                    NoteTile(tilted: false) {
                        Text(vm.audioNotice).interfaceVoice(size: 12)
                            .foregroundStyle(Tokens.inkMuted(room))
                    }

                    PrimaryButton(Copy.confirmTranscript) { vm.confirm() }
                    HStack {
                        SecondaryButton(Copy.reRecord) { vm.discard() }
                        Spacer()
                        TertiaryButton(Copy.later) { vm.later() }
                    }
                }
                .padding(.top, Tokens.screenPaddingTop)
                .padding(.horizontal, Tokens.screenPaddingSide)
            }
        }
    }
}

struct ReviewView: View {
    @ObservedObject var vm: ReviewViewModel
    @Environment(\.room) var room

    var body: some View {
        RoomBackground { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Copy.reviewTitle).interfaceVoice(size: 20, weight: .bold)
                        .foregroundStyle(Tokens.ink(room))

                    ForEach(vm.visibleGroups) { group in
                        VStack(alignment: .leading, spacing: Tokens.gridGap) {
                            HStack {
                                Text(group.name).memoryVoice(size: 16, weight: .semibold)
                                    .foregroundStyle(Tokens.ink(room))
                                Spacer()
                                if group.cards.count > 1 {
                                    TertiaryButton("all \(Copy.yes.lowercased())") { vm.acceptAll(in: group) }
                                }
                            }
                            ForEach(group.cards) { card in
                                ProposalCardView(vm: vm, card: card)
                            }
                        }
                    }

                    if vm.allSettled {
                        PrimaryButton(Copy.doneForNow) { vm.finish() }
                    } else {
                        TertiaryButton(Copy.later) { vm.finish() }   // J-3: defer everything, 1 tap, no nags after
                    }
                }
                .padding(.top, Tokens.screenPaddingTop)
                .padding(.horizontal, Tokens.screenPaddingSide)
            }
        }
    }
}

/// `sheet(item:)` needs an Identifiable; the ref itself is the identity.
struct RenameTarget: Identifiable {
    let ref: String
    var id: String { ref }
}

/// One field, because there is only one thing to fix. The correction lands on
/// the ref, so every card in the review that mentions it updates at once — which
/// is the whole point: a name misheard once is misheard on every card.
struct RenameSheet: View {
    @ObservedObject var vm: ReviewViewModel
    let ref: String
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""

    var body: some View {
        RoomBackground { _ in
            VStack(alignment: .leading, spacing: 14) {
                Text(Copy.renameTitle).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                    .padding(.top, 28)
                Text(Copy.renameHint).interfaceVoice(size: 12)
                    .foregroundStyle(Tokens.inkMuted(room))

                // a name is his content, not the system's — memory voice (§4.2)
                TextField("", text: $name)
                    .accessibilityIdentifier("rename.field")
                    .font(.custom(Tokens.serifFamily, size: 16))
                    .padding(12)
                    .background(Tokens.paper(room))
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                        .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))

                PrimaryButton(Copy.renameSave) {
                    vm.rename(ref: ref, to: name)
                    dismiss()
                }
                Spacer()
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .overlay(alignment: .topTrailing) {
            TertiaryButton(Copy.notNow) { dismiss() }.padding()
        }
        .onAppear { name = vm.currentName(forRef: ref) }
    }
}

struct ProposalCardView: View {
    @ObservedObject var vm: ReviewViewModel
    let card: ReviewViewModel.Card
    @Environment(\.room) var room
    @State private var editing = false
    @State private var renaming: String?

    var body: some View {
        if let settled = card.settled {
            // settled grey line (ratified interactive behavior)
            HStack {
                Text(settled).interfaceVoice(size: 11)
                    .foregroundStyle(Tokens.inkFaint(room))
                Text(card.quote).interfaceVoice(size: 11)
                    .foregroundStyle(Tokens.inkFaint(room)).lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 4)
        } else if let question = card.question {
            // DISAMBIGUATE ask-card: note material + ember edge — a thing to handle by hand (§9)
            NoteTile(tilted: false) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTag("A question", ember: true)
                    // system speech: the tool asking, not a memory — sans (§4.2)
                    Text(question).interfaceVoice(size: 13, weight: .semibold)
                        .foregroundStyle(Tokens.ink(room))
                    ForEach(card.candidates, id: \.id) { candidate in
                        SecondaryButton(candidate.name) { vm.choose(card, candidate: candidate.id) }
                    }
                    HStack {
                        SecondaryButton("Keep it, leave open") { vm.keepUnresolved(card) }
                        Spacer()
                        TertiaryButton(Copy.later) { vm.setAside(card) }
                    }
                }
            }
        } else {
            PaperTile {
                VStack(alignment: .leading, spacing: 9) {
                    if let teller = card.hearsayTeller {
                        HearsayChip(teller: teller)
                    }
                    if card.op == .proposeState {
                        // §7.13: his words transported — quote authoritative,
                        // mapping shown as a suggestion, never as fact
                        SectionTag(Copy.stateCardTag, ember: true)
                    }
                    // verbatim quote: memory voice with left ember-wash rule (§12)
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(Tokens.emberWash(room)).frame(width: 2)
                        Text(card.quote).memoryVoice(size: 13.5)
                            .foregroundStyle(Tokens.ink(room))
                    }
                    // On a CREATE_PERSON or LINK card this line is a *name*, not a
                    // transcript quote — the one thing in review that is safe to
                    // rewrite, and the only place a misheard name or a spoken
                    // shorthand can be corrected. Verbatim quotes stay untouchable
                    // (P5): assert cards have no ref and so never become tappable.
                    if let ref = vm.renameableRef(card), card.settled == nil {
                        Button { renaming = ref } label: {
                            Text(Copy.renameTapHint).interfaceVoice(size: 10.5)
                                .foregroundStyle(Tokens.inkFaint(room))
                        }
                        .accessibilityIdentifier("card.rename")
                    }
                    if let suggestion = card.stateSuggestion {
                        Text(suggestion).interfaceVoice(size: 11.5)
                            .foregroundStyle(Tokens.inkMuted(room))
                    }
                    // What actually gets saved, in the system's own voice — sans,
                    // because this is Orbit's reading of the sentence, not the
                    // sentence (§4.2). The quote above stays untouchable (P5).
                    if let fact = card.mappedFact {
                        Text(fact).interfaceVoice(size: 12, weight: .semibold)
                            .foregroundStyle(Tokens.ink(room))
                            .accessibilityIdentifier("card.mappedFact")
                    }
                    // when it happened, at the precision the record claims
                    if let when = card.whenLine {
                        Text(when).interfaceVoice(size: 11.5)
                            .foregroundStyle(Tokens.inkMuted(room))
                            .accessibilityIdentifier("card.when")
                    }
                    // why the last tap didn't take — plain ink, never red (D-1)
                    if let blocked = card.blocked {
                        Text(blocked).interfaceVoice(size: 11.5)
                            .foregroundStyle(Tokens.inkMuted(room))
                            .accessibilityIdentifier("card.blocked")
                    }
                    // the rationale earns its line only when it says something the
                    // quote above hasn't already said, word for word
                    if !card.rationale.isEmpty, !card.rationaleEchoesQuote {
                        Text(card.rationale).interfaceVoice(size: 11.5)
                            .foregroundStyle(Tokens.inkMuted(room))
                    }
                    HStack(spacing: 10) {
                        SecondaryButton(Copy.yes) { vm.accept(card) }
                        SecondaryButton(Copy.no) { vm.reject(card, reason: nil) }
                        if card.op == .assert || card.op == .proposeState
                            || card.op == .createEvent {
                            TertiaryButton(Copy.editAction) { editing = true }
                        }
                        Spacer()
                        TertiaryButton(Copy.later) { vm.setAside(card) }
                    }
                    if card.isEpisode {
                        // first_met falls out of confirming an episode AS the
                        // meeting — no special case in the model (§7.11)
                        TertiaryButton(Copy.firstMetAction) { vm.acceptAsFirstMet(card) }
                    }
                }
            }
            .sheet(item: Binding(get: { renaming.map { RenameTarget(ref: $0) } },
                                 set: { renaming = $0?.ref })) { target in
                RenameSheet(vm: vm, ref: target.ref)
            }
            .sheet(isPresented: $editing) {
                EditProposalSheet(vm: vm, card: card)
            }
        }
    }
}

/// Accept-with-edits (P5): the verbatim quote stays untouchable — it's what
/// was said — but the mapped value and dates are his to correct before the
/// fact lands.
struct EditProposalSheet: View {
    @ObservedObject var vm: ReviewViewModel
    let card: ReviewViewModel.Card
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss
    @State private var objectValue: String = ""
    @State private var validFrom: String = ""
    @State private var suggestedOrbit: String = ""
    @State private var occurredAt: String = ""

    var payloadDict: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(card.payload.utf8))) as? [String: Any] ?? [:]
    }

    var body: some View {
        RoomBackground { _ in
            VStack(alignment: .leading, spacing: 14) {
                Text(Copy.editAction).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                    .padding(.top, 28)
                // the quote is the record — shown, never editable here
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Tokens.emberWash(room)).frame(width: 2)
                    Text(card.quote).memoryVoice(size: 13.5)
                        .foregroundStyle(Tokens.ink(room))
                }
                if card.op == .assert {
                    editField(Copy.editValueLabel, text: $objectValue, id: "edit.value")
                    editField(Copy.editSinceLabel, text: $validFrom, id: "edit.validFrom")
                } else if card.op == .createEvent {
                    editField(Copy.editWhenLabel, text: $occurredAt, id: "edit.occurredAt")
                    Text(Copy.editWhenHint).interfaceVoice(size: 11.5)
                        .foregroundStyle(Tokens.inkFaint(room))
                } else {
                    editField(Copy.editOrbitLabel, text: $suggestedOrbit, id: "edit.orbit")
                }
                PrimaryButton(Copy.saveEdited) {
                    var dict = payloadDict
                    func put(_ key: String, _ value: String) {
                        if value.isEmpty { dict.removeValue(forKey: key) }
                        else { dict[key] = value }
                    }
                    if card.op == .assert {
                        put("object_value", objectValue)
                        put("valid_from", validFrom)
                    } else if card.op == .createEvent {
                        // the precision follows what he actually wrote: a year is
                        // a year, and Orbit must not re-sharpen it afterwards
                        let trimmed = occurredAt.trimmingCharacters(in: .whitespaces)
                        put("occurred_at", trimmed)
                        let parts = trimmed.split(separator: "-").count
                        dict["date_precision"] = parts >= 3 ? "exact"
                            : (parts == 2 ? "month" : "year")
                    } else {
                        put("suggested_orbit", suggestedOrbit)
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: dict),
                       let json = String(data: data, encoding: .utf8) {
                        vm.acceptEdited(card, payloadJSON: json)
                    }
                    dismiss()
                }
                Spacer()
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .overlay(alignment: .topTrailing) {
            TertiaryButton(Copy.notNow) { dismiss() }.padding()
        }
        .onAppear {
            objectValue = payloadDict["object_value"] as? String ?? ""
            validFrom = payloadDict["valid_from"] as? String ?? ""
            suggestedOrbit = payloadDict["suggested_orbit"] as? String ?? ""
            occurredAt = payloadDict["occurred_at"] as? String ?? ""
        }
    }

    func editField(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).interfaceVoice(size: 11, weight: .semibold)
                .foregroundStyle(Tokens.inkFaint(room))
            TextField("", text: text)
                .accessibilityIdentifier(id)
                .font(.system(size: 14))
                .padding(11)
                .background(Tokens.paper(room))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                    .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))
        }
    }
}

/// Desk & Deck land in Phase 5 (M3) on OrbitRecall's brief assembly.
struct DeskView: View {
    let personID: String
    var body: some View {
        RoomBackground { _ in
            BriefScreen(personID: personID)
        }
    }
}

struct SearchView: View {
    var initialQuery: String
    var body: some View {
        RoomBackground { _ in
            SearchScreen(initialQuery: initialQuery)
        }
    }
}

@main
struct OrbitAppMain: App {
    @StateObject private var model: AppModel

    init() {
        let env = ProcessInfo.processInfo.environment
        if env["ORBIT_UITEST"] == "1" {
            _model = StateObject(wrappedValue: AppModel.uiTest(env: env))
            return
        }
        do {
            let production = try AppModel.production()
            _model = StateObject(wrappedValue: production)
        } catch {
            // NEVER fall back to an in-memory store: the app would look normal
            // while silently writing memories to RAM. Fail visibly instead.
            _storeFailure = State(initialValue: String(describing: error))
            _model = StateObject(wrappedValue: try! AppModel(
                store: .inMemory(), transcription: MockTranscriber(canned: "")))
        }
    }

    @State private var storeFailure: String?

    var body: some Scene {
        WindowGroup {
            RoomBackground { _ in
                if let storeFailure {
                    StoreFailureView(detail: storeFailure)
                } else if model.selfID == nil {
                    OnboardingView()          // §7.12: one name, then the room
                } else {
                    // the backdrop goes INSIDE the stack: a NavigationStack
                    // paints an opaque system background over whatever sits
                    // behind it, so Home was rendering on white/black instead
                    // of `room` while every other surface looked correct.
                    NavigationStack {
                        HomeView().background(RoomBackdrop())
                    }
                }
            }
            .environmentObject(model)
            .task { if storeFailure == nil { model.warmModels() } }   // §6 dead-time download
        }
    }
}

/// The store failed to open. Nothing pretends to work: plain ink states the
/// problem (no red exists, D-1) and nothing is writable until it's resolved.
struct StoreFailureView: View {
    let detail: String
    @Environment(\.room) var room
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(Copy.storeFailureTitle).interfaceVoice(size: 17, weight: .bold)
                .foregroundStyle(Tokens.ink(room))
            Text(Copy.storeFailureBody).interfaceVoice(size: 12.5)
                .foregroundStyle(Tokens.inkMuted(room))
                .multilineTextAlignment(.center)
            Text(detail).interfaceVoice(size: 10.5)
                .foregroundStyle(Tokens.inkFaint(room))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
