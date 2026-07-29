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

    var body: some View {
        VStack(spacing: 14) {
            // Door 2: one field, three query shapes — no submit affordance exists (J-8)
            NavigationLink {
                SearchView(initialQuery: searchText)
            } label: {
                HStack {
                    Text(Copy.searchPlaceholders[0])
                        .interfaceVoice(size: 13)
                        .foregroundStyle(Tokens.inkFaint(room))
                    Spacer()
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(Tokens.pillBg(room))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Tokens.pillEdge(room), lineWidth: 1))
            }

            // "Today" — at most two reasoned items; collapses entirely when empty (D-8)
            if !app.todayItems.isEmpty {
                VStack(spacing: Tokens.gridGap) {
                    ForEach(app.todayItems) { item in
                        NavigationLink {
                            DeskView(personID: item.personID)
                        } label: {
                            PaperTile {
                                VStack(alignment: .leading, spacing: 6) {
                                    SectionTag("Today", ember: true)
                                    Text(item.personName).memoryVoice(size: 15, weight: .semibold)
                                        .foregroundStyle(Tokens.ink(room))
                                    Text(item.reason).interfaceVoice(size: 12)
                                        .foregroundStyle(Tokens.inkMuted(room))
                                }
                            }
                        }
                    }
                }
            } else {
                Text(Copy.todayEmpty)
                    .interfaceVoice(size: 12)
                    .foregroundStyle(Tokens.inkFaint(room))
                    .padding(.top, 6)
            }

            Spacer()

            // Door 1: the capture mic — the app's one large ember object (§12)
            Button {
                showCapture = true
            } label: {
                Circle()
                    .fill(Tokens.ember(room))
                    .frame(width: 84, height: 84)
                    .overlay(Image(systemName: "mic.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Tokens.emberInk(room)))
            }
            .accessibilityLabel(Copy.captureIdle)
            .accessibilityIdentifier("home.mic")

            // Set-asides: a footer text line, never a card, never a badge (D-2)
            if app.setAsideCount > 0 {
                Text(Copy.setAsideFooter(app.setAsideCount))
                    .interfaceVoice(size: 11)
                    .foregroundStyle(Tokens.inkFaint(room))
                    .accessibilityIdentifier("home.setAsideFooter")
                    .padding(.bottom, 4)
            }
        }
        .padding(.top, Tokens.screenPaddingTop)
        .padding(.horizontal, Tokens.screenPaddingSide)
        .overlay(alignment: .topTrailing) {
            // the one quiet drawer: key entry (chrome-minimal, faint ink)
            Button { showSettings = true } label: {
                Image(systemName: "key")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.inkFaint(room))
                    .padding(10)
            }
            .accessibilityIdentifier("home.settings")
        }
        .sheet(isPresented: $showCapture) { CaptureView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { app.refreshAmbient() }
    }
}

/// Key entry (§7.9 seam's one visible knob): two secure fields, keychain-only
/// storage, provider chosen by whichever key exists.
struct SettingsView: View {
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss
    @State private var anthropicKey = KeychainLite.read("anthropic-api-key") ?? ""
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

                keyField(Copy.anthropicKeyLabel, text: $anthropicKey, id: "settings.anthropicKey")
                keyField(Copy.openAIKeyLabel, text: $openAIKey, id: "settings.openAIKey")

                PrimaryButton(Copy.saveKeys) {
                    KeychainLite.write("anthropic-api-key",
                                       value: anthropicKey.trimmingCharacters(in: .whitespaces))
                    KeychainLite.write("openai-api-key",
                                       value: openAIKey.trimmingCharacters(in: .whitespaces))
                    saved = true
                }
                if saved {
                    Text(Copy.keySaved).interfaceVoice(size: 11.5)
                        .foregroundStyle(Tokens.inkMuted(room))
                }
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
                        app.beginRecording()
                        isRecording = true
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
                        .onSubmit {
                            let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            try? app.captureTypedNote(text: text)   // typed text IS the transcript (J-5)
                            typed = ""
                        }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .presentationDetents([.large])
        .overlay(alignment: .topTrailing) {
            TertiaryButton(Copy.notNow) { dismiss() }.padding()
        }
        .fullScreenCover(item: transcriptBinding) { vm in
            TranscriptReviewView(vm: vm)
        }
        .fullScreenCover(item: reviewBinding) { vm in
            ReviewView(vm: vm)
        }
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
                        TertiaryButton(Copy.later) { vm.app?.pendingCapture = nil }
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

struct ProposalCardView: View {
    @ObservedObject var vm: ReviewViewModel
    let card: ReviewViewModel.Card
    @Environment(\.room) var room

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
                    Text(question).memoryVoice(size: 13.5)
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
                    if let suggestion = card.stateSuggestion {
                        Text(suggestion).interfaceVoice(size: 11.5)
                            .foregroundStyle(Tokens.inkMuted(room))
                    }
                    Text(card.rationale).interfaceVoice(size: 11.5)
                        .foregroundStyle(Tokens.inkMuted(room))
                    HStack(spacing: 10) {
                        SecondaryButton(Copy.yes) { vm.accept(card) }
                        SecondaryButton(Copy.no) { vm.reject(card, reason: nil) }
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
        let m: AppModel
        if env["ORBIT_UITEST"] == "1" {
            m = AppModel.uiTest(env: env)
        } else {
            m = (try? AppModel.production())
                ?? (try! AppModel(store: .inMemory(), transcription: MockTranscriber(canned: "")))
        }
        _model = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        WindowGroup {
            RoomBackground { _ in
                if model.selfID == nil {
                    OnboardingView()          // §7.12: one name, then the room
                } else {
                    NavigationStack { HomeView() }
                }
            }
            .environmentObject(model)
            .task { model.warmModels() }   // ceiling model rides onboarding dead time (§6)
        }
    }
}
