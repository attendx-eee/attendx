#!/bin/bash
# Generates the voice prompt WAVs into ./prompts/ using the best engine
# available: Piper (neural, near-human) > pico2wave > espeak-ng.
# Safe to re-run — always regenerates everything.
set -e
cd "$(dirname "$0")"
mkdir -p prompts voices

PIPER_VOICE="${PIPER_VOICE:-en_US-amy-medium}"

# One-time: install Piper into the venv (small, CPU-only).
if [ ! -x venv/bin/piper ]; then
  echo "Installing Piper TTS (one time)..."
  ./venv/bin/pip install piper-tts || echo "piper install failed — will fall back"
fi

synth() {
  key="$1"; text="$2"
  if [ -x venv/bin/piper ] && echo "$text" | ./venv/bin/piper \
        -m "$PIPER_VOICE" --data-dir voices --download-dir voices \
        -f "prompts/$key.wav" 2>/dev/null; then
    :
  elif command -v pico2wave >/dev/null 2>&1; then
    pico2wave -l en-GB -w "prompts/$key.wav" "$text"
  else
    espeak-ng -v en+f3 -s 150 -a 190 -w "prompts/$key.wav" "$text"
  fi
  # normalize loudness
  if command -v sox >/dev/null 2>&1; then
    sox "prompts/$key.wav" "prompts/_n.wav" gain -n -1 \
      && mv "prompts/_n.wav" "prompts/$key.wav"
  fi
  echo "  prompts/$key.wav"
}

synth starting        "Attendance system ready."
synth initializing    "Initializing. Searching for network."
synth net_ok          "Internet connection successful."
synth net_fail        "No internet. Please check the hotspot. Running in offline mode."
synth net_lost        "Internet disconnected. Attendance will be saved and synced automatically."
synth look_at_camera  "Please look straight at the camera."
synth full_face       "Bring your full face into the frame."
synth too_dark        "Too dark. Please move to better lighting."
synth no_face_dark    "No face detected. Please move to a brighter place."
synth come_closer     "Please come closer."
synth move_left       "Move slightly to your left."
synth move_right      "Move slightly to your right."
synth hold_still      "Hold still."
synth blink_to_scan   "Perfect. Now blink your eyes to scan."
synth scanning        "Scanning. Please wait."
synth verified        "Verified."
synth checked_in      "Checked in. Welcome."
synth checked_out     "Checked out. Goodbye."
synth already_marked  "Attendance already marked."
synth not_recognized  "Face not recognized. Please try again."
synth no_network      "Network issue. Your attendance will sync automatically."
synth error           "Something went wrong. Please try again."

# clear the dynamic-name cache so names regenerate with the new voice
rm -rf prompts/cache

echo "Done. Test with: aplay -D plughw:Headphones,0 prompts/starting.wav"
