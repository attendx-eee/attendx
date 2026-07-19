"""Speaker output for the headless Pi.

Pre-recorded WAV prompts (generate_prompts.sh) + espeak-ng for dynamic
text. PREEMPTIVE: starting a new prompt instantly kills whatever is
currently playing — the newest instruction always wins. Per-key cooldown
stops the same prompt machine-gunning. Audio failure never crashes the
attendance loop.
"""

import logging
import subprocess
import threading
import time

import config

log = logging.getLogger("voice")

# Phrase key -> spoken text. generate_prompts.sh reads this table.
PHRASES = {
    "starting": "Attendance system ready.",
    "initializing": "Initializing. Searching for network.",
    "net_ok": "Internet connection successful.",
    "net_fail": "No internet. Please check the hotspot. Running in offline mode.",
    "look_at_camera": "Please look straight at the camera.",
    "full_face": "Bring your full face into the frame.",
    "too_dark": "Too dark. Please move to better lighting.",
    "no_face_dark": "No face detected. Please move to a brighter place.",
    "come_closer": "Please come closer.",
    "move_left": "Move slightly to your left.",
    "move_right": "Move slightly to your right.",
    "hold_still": "Hold still.",
    "blink_to_scan": "Perfect. Now blink your eyes to scan.",
    "scanning": "Scanning. Please wait.",
    "verified": "Verified.",
    "checked_in": "Checked in. Welcome.",
    "checked_out": "Checked out. Goodbye.",
    "already_marked": "Attendance already marked.",
    "not_recognized": "Face not recognized. Please try again.",
    "no_network": "Network issue. Your attendance will sync automatically.",
    "error": "Something went wrong. Please try again.",
}

_lock = threading.Lock()
_last_spoken: dict[str, float] = {}
_current: subprocess.Popen | None = None


def _start(cmd: list[str]) -> subprocess.Popen | None:
    """Kill whatever is playing, start the new sound."""
    global _current
    try:
        with _lock:
            if _current is not None and _current.poll() is None:
                _current.kill()
            _current = subprocess.Popen(
                cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            return _current
    except Exception as exc:  # audio must never kill the loop
        log.warning("audio failed: %s", exc)
        return None


def _wait(proc: subprocess.Popen | None) -> None:
    if proc is None:
        return
    try:
        proc.wait(timeout=15)
    except Exception:
        pass


def set_max_volume() -> None:
    """Force the headphone jack to full volume (runs at every startup —
    survives reboots and ALSA state resets)."""
    try:
        subprocess.run(
            ["amixer", "-c", "Headphones", "sset", "PCM", "100%"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
        )
    except Exception as exc:
        log.warning("could not set volume: %s", exc)


def _espeak_cmd(text: str) -> list[str]:
    return ["espeak-ng", "-v", config.ESPEAK_VOICE, "-s", config.ESPEAK_SPEED,
            "-a", config.ESPEAK_AMPLITUDE, text]


def say(key: str, block: bool = False, force: bool = False) -> None:
    """Play a prompt, instantly replacing anything already playing.
    Non-forced repeats of the SAME prompt are rate-limited."""
    now = time.monotonic()
    with _lock:
        if not force and now - _last_spoken.get(key, 0) < config.PROMPT_COOLDOWN_SECONDS:
            return
        _last_spoken[key] = now

    wav = config.PROMPTS_DIR / f"{key}.wav"
    if wav.exists():
        cmd = ["aplay", "-q", str(wav)]
    elif key in PHRASES:
        cmd = _espeak_cmd(PHRASES[key])
    else:
        return

    proc = _start(cmd)
    if block:
        _wait(proc)


def say_text(text: str, block: bool = True) -> None:
    """Speak dynamic text (student names etc.), replacing current audio."""
    proc = _start(_espeak_cmd(text))
    if block:
        _wait(proc)
