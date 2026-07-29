#!/usr/bin/env bash
# Build whisper.cpp as an xcframework + fetch the two model tiers (DATA-MODEL §6).
# Runs on a Mac with Xcode (T3 — cannot run in the Linux build environment).
#
# Produces:
#   apps/OrbitApp/Vendor/whisper.xcframework      — the C library, iOS + simulator
#   apps/OrbitApp/Vendor/models/ggml-base.q5_1.bin            — bundled floor model
#   apps/OrbitApp/Vendor/models/ggml-large-v3-turbo-q5_0.bin  — download-ceiling model
#                                                   (hosted, not bundled; see §6)
#
# Decode discipline (2026-07-27 empirical findings, docs/build/WORKLOG.md):
#   - context carryover OFF (no_context=true / -mc 0): primed runs loop on
#     disfluent speech otherwise
#   - entropy_thold=2.8
#   - initial_prompt = known display names, comma-joined (assist only; the
#     NameMatcher post-pass is the correctness mechanism, PIPE-1)
# WhisperBridge.run() must pass exactly these flags.
set -euo pipefail
cd "$(dirname "$0")/.."

WHISPER_TAG="v1.7.5"   # pinned; bump deliberately and re-run PIPE-1/2 (ratchet rule)
VENDOR="apps/OrbitApp/Vendor"
WORK="$(mktemp -d)"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: this script needs a Mac with Xcode (see BUILD.md verification tiers)" >&2
  exit 1
fi

echo "== clone whisper.cpp @ ${WHISPER_TAG} =="
git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp "$WORK/whisper.cpp"

echo "== build xcframework (iOS device + simulator) =="
(cd "$WORK/whisper.cpp" && ./build-xcframework.sh)

mkdir -p "$VENDOR/models"
rm -rf "$VENDOR/whisper.xcframework"
cp -R "$WORK/whisper.cpp/build-apple/whisper.xcframework" "$VENDOR/whisper.xcframework"

echo "== fetch models =="
# floor: ships in the app bundle so capture never hard-fails (§6)
curl -L -o "$VENDOR/models/ggml-base.q5_1.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.q5_1.bin"
# ceiling: downloaded during onboarding by ModelManager; kept here for local
# device testing + as the artifact to host
curl -L -o "$VENDOR/models/ggml-large-v3-turbo-q5_0.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"

rm -rf "$WORK"

cat <<'DONE'
== done ==
Next steps (on the Mac):
  1. Add to apps/OrbitApp/project.yml under the OrbitApp target:
       dependencies:
         - framework: Vendor/whisper.xcframework
           embed: true
     (left out of the committed spec so CI builds without the vendored binary)
     then `xcodegen generate`.
  2. Replace the WhisperBridge placeholder (Transcription.swift) with the C
     calls; keep the flags in this script's header verbatim.
  3. Run the audio harness for PIPE-1/2 numbers:
     swift run orbit-evals measure --audio-fixtures <dir>   (T3, your device mics)
DONE
