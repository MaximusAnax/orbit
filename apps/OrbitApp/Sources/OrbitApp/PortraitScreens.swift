import SwiftUI
import OrbitCore
import OrbitDesign

/// Portrait capture (§7.11): one continuous, pausable recording with skippable
/// serif prompts. Never queued, never bulk-prompted — a contact with no
/// portrait is a valid permanent state. Downstream is the ordinary capture
/// flow: transcript review, extraction (episodes → reconstructed events,
/// periods → interval assertions, PROPOSE_STATE on explicit declarations),
/// person-grouped review.
struct PortraitCaptureView: View {
    let personName: String?      // nil = a self-portrait (the era-anchor registry, §7.12)
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @Environment(\.dismiss) var dismiss
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var promptIndex = 0

    var body: some View {
        RoomBackground { _ in
            VStack(spacing: 22) {
                Text(Copy.portraitTitle).interfaceVoice(size: 20, weight: .bold)
                    .foregroundStyle(Tokens.ink(room))
                    .padding(.top, 30)
                if let personName {
                    Text(personName).memoryVoice(size: 16, weight: .semibold)
                        .foregroundStyle(Tokens.ink(room))
                }
                Text(Copy.portraitHint).interfaceVoice(size: 12)
                    .foregroundStyle(Tokens.inkMuted(room))
                    .multilineTextAlignment(.center)

                Spacer()

                // the current prompt — serif, skippable, unhurried
                if promptIndex < Copy.portraitPrompts.count {
                    Text(Copy.portraitPrompts[promptIndex])
                        .memoryVoice(size: 19)
                        .foregroundStyle(Tokens.ink(room))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                    TertiaryButton(Copy.skipPrompt) {
                        promptIndex += 1
                    }
                }

                Spacer()

                // pause genuinely pauses — one continuous, pausable session (§7.11)
                Button {
                    if !isRecording {
                        isRecording = app.beginRecording()
                    } else if isPaused {
                        app.recorder.resume()
                        isPaused = false
                    } else {
                        app.recorder.pause()
                        isPaused = true
                    }
                } label: {
                    Circle().fill(Tokens.ember(room))
                        .frame(width: 96, height: 96)
                        .overlay(Image(systemName: !isRecording ? "mic.fill"
                                        : (isPaused ? "mic.fill" : "pause.fill"))
                            .font(.system(size: 34))
                            .foregroundStyle(Tokens.emberInk(room)))
                }
                .accessibilityIdentifier("portrait.mic")
                if isRecording {
                    Text(isPaused ? Copy.portraitPaused : Copy.captureRecording)
                        .interfaceVoice(size: 12)
                        .foregroundStyle(Tokens.inkMuted(room))
                }
                if isRecording {
                    PrimaryButton(Copy.portraitDone) {
                        isRecording = false
                        isPaused = false
                        Task { await app.endRecording(kind: .portrait) }
                    }
                }
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, Tokens.screenPaddingSide)
        }
        .onDisappear {
            if isRecording {
                isRecording = false
                app.cancelRecording()
            }
        }
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

/// Onboarding (§7.12): quiet. One name creates the single `is_self` row
/// (INV-22) — no forms, no tour. The portrait invite is a suggestion line,
/// never a queue.
struct OnboardingView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.room) var room
    @State private var name = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(Copy.onboardingNamePrompt)
                .interfaceVoice(size: 19, weight: .semibold)
                .foregroundStyle(Tokens.ink(room))
            TextField("", text: $name)
                .accessibilityIdentifier("onboarding.name")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Tokens.paper(room))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard)
                    .strokeBorder(Tokens.paperEdge(room), lineWidth: 1))
                .padding(.horizontal, 40)
            PrimaryButton(Copy.onboardingBegin) {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                app.ensureSelf(named: trimmed)
            }
            Text(Copy.onboardingPortraitInvite)
                .interfaceVoice(size: 11.5)
                .foregroundStyle(Tokens.inkFaint(room))
            Spacer()
        }
        .padding(.horizontal, Tokens.screenPaddingSide)
    }
}
