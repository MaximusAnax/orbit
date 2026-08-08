import SwiftUI
import OrbitCore
import OrbitRecall
import OrbitSearch
import OrbitDesign

/// The Desk (DESIGN §6): the permanent structure. Fixed tile order — positions
/// are muscle memory, and "what isn't here" is answerable because empty
/// sections collapse to nothing (never placeholder'd, D-8). Full-width =
/// editorial, half-width = factual.
struct BriefScreen: View {
    let personID: String
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @State private var brief: Brief?
    @State private var addingContact = false
    @State private var removing = false
    @State private var showDeck = false
    @State private var showPortrait = false
    // FN-13/FN-15: correcting what is already saved
    @State private var renaming = false
    @State private var factEdit: FactEdit?

    /// A saved fact the user is about to correct.
    struct FactEdit: Identifiable {
        let id: String          // assertion id
        let claim: String
    }

    var body: some View {
        ScrollView {
            if let brief {
                VStack(alignment: .leading, spacing: Tokens.gridGap) {
                    header(brief)

                    if brief.header.isKnownOf {
                        Text(Copy.knownOfBanner).interfaceVoice(size: 11.5)
                            .foregroundStyle(Tokens.inkMuted(room))
                    }

                    // tile 1 — Deck entry; hides on near-empty profiles
                    if brief.deckAvailable {
                        ModePill(Copy.walkMeIn) { showDeck = true }
                            .accessibilityIdentifier("desk.walkMeIn")
                    }

                    // tile 2 — hero: exactly one item, the ranking made visible
                    if let hero = brief.hero {
                        PaperTile {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionTag(Copy.heroTag, ember: true)
                                Text(hero.claim).memoryVoice(size: 17, weight: .semibold)
                                    .foregroundStyle(Tokens.ink(room))
                                if let teller = hero.teller {
                                    HearsayChip(teller: teller)
                                }
                                Text(hero.reason).interfaceVoice(size: 11.5)
                                    .foregroundStyle(Tokens.inkMuted(room))
                                // FN-15: review used to be the only moment
                                // anything could be corrected. It isn't now.
                                TertiaryButton(Copy.factFixAction) {
                                    factEdit = .init(id: hero.assertionID, claim: hero.claim)
                                }
                                .accessibilityIdentifier("desk.fixHero")
                            }
                        }
                    }

                    // tiles 3+4 — half-width factual pair
                    HStack(alignment: .top, spacing: Tokens.gridGap) {
                        if let thread = brief.openThreads.first {
                            PaperTile {
                                VStack(alignment: .leading, spacing: 5) {
                                    SectionTag(Copy.openTag)
                                    Text(thread.title).interfaceVoice(size: 13, weight: .semibold)
                                        .foregroundStyle(Tokens.ink(room))
                                    Text(thread.statusLine).interfaceVoice(size: 10.5)
                                        .foregroundStyle(Tokens.inkFaint(room))
                                    if brief.openThreads.count > 1 {
                                        Text("\(brief.openThreads.count - 1) more ›")
                                            .interfaceVoice(size: 10.5)
                                            .foregroundStyle(Tokens.inkFaint(room))
                                    }
                                }
                            }
                        }
                        if let loop = brief.loops.first {
                            NoteTile {
                                VStack(alignment: .leading, spacing: 5) {
                                    SectionTag(loop.tag, ember: true)
                                    Text(loop.description).memoryVoice(size: 13.5)
                                        .foregroundStyle(Tokens.ink(room))
                                }
                            }
                        }
                    }

                    // tile 5 — since you last saw them (editorial)
                    if !brief.changed.isEmpty {
                        PaperTile {
                            VStack(alignment: .leading, spacing: 7) {
                                SectionTag(Copy.sinceTag(brief.header.name))
                                ForEach(Array(brief.changed.enumerated()), id: \.element.assertionID) { pair in
                                    // §5.6: dashes separate memory items — never
                                    // interface elements, and never above the first
                                    if pair.offset > 0 { DashedDivider() }
                                    Text(pair.element.line)
                                        .memoryVoice(size: 13)
                                        .foregroundStyle(pair.element.isClose
                                            ? Tokens.inkMuted(room) : Tokens.ink(room))
                                }
                            }
                        }
                    }

                    // tile 6 — worth having back: unbounded, era-grouped past 6
                    if !brief.forgotten.isEmpty {
                        PaperTile {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionTag(Copy.worthHavingBack, ember: true)
                                if brief.forgotten.count > 6 {
                                    ForEach(eraGroups(brief.forgotten), id: \.era) { group in
                                        Text(group.era).interfaceVoice(size: 10.5, weight: .semibold)
                                            .foregroundStyle(Tokens.inkFaint(room))
                                        ForEach(Array(group.items.enumerated()), id: \.element.assertionID) { pair in
                                            if pair.offset > 0 { DashedDivider() }   // §5.6
                                            Text(pair.element.claim).memoryVoice(size: 13)
                                                .foregroundStyle(Tokens.ink(room))
                                        }
                                    }
                                } else {
                                    ForEach(Array(brief.forgotten.enumerated()), id: \.element.assertionID) { pair in
                                        if pair.offset > 0 { DashedDivider() }   // §5.6
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pair.element.claim).memoryVoice(size: 13)
                                                .foregroundStyle(Tokens.ink(room))
                                            if let teller = pair.element.teller {
                                                Text(Copy.toldYou(teller)).interfaceVoice(size: 10.5)
                                                    .foregroundStyle(Tokens.inkFaint(room))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // tiles 7+8 — collapse rows → mini-pages (never accordions)
                    if brief.timeline.eventCount > 0 {
                        NavigationLink {
                            TimelineMiniPage(personID: personID, title: Copy.timeline)
                        } label: {
                            collapseRow(Copy.timeline, detail: timelineLine(brief.timeline))
                        }
                    }
                    if !brief.reach.isEmpty {
                        NavigationLink {
                            ReachMiniPage(items: brief.reach,
                                          title: Copy.reach(brief.header.name),
                                          personID: personID) {
                                self.brief = try? app.assembleBrief(personID: personID)
                            }
                        } label: {
                            collapseRow(Copy.reach(brief.header.name),
                                        detail: brief.reach.map(\.kind).joined(separator: " · "))
                        }
                    }

                    // portrait entry: an invitation, never a queue (§7.11)
                    TertiaryButton(Copy.portraitTitle) { showPortrait = true }
                        .padding(.top, 6)
                    // The Reach row is absent until a handle exists (D-8), so
                    // without this there is no way to add the first one.
                    TertiaryButton(Copy.addContactAction) { addingContact = true }
                        .accessibilityIdentifier("desk.addContact")
                    TertiaryButton(Copy.removePersonAction) { removing = true }
                        .accessibilityIdentifier("desk.removePerson")
                }
                .padding(.top, Tokens.screenPaddingTop)
                .padding(.horizontal, Tokens.screenPaddingSide)
            }
        }
        .onAppear { brief = try? app.assembleBrief(personID: personID) }
        .fullScreenCover(isPresented: $showDeck) {
            if let brief { DeckScreen(brief: brief) }
        }
        .fullScreenCover(isPresented: $showPortrait) {
            PortraitCaptureView(personName: brief?.header.name)
        }
        .sheet(isPresented: $renaming) {
            CorrectionSheet(title: Copy.deskRenameTitle,
                            hint: Copy.deskRenameHint,
                            initial: brief?.header.name ?? "") { name in
                app.renamePerson(personID, to: name)
                brief = try? app.assembleBrief(personID: personID)
            }
        }
        .sheet(isPresented: $removing) {
            RemovePersonSheet(personID: personID, name: brief?.header.name ?? "")
        }
        .sheet(isPresented: $addingContact) {
            AddContactSheet(personID: personID) {
                brief = try? app.assembleBrief(personID: personID)
            }
        }
        .sheet(item: $factEdit) { edit in
            CorrectionSheet(title: Copy.factFixTitle,
                            hint: Copy.factFixHint,
                            initial: "",
                            quote: edit.claim) { value in
                app.amendFact(edit.id, objectValue: value)
                brief = try? app.assembleBrief(personID: personID)
            }
        }
    }

    func header(_ brief: Brief) -> some View {
        HStack(spacing: 12) {
            PortraitView(initial: String(brief.header.name.prefix(1)))
            VStack(alignment: .leading, spacing: 3) {
                // FN-13: a saved name had no way to be corrected anywhere in the
                // app. Tapping it is that way — quiet, no chrome, no pencil.
                Button { renaming = true } label: {
                    Text(brief.header.name).memoryVoice(size: 21, weight: .semibold)
                        .foregroundStyle(Tokens.ink(room))
                }
                .accessibilityIdentifier("desk.name")
                if !brief.header.metLine.isEmpty {
                    Text(brief.header.metLine).interfaceVoice(size: 11)
                        .foregroundStyle(Tokens.inkMuted(room))
                }
            }
            Spacer()
        }
    }

    func collapseRow(_ title: String, detail: String) -> some View {
        PaperTile {
            HStack {
                Text(title).interfaceVoice(size: 13, weight: .semibold)
                    .foregroundStyle(Tokens.ink(room))
                Spacer()
                Text(detail).interfaceVoice(size: 11)
                    .foregroundStyle(Tokens.inkFaint(room))
                Image(systemName: "chevron.right").font(.system(size: 10))
                    .foregroundStyle(Tokens.inkFaint(room))
            }
        }
    }

    func timelineLine(_ t: Brief.TimelineSummary) -> String {
        // real counts, never rounded (D-9)
        if let year = t.sinceYear {
            return "\(t.eventCount) event\(t.eventCount == 1 ? "" : "s") since \(year)"
        }
        return "\(t.eventCount) event\(t.eventCount == 1 ? "" : "s")"
    }

    struct EraGroup { var era: String; var items: [Brief.ForgottenItem] }

    func eraGroups(_ items: [Brief.ForgottenItem]) -> [EraGroup] {
        var order: [String] = []
        var byEra: [String: [Brief.ForgottenItem]] = [:]
        for item in items {
            if byEra[item.eraLabel] == nil { order.append(item.eraLabel) }
            byEra[item.eraLabel, default: []].append(item)
        }
        return order.map { EraGroup(era: $0, items: byEra[$0] ?? []) }
    }
}

/// The Deck (DESIGN §7): full-screen cards, tap advances, no timers — pacing
/// belongs to the walker. Ends on the tool's one memory-voice sentence.
struct DeckScreen: View {
    let brief: Brief
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss
    @State private var index = 0
    @State private var deck: Deck?

    var body: some View {
        RoomBackground { _ in
            Group {
                if let deck, index < deck.cards.count {
                    let card = deck.cards[index]
                    VStack(spacing: 18) {
                        // progress dots: 2px bars, ember fill on progress
                        HStack(spacing: 4) {
                            ForEach(0..<deck.cards.count, id: \.self) { i in
                                Rectangle()
                                    .fill(i <= index ? Tokens.ember(room) : Tokens.paperEdge(room))
                                    .frame(height: 2)
                            }
                        }
                        .padding(.top, Tokens.screenPaddingTop)

                        Spacer()
                        SectionTag(card.tag, ember: true)
                        Text(card.main)
                            .memoryVoice(size: 24, weight: .semibold)
                            .foregroundStyle(Tokens.ink(room))
                            .multilineTextAlignment(.center)
                        if !card.sub.isEmpty {
                            Text(card.sub).interfaceVoice(size: 12.5)
                                .foregroundStyle(Tokens.inkMuted(room))
                                .multilineTextAlignment(.center)
                        }
                        Spacer()

                        if card.isEnd {
                            TertiaryButton(Copy.deckEndTag) { dismiss() }
                                .padding(.bottom, 20)
                        }
                    }
                    .padding(.horizontal, Tokens.screenPaddingSide)
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }
                }
            }
        }
        .onAppear {
            let built = Deck.build(from: brief)
            deck = built
            // deck sessions count as surfaced — through the funnel (INV-5)
            try? app.edits.markSurfaced(assertions: built.surfacedAssertionIDs)
        }
    }

    func advance() {
        guard let deck else { return }
        if index < deck.cards.count - 1 {
            withAnimation(.easeOut(duration: 0.18)) { index += 1 }
        } else {
            dismiss()
        }
    }
}

/// Timeline mini-page (tile 7 opens here — pushed full screen, same room).
struct TimelineMiniPage: View {
    let personID: String
    let title: String
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @State private var rows: [(id: String, when: String, kind: String, title: String)] = []

    var body: some View {
        // carries the room itself — see ReachMiniPage
        RoomBackground { _ in
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.gridGap) {
                Text(title).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                ForEach(rows, id: \.id) { row in
                    PaperTile {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(row.when.prefix(10))).interfaceVoice(size: 10.5)
                                .foregroundStyle(Tokens.inkFaint(room))
                            Text(row.title.isEmpty ? row.kind : row.title)
                                .memoryVoice(size: 13.5)
                                .foregroundStyle(Tokens.ink(room))
                        }
                    }
                }
            }
            .padding(.top, Tokens.screenPaddingTop)
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        }
        .onAppear {
            rows = ((try? app.store.db.query(
                """
                SELECT e.id, e.occurred_at, e.kind, COALESCE(e.title,'') AS title
                FROM event e JOIN event_participant ep ON ep.event_id = e.id
                WHERE ep.person_id=? AND e.lifecycle='confirmed'
                ORDER BY e.occurred_at DESC
                """, [.text(personID)])) ?? []).compactMap { r in
                guard let id = r.text("id") else { return nil }
                return (id, r.text("occurred_at") ?? "", r.text("kind") ?? "",
                        r.text("title") ?? "")
            }
        }
    }
}

/// Reach mini-page (tile 8): contact kinds with tap-to-act affordances.
///
/// Handles arrive by hand, not by voice. ORBIT.md §Contact Points spans phone,
/// email, Instagram, LinkedIn, X, a website — the one data type a transcriber
/// reliably ruins, and the one where a near-miss is worthless rather than merely
/// vague. `addContactPoint` has been in the write layer since M3 with no way to
/// call it; this is that way. Tap-to-act stays deferred (DESIGN §338).
struct ReachMiniPage: View {
    let items: [Brief.ReachItem]
    let title: String
    var personID: String? = nil
    var onAdded: () -> Void = {}
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @State private var adding = false

    var body: some View {
        // Pushed into the NavigationStack, which paints its own opaque
        // background — a mini-page that does not carry the room renders on
        // system black/white (see FN-24).
        RoomBackground { _ in
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.gridGap) {
                Text(title).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                // D-8: an empty section says so plainly rather than rendering
                // a placeholder row.
                if items.isEmpty {
                    Text(Copy.reachEmpty).interfaceVoice(size: 12)
                        .foregroundStyle(Tokens.inkFaint(room))
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    PaperTile {
                        HStack {
                            Text(item.kind).interfaceVoice(size: 12, weight: .semibold)
                                .foregroundStyle(Tokens.inkMuted(room))
                            Text(item.value).interfaceVoice(size: 13)
                                .foregroundStyle(Tokens.ink(room))
                            Spacer()
                        }
                    }
                }
                if personID != nil {
                    SecondaryButton(Copy.addContactAction) { adding = true }
                        .accessibilityIdentifier("reach.add")
                        .padding(.top, 4)
                }
            }
            .padding(.top, Tokens.screenPaddingTop)
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        }
        .sheet(isPresented: $adding) {
            if let personID {
                AddContactSheet(personID: personID, onSaved: onAdded)
            }
        }
    }
}

/// Retiring a person (FIELD-NOTES FN-29). Deliberately a sheet rather than a
/// bare button: "remove" reads as destruction, and this is not — so the screen
/// that offers it is also the screen that says what it actually does.
struct RemovePersonSheet: View {
    let personID: String
    let name: String
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.room) var room

    var body: some View {
        RoomBackground { _ in
            VStack(alignment: .leading, spacing: 18) {
                Text(Copy.removePersonTitle(name))
                    .interfaceVoice(size: 16, weight: .semibold)
                    .foregroundStyle(Tokens.ink(room))
                Text(Copy.retirePersonHint).interfaceVoice(size: 12)
                    .foregroundStyle(Tokens.inkMuted(room))
                PrimaryButton(Copy.retirePersonAction) {
                    app.retire(person: personID)
                    dismiss()
                }
                .accessibilityIdentifier("remove.retire")
                TertiaryButton(Copy.notNow) { dismiss() }
                Spacer()
            }
            .padding(.top, 30)
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
    }
}

/// One kind, one value. The kind list is `ContactPointKind` verbatim, so the
/// sheet cannot invent a category the ledger has no column for.
struct AddContactSheet: View {
    let personID: String
    let onSaved: () -> Void
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.room) var room
    @State private var kind: ContactPointKind = .phone
    @State private var value = ""

    private let kinds: [ContactPointKind] = [.phone, .email, .instagram, .linkedin,
                                             .x, .website, .other]

    var body: some View {
        RoomBackground { _ in
            VStack(alignment: .leading, spacing: 16) {
                Text(Copy.addContactTitle).interfaceVoice(size: 16, weight: .semibold)
                    .foregroundStyle(Tokens.ink(room))

                // mode entries, not a fourth button tier (§3.5/§3.6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(kinds, id: \.rawValue) { k in
                            Button { kind = k } label: {
                                Text(Copy.contactKindLabel(k.rawValue))
                                    .interfaceVoice(size: 12,
                                                    weight: k == kind ? .semibold : .regular)
                                    .foregroundStyle(k == kind ? Tokens.emberInk(room)
                                                               : Tokens.inkMuted(room))
                                    .padding(.vertical, 7).padding(.horizontal, 12)
                                    .background(k == kind ? Tokens.ember(room)
                                                          : Tokens.pillBg(room))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(
                                        k == kind ? .clear : Tokens.pillEdge(room), lineWidth: 1))
                            }
                        }
                    }
                }

                TextField("", text: $value)
                    .accessibilityIdentifier("contact.value")
                    .font(.system(size: 16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Tokens.paper(room))
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                        .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))

                Text(Copy.addContactHint).interfaceVoice(size: 11.5)
                    .foregroundStyle(Tokens.inkFaint(room))

                PrimaryButton(Copy.addContactSave) {
                    app.addContact(person: personID, kind: kind, value: value)
                    onSaved()
                    dismiss()
                }
                TertiaryButton(Copy.notNow) { dismiss() }
                Spacer()
            }
            .padding(.top, 30)
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
    }
}

/// Search & Discover (M4, DESIGN §12): one field, three query shapes, results
/// as-you-type — no submit affordance exists (J-8). Evidence lines with
/// remembered content speak in the memory voice; the "And maybe —" band is
/// visually distinct (note material) and every maybe cites its source.
struct SearchScreen: View {
    @State var query: String
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @State private var result: Searcher.Result = .empty

    init(initialQuery: String) {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.gridGap) {
                TextField(Copy.searchPlaceholders[1], text: $query)
                    .accessibilityIdentifier("search.field")
                    .font(.system(size: 14))
                    .padding(.vertical, 11).padding(.horizontal, 15)
                    .background(Tokens.pillBg(room))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Tokens.pillEdge(room), lineWidth: 1))
                    .onChange(of: query) { _, text in
                        result = (try? Searcher(reader: app.store.reader).search(text)) ?? .empty
                    }

                switch result {
                case .people(let hits):
                    ForEach(hits, id: \.personID) { hit in
                        NavigationLink { DeskView(personID: hit.personID) } label: {
                            PaperTile {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.name).memoryVoice(size: 15, weight: .semibold)
                                        .foregroundStyle(Tokens.ink(room))
                                    if !hit.anchor.isEmpty {
                                        Text(hit.anchor).interfaceVoice(size: 11)
                                            .foregroundStyle(Tokens.inkMuted(room))
                                    }
                                }
                            }
                        }
                    }

                case .answer(let answer):
                    answerView(answer)

                case .probably(let top, let runnersUp):
                    if let top {
                        PaperTile {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Probably \(top.name) — here's why")
                                    .interfaceVoice(size: 13, weight: .semibold)
                                    .foregroundStyle(Tokens.ink(room))
                                ForEach(Array(top.evidence.enumerated()), id: \.offset) { _, ev in
                                    // matched facts underlined in ember-wash — the
                                    // search showing its work (§12)
                                    Text(ev.text).memoryVoice(size: 13)
                                        .foregroundStyle(Tokens.ink(room))
                                        .emberEmphasis()
                                }
                            }
                        }
                        ForEach(runnersUp, id: \.personID) { hit in
                            Text("or \(hit.name)").interfaceVoice(size: 11.5)
                                .foregroundStyle(Tokens.inkFaint(room))
                        }
                    }

                case .empty:
                    // An empty field is not a failed search: it is the moment to
                    // browse. A typed query that found nothing still renders
                    // nothing at all (D-8) — no "no results" chrome.
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        rosterView()
                    } else {
                        EmptyView()
                    }
                }
            }
            .padding(.top, Tokens.screenPaddingTop)
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .onAppear {
            result = (try? Searcher(reader: app.store.reader).search(query)) ?? .empty
        }
    }

    /// The roster — reached by clearing the search field rather than by a fourth
    /// door, so Home stays the ratified three (§12).
    @ViewBuilder
    func rosterView() -> some View {
        let people = app.roster()
        SectionTag(Copy.rosterTitle)
            .padding(.top, 4)
        if people.isEmpty {
            Text(Copy.rosterEmpty).interfaceVoice(size: 12)
                .foregroundStyle(Tokens.inkFaint(room))
        }
        ForEach(people) { person in
            NavigationLink { DeskView(personID: person.id) } label: {
                PaperTile {
                    HStack(spacing: 11) {
                        PortraitView(initial: String(person.name.prefix(1)).uppercased(),
                                     size: 34)
                        Text(person.name).memoryVoice(size: 15, weight: .semibold)
                            .foregroundStyle(Tokens.ink(room))
                        if person.isKnownOf {
                            // §7.3: known through others, never met — said, not badged
                            Text(Copy.knownOfShort).interfaceVoice(size: 10.5)
                                .foregroundStyle(Tokens.inkFaint(room))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func answerView(_ answer: Searcher.Answer) -> some View {
        // an ANSWER, not matches: count first (a true count, D-9)
        if let fact = answer.factAnswer {
            PaperTile {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fact).memoryVoice(size: 17, weight: .semibold)
                        .foregroundStyle(Tokens.ink(room))
                    ForEach(Array((answer.firsthand.first?.evidence ?? []).enumerated()),
                            id: \.offset) { _, ev in
                        evidenceLine(ev)
                    }
                }
            }
        } else if !answer.firsthand.isEmpty {
            Text("\(answer.firsthand.count)")
                .interfaceVoice(size: 12, weight: .semibold)
                .foregroundStyle(Tokens.inkMuted(room))
        }
        ForEach(answer.firsthand, id: \.personID) { hit in
            NavigationLink { DeskView(personID: hit.personID) } label: {
                PaperTile {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(hit.name).memoryVoice(size: 14.5, weight: .semibold)
                            .foregroundStyle(Tokens.ink(room))
                        ForEach(Array(hit.evidence.enumerated()), id: \.offset) { _, ev in
                            evidenceLine(ev)
                        }
                    }
                }
            }
        }
        if !answer.maybe.isEmpty {
            // the known-of band: visually distinct, each citing its source (§12)
            Text("And maybe —").interfaceVoice(size: 12, weight: .semibold)
                .foregroundStyle(Tokens.inkMuted(room))
                .padding(.top, 6)
            ForEach(answer.maybe, id: \.personID) { hit in
                NoteTile(tilted: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(hit.name).memoryVoice(size: 14, weight: .semibold)
                            .foregroundStyle(Tokens.ink(room))
                        Text(hit.source).interfaceVoice(size: 11)
                            .foregroundStyle(Tokens.inkMuted(room))
                        ForEach(Array(hit.evidence.enumerated()), id: \.offset) { _, ev in
                            evidenceLine(ev)
                        }
                    }
                }
            }
        }
    }

    func evidenceLine(_ ev: Searcher.Evidence) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(ev.text).memoryVoice(size: 12.5)
                .foregroundStyle(Tokens.inkMuted(room))
            if let bound = ev.timeBound {
                Text(bound).interfaceVoice(size: 10.5)
                    .foregroundStyle(Tokens.inkFaint(room))
            }
        }
    }
}

/// Correcting something already saved (FIELD-NOTES FN-13 / FN-15).
///
/// One sheet for both jobs, because both are the same shape: show what is
/// there, take a replacement, write it through the funnel (INV-5). When a
/// quote is passed it is shown and untouchable — his words are the record
/// (P5); the correction lands on what Orbit filed under them, and INV-1 keeps
/// the original readable in the ledger.
struct CorrectionSheet: View {
    let title: String
    let hint: String
    let initial: String
    var quote: String? = nil
    let onSave: (String) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.room) var room
    @State private var text = ""

    var body: some View {
        RoomBackground { _ in
            VStack(alignment: .leading, spacing: 16) {
                Text(title).interfaceVoice(size: 16, weight: .semibold)
                    .foregroundStyle(Tokens.ink(room))
                if let quote {
                    Text(quote).memoryVoice(size: 14)
                        .foregroundStyle(Tokens.inkMuted(room))
                }
                TextField("", text: $text)
                    .accessibilityIdentifier("correction.field")
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Tokens.paper(room))
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                        .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))
                Text(hint).interfaceVoice(size: 11.5)
                    .foregroundStyle(Tokens.inkFaint(room))
                PrimaryButton(Copy.saveCorrection) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                    dismiss()
                }
                TertiaryButton(Copy.notNow) { dismiss() }
                Spacer()
            }
            .padding(.top, 30)
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .onAppear { text = initial }
    }
}
