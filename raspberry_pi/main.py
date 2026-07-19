"""AttendX Raspberry Pi attendance kiosk (headless — all feedback by voice).

Flow: detect face -> voice-guide the student into position -> embed ->
match against cached enrollments -> write check-in/check-out event ->
announce result. The app derives present/late/absent and sends the
notification; the Pi only records raw timestamps.
"""

import logging
import threading
import time

import cv2
import numpy as np

import config
import face_matcher
import firestore_client
import voice

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
log = logging.getLogger("main")


# --------------------------------------------------------------------------
# Camera (Pi Camera Module via picamera2; USB webcam fallback)
# --------------------------------------------------------------------------

class Camera:
    def __init__(self) -> None:
        self.picam = None
        self.cap = None
        try:
            from picamera2 import Picamera2
            from libcamera import Transform

            self.picam = Picamera2()
            cfg = self.picam.create_video_configuration(
                main={"size": config.FRAME_SIZE, "format": "RGB888"},
                transform=Transform(hflip=config.HFLIP, vflip=config.VFLIP),
            )
            self.picam.configure(cfg)
            self.picam.start()
            time.sleep(1.5)  # AE/AWB settle
            log.info("Pi Camera Module started")
        except Exception as exc:
            log.warning("picamera2 unavailable (%s); trying USB webcam", exc)
            self.cap = cv2.VideoCapture(0)
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.FRAME_SIZE[0])
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.FRAME_SIZE[1])
            if not self.cap.isOpened():
                raise RuntimeError("No camera found (CSI or USB)") from exc

    def read(self):
        """Returns a BGR frame or None."""
        if self.picam is not None:
            # picamera2 quirk: 'RGB888' arrays are BGR in memory (cv2-ready)
            return self.picam.capture_array()
        ok, frame = self.cap.read()
        return frame if ok else None


# --------------------------------------------------------------------------
# Guidance + quality gates: the same idea as enrollment — only a full,
# frontal, well-lit, centered, sharp face reaches embedding/matching.
# --------------------------------------------------------------------------

def guide(face, score: float, frame) -> str:
    """Voice-guides the student. Returns:
    'good'  — face passed all quality checks
    'bad'   — problem announced (or lighting issue), reset stability
    'blur'  — motion blur, silently skip this frame
    """
    frame_h, frame_w = frame.shape[:2]
    x, y, w, h = face

    # Weak detection = partial or turned-away face.
    if score < config.DETECT_GOOD_SCORE:
        voice.say("look_at_camera")
        return "bad"

    # Face cut off at any frame edge.
    m = config.EDGE_MARGIN_PX
    if x <= m or y <= m or x + w >= frame_w - m or y + h >= frame_h - m:
        voice.say("full_face")
        return "bad"

    if w < config.MIN_FACE_FRACTION * frame_w:
        voice.say("come_closer")
        return "bad"

    offset = ((x + w / 2) - frame_w / 2) / frame_w
    if abs(offset) > config.CENTER_TOLERANCE:
        # offset > 0: face is on the right side of the image.
        if config.MIRRORED:
            voice.say("move_left" if offset > 0 else "move_right")
        else:
            voice.say("move_right" if offset > 0 else "move_left")
        return "bad"

    gray = cv2.cvtColor(frame[y : y + h, x : x + w], cv2.COLOR_BGR2GRAY)
    if gray.mean() < config.MIN_BRIGHTNESS:
        voice.say("too_dark")
        return "bad"

    if cv2.Laplacian(gray, cv2.CV_64F).var() < config.MIN_SHARPNESS:
        return "blur"  # moving — wait for a sharp frame, no prompt

    return "good"


# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------

def connect_network(cache) -> bool:
    """Startup network sequence, narrated over the speaker.
    Falls back to the on-disk enrollment cache and keeps retrying in the
    background — the kiosk always comes up, with or without the hotspot."""
    voice.set_max_volume()
    voice.say("initializing", block=True, force=True)
    for attempt in range(1, config.NET_STARTUP_ATTEMPTS + 1):
        try:
            cache.refresh()  # also persists to disk for next offline boot
            voice.say("net_ok", block=True, force=True)
            return True
        except Exception as exc:
            log.warning("network attempt %d/%d failed: %s",
                        attempt, config.NET_STARTUP_ATTEMPTS, exc)
            time.sleep(4)

    have_cache = cache.load_disk()
    voice.say("net_fail", block=True, force=True)
    if not have_cache:
        log.error("offline AND no cached enrollments — faces can't match "
                  "until the network returns")

    def reconnect() -> None:
        while True:
            time.sleep(config.NET_RECONNECT_SECONDS)
            try:
                cache.refresh()
                log.info("network is back")
                voice.say("net_ok", force=True)
                return
            except Exception:
                pass

    threading.Thread(target=reconnect, daemon=True).start()
    return False


def main() -> None:
    db = firestore_client.init()
    cache = firestore_client.EnrollmentCache(db)
    connect_network(cache)
    cache.start_auto_refresh()

    writer = firestore_client.EventWriter(db)
    writer.start_retry_loop()

    detector = face_matcher.FaceDetector()
    embedder = face_matcher.FaceEmbedder()
    eye_detector = face_matcher.EyeDetector() if config.BLINK_REQUIRED else None
    blink_gate = face_matcher.BlinkGate()
    camera = Camera()

    voice.say("starting", block=True, force=True)
    log.info("ready")

    last_seen: dict[str, float] = {}  # uid -> monotonic time (debounce)
    stable = 0
    fails = 0
    blink_done = False
    blink_timeouts = 0
    emb_buffer: list = []  # rolling window fused before each match
    last_dark_prompt = 0.0

    while True:
        frame = camera.read()
        if frame is None:
            time.sleep(0.1)
            continue

        detected = detector.largest_face(frame)
        if detected is None:
            stable = 0
            fails = 0
            blink_done = False
            blink_timeouts = 0
            blink_gate.reset()
            emb_buffer.clear()
            # Dark room + no face: someone may be there but invisible.
            now = time.monotonic()
            if now - last_dark_prompt > config.NO_FACE_PROMPT_SECONDS:
                small = cv2.cvtColor(cv2.resize(frame, (160, 90)),
                                     cv2.COLOR_BGR2GRAY)
                if small.mean() < config.DARK_FRAME_MEAN:
                    voice.say("no_face_dark")
                    last_dark_prompt = now
            time.sleep(0.05)
            continue

        face, score = detected
        quality = guide(face, score, frame)
        if quality == "bad":
            stable = 0
            blink_done = False
            blink_timeouts = 0
            blink_gate.reset()
            emb_buffer.clear()
            continue
        if quality == "blur":
            continue  # keep stability, just wait for a sharp frame

        stable += 1
        if stable < config.STABLE_FRAMES:
            continue
        if stable == config.STABLE_FRAMES:
            if config.BLINK_REQUIRED:
                voice.say("blink_to_scan", force=True)
            else:
                voice.say("hold_still")

        crop = face_matcher.crop_face(frame, face)
        if crop is None:
            stable = 0
            continue

        # Liveness gate: face is stable — now require one real blink.
        if config.BLINK_REQUIRED and not blink_done:
            now = time.monotonic()
            if blink_gate.update(eye_detector.eyes_open(crop), now):
                blink_done = True  # blink seen — fall through and scan
                voice.say("scanning", force=True)
            elif blink_gate.timed_out(now):
                blink_timeouts += 1
                blink_gate.reset()
                if blink_timeouts >= config.BLINK_MAX_TIMEOUTS:
                    # Eye detector missing the blink (glasses/lighting) —
                    # don't hold the student hostage, scan anyway.
                    log.info("blink not caught after %d prompts — scanning",
                             blink_timeouts)
                    blink_done = True
                    voice.say("scanning", force=True)
                else:
                    voice.say("blink_to_scan")  # one gentle re-prompt
                continue
            else:
                continue  # keep watching for the blink

        # SWAP_RGB flips the color order fed to the model (set it in
        # config.py if the 'swapped' scores in the logs are much higher).
        model_input = crop if not config.SWAP_RGB else crop[:, :, ::-1].copy()
        embedding = embedder.embed(model_input)

        # Fuse a rolling window of frames (normalized mean — the app's
        # fuse()) to smooth out the Pi camera's frame-to-frame noise.
        emb_buffer.append(embedding)
        if len(emb_buffer) > config.FUSE_FRAMES:
            emb_buffer.pop(0)
        if len(emb_buffer) < config.FUSE_FRAMES:
            continue  # need a few frames before the first match attempt
        fused = np.mean(emb_buffer, axis=0)
        norm = np.linalg.norm(fused)
        fused = fused / norm if norm > 0 else fused

        snapshot = cache.snapshot()
        result = face_matcher.identify(fused, snapshot)
        uid = result["uid"]

        if config.LOG_MATCH_SCORES:
            log.info(
                "identify: score=%.3f pose=%s margin=%.3f (need >= %.2f) -> %s",
                result["score"], result["pose"] or "-", result["margin"],
                config.MATCH_THRESHOLD, uid or "NO MATCH",
            )

        if uid is None:
            fails += 1
            if fails >= config.MATCH_ATTEMPTS:
                voice.say("not_recognized", block=True, force=True)
                fails = 0
                stable = 0
                blink_done = False
                blink_timeouts = 0
                blink_gate.reset()
                emb_buffer.clear()
                time.sleep(2)  # let them reposition / walk away
            continue

        fails = 0
        stable = 0
        blink_done = False
        blink_timeouts = 0
        blink_gate.reset()
        emb_buffer.clear()
        info = cache.snapshot().get(uid, {})
        name = info.get("name") or ""

        # Debounce: ignore repeat matches within ~60 s (from the notes).
        now = time.monotonic()
        if now - last_seen.get(uid, -1e9) < config.DEBOUNCE_SECONDS:
            voice.say("already_marked")
            time.sleep(1)
            continue
        last_seen[uid] = now

        result = writer.record(uid, info.get("regNo", ""))
        log.info("event %s for %s (%s)", result, uid, name or "?")

        if result == "checkin":
            voice.say("verified", block=True, force=True)
            if name:
                voice.say_text(f"Welcome {name}. Checked in.")
            else:
                voice.say("checked_in", block=True, force=True)
        elif result == "checkout":
            if name:
                voice.say_text(f"Goodbye {name}. Checked out.")
            else:
                voice.say("checked_out", block=True, force=True)
        elif result == "queued":
            voice.say("verified", block=True, force=True)
            voice.say("no_network", block=True, force=True)
        else:  # skipped (within checkout guard window)
            voice.say("already_marked")

        time.sleep(1)


if __name__ == "__main__":
    while True:
        try:
            main()
        except KeyboardInterrupt:
            break
        except Exception:
            log.exception("fatal error — restarting in 10 s")
            voice.say("error", block=True, force=True)
            time.sleep(10)
