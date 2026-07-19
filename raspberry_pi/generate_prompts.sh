#!/bin/bash
# Generates the pre-recorded voice prompt WAVs into ./prompts/
# Uses pico2wave (clearer voice) if available, otherwise espeak-ng.
# If sox is installed, every WAV is normalized to near-max loudness.
set -e
cd "$(dirname "$0")"
mkdir -p prompts

gen() {
  key="$1"; text="$2"
  if command -v pico2wave >/dev/null 2>&1; then
    pico2wave -l en-GB -w "prompts/$key.wav" "$text"
  else
    espeak-ng -v en+f3 -s 150 -a 190 -w "prompts/$key.wav" "$text"
  fi
  if command -v sox >/dev/null 2>&1; then
    sox "prompts/$key.wav" "prompts/_n.wav" gain -n -1 && mv "prompts/_n.wav" "prompts/$key.wav"
  fi
  echo "  prompts/$key.wav"
}

gen starting        "Attendance system ready."
gen initializing    "Initializing. Searching for network."
gen net_ok          "Internet connection successful."
gen net_fail        "No internet. Please check the hotspot. Running in offline mode."
gen look_at_camera  "Please look straight at the camera."
gen full_face       "Bring your full face into the frame."
gen too_dark        "Too dark. Please move to better lighting."
gen no_face_dark    "No face detected. Please move to a brighter place."
gen come_closer     "Please come closer."
gen move_left       "Move slightly to your left."
gen move_right      "Move slightly to your right."
gen hold_still      "Hold still."
gen blink_to_scan   "Perfect. Now blink your eyes to scan."
gen scanning        "Scanning. Please wait."
gen verified        "Verified."
gen checked_in      "Checked in. Welcome."
gen checked_out     "Checked out. Goodbye."
gen already_marked  "Attendance already marked."
gen not_recognized  "Face not recognized. Please try again."
gen no_network      "Network issue. Your attendance will sync automatically."
gen error           "Something went wrong. Please try again."

echo "Done. Test with: aplay prompts/starting.wav"
