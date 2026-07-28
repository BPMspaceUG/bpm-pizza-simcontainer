#!/usr/bin/env bash
# Audio round trip: generate an mp3 with text-to-speech, then transcribe it
# back with speech-to-text. The test creates its own fixture, so nothing has
# to be shipped in the image.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="04-audio-roundtrip"
header "text-to-speech and speech-to-text"

require_gateway

SENTENCE="Das Pferd frisst keinen Gurkensalat."
MP3="${TMPDIR:-/tmp}/pizzasim-tts-test.mp3"
TTS_MODEL="${TTS_MODEL:-tts-1}"
STT_MODEL="${STT_MODEL:-whisper}"

rm -f "$MP3"

# --- text to speech ---------------------------------------------------------
code=$(curl -sS -o "$MP3" -w '%{http_code}' \
       -X POST "$LITELLM_PIZZA_URL/audio/speech" \
       -H "Authorization: Bearer $LITELLM_PIZZA_KEY" \
       -H "Content-Type: application/json" \
       -d "{\"model\":\"${TTS_MODEL}\",\"voice\":\"alloy\",\"input\":\"${SENTENCE}\"}")

[ "$code" = "200" ] || fail "text-to-speech returned HTTP $code" \
    "$(head -c 200 "$MP3" 2>/dev/null)"

size=$(stat -c%s "$MP3" 2>/dev/null || echo 0)
printf '  mp3     : %s bytes\n' "$size"

[ "$size" -gt 10000 ] || fail "the mp3 is only ${size} bytes - probably an error body" \
    "$(head -c 200 "$MP3" 2>/dev/null)"

magic=$(head -c 3 "$MP3" | xxd -p)
case "$magic" in
    494433|fffb*|fff3*|fff2*) ;;   # ID3 tag or an MPEG frame header
    *) note "unexpected magic bytes ($magic) - continuing anyway" ;;
esac

# --- speech to text ---------------------------------------------------------
transcript=$(curl -sS -X POST "$LITELLM_PIZZA_URL/audio/transcriptions" \
             -H "Authorization: Bearer $LITELLM_PIZZA_KEY" \
             -F "file=@${MP3}" \
             -F "model=${STT_MODEL}" \
             -F "language=de" | jq -r '.text // empty')

printf '  spoken  : %s\n' "$SENTENCE"
printf '  heard   : %s\n' "${transcript:-<empty>}"

[ -n "$transcript" ] || fail "speech-to-text returned nothing" \
    "Check that the ${STT_MODEL} model exists on the gateway."

# Punctuation and casing vary; the content words are what matters.
lower=$(printf '%s' "$transcript" | tr '[:upper:]' '[:lower:]')
for word in pferd gurkensalat; do
    printf '%s' "$lower" | grep -q "$word" \
        || fail "the transcription does not contain \"$word\""
done

pass "audio round trip works in both directions"
