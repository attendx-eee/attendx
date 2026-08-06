"""AttendX Pi configuration. All values here must stay in sync with
lib/core/constants/app_config.dart and PI_INTEGRATION_NOTES.md."""

from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

# ---------------- Firebase ----------------
SERVICE_ACCOUNT_FILE = BASE_DIR / "serviceAccountKey.json"

ATTENDANCE_COLLECTION = "attendance_events"
ENROLLMENTS_COLLECTION = "student_face_enrollments"
STUDENTS_COLLECTION = "students"
TIMETABLE_OVERRIDES_COLLECTION = "timetable_overrides"

DEVICE_ID = "pi-gate-1"

# College local timezone — the `date` field must be the IST date.
TIMEZONE = "Asia/Kolkata"

# Re-download face templates this often (app adapts embeddings over time;
# notes say refresh at least daily).
CACHE_REFRESH_HOURS = 6

# ---------------- Face matching (same as app's AdaptiveFaceService) ----
MODEL_FILE = BASE_DIR / "mobilefacenet.tflite"   # copy from assets/models/
YUNET_FILE = BASE_DIR / "face_detection_yunet_2023mar.onnx"

# The app uses 0.75 (phone camera matching phone enrollment). The Pi
# camera differs from the enrollment camera (diag: same person = 0.5-0.6,
# stranger = ~0.3), so the Pi uses a lower cutoff between those bands.
MATCH_THRESHOLD = 0.58
MATCH_MARGIN = 0.06      # required lead over runner-up (2+ students)
CONFIRM_MATCHES = 2      # same student must win N consecutive fused
                         # windows before attendance is recorded — the
                         # standard temporal-consistency guard against
                         # one-frame wrong recognitions
POSE_FALLBACK_TOP_K = 3  # per-pose check for top-K centroid candidates
FUSE_FRAMES = 3          # average N frames' embeddings before matching
                         # (steadies the Pi's noisy captures, like app's fuse())

LOG_MATCH_SCORES = True  # log best similarity scores on every attempt
SWAP_RGB = False         # set True if logs show 'swapped' scores much higher
                         # (color channel order mismatch with the app)

# Crop expansion around the YuNet box, as fractions of box size. The app
# enrolls with ML Kit boxes (more forehead/head than YuNet) — run
# tune_match.py to find the values that best match YOUR enrollment.
CROP_EXPAND_TOP = 0.10
CROP_EXPAND_BOTTOM = 0.10
CROP_EXPAND_SIDES = 0.10

# ---------------- Camera / guidance ----------------
FRAME_SIZE = (1280, 720)
HFLIP = False                 # set True if left/right are swapped
VFLIP = False                 # set True if the camera is mounted upside down
DETECT_LOW_SCORE = 0.5        # below this = no face at all (silence)
DETECT_GOOD_SCORE = 0.7       # low..good = partial/turned face -> "look at camera"
MIN_FACE_FRACTION = 0.16      # face width / frame width below this -> "come closer"
CENTER_TOLERANCE = 0.18       # horizontal offset fraction before "move left/right"
EDGE_MARGIN_PX = 8            # face box touching frame edge -> "full face in frame"
MIN_BRIGHTNESS = 55           # mean gray of face crop below this -> "too dark"
DARK_FRAME_MEAN = 60          # whole frame darker than this + no face ->
                              # "no face detected, move to brighter place"
NO_FACE_PROMPT_SECONDS = 20   # how often that prompt may repeat
MIN_SHARPNESS = 40            # Laplacian variance below this = motion blur (skip frame)
STABLE_FRAMES = 3             # consecutive good frames before capturing
MATCH_ATTEMPTS = 5            # embed/match tries before "not recognized"
MIRRORED = True               # True if user sees camera like a mirror

# Blink-to-scan (liveness): after the face is stable, require one real
# blink (open -> closed -> open) before embedding/matching.
BLINK_REQUIRED = False        # disabled for now (eye detector unreliable)
BLINK_TIMEOUT_SECONDS = 5     # re-prompt "blink to scan" after this long
BLINK_MAX_TIMEOUTS = 2        # after this many prompts, scan anyway (the
                              # eye detector can miss blinks with glasses)
EYE_CASCADE_FILE = BASE_DIR / "haarcascade_eye.xml"

# ---------------- PIR motion sensor ----------------
PIR_ENABLED = True            # False = camera always on (no sensor wired)
PIR_GPIO = 17                 # BCM number — physical pin 11
CAMERA_OFF_AFTER_SECONDS = 30 # no motion & no face this long -> camera off

# ---------------- Behaviour ----------------
DEBOUNCE_SECONDS = 60          # ignore repeat matches of same student (from notes)
MIN_MINUTES_BEFORE_CHECKOUT = 20  # don't turn a lingering check-in into a checkout.
                                  # Contract allows overwriting checkOut on every
                                  # later sighting; this guard only skips sightings
                                  # within N minutes of checkIn. Set 0 to disable.

# ---------------- Audio ----------------
# Explicit ALSA device by NAME — no .asoundrc needed, survives reboots
# and card-number shuffles. The startup also forces volume to 100%.
AUDIO_DEVICE = "plughw:Headphones,0"
PROMPTS_DIR = BASE_DIR / "prompts"

# Neural TTS (Piper) — used by generate_prompts.sh for the fixed prompts
# and live (with caching) for dynamic text like student names.
PIPER_VOICE = "en_US-amy-medium"   # natural female; try en_US-lessac-medium too
VOICES_DIR = BASE_DIR / "voices"
TTS_CACHE_DIR = PROMPTS_DIR / "cache"
PROMPT_COOLDOWN_SECONDS = 4    # min gap before repeating the same voice prompt
GLOBAL_PROMPT_GAP_SECONDS = 1.5  # min gap between ANY two prompts (no overlap)
ESPEAK_VOICE = "en+f3"
ESPEAK_SPEED = "150"
ESPEAK_AMPLITUDE = "190"   # 0-200, default 100 — louder for the PAM8403

# ---------------- Timetable override cleanup ----------------
# CRs mark a period cancelled/postponed/room-changed by writing a doc to
# `timetable_overrides`; nothing ever deleted it once the class it
# referred to had ended. The Pi (already the one always-on service with
# Admin SDK access) sweeps this collection periodically and removes any
# record whose class end time has passed, so the collection only ever
# holds what's still relevant. Kept short (2 min) since this is meant to
# feel close to real-time, not "eventually consistent".
OVERRIDE_CLEANUP_SECONDS = 120

# ---------------- Offline operation ----------------
QUEUE_FILE = BASE_DIR / "pending_events.json"
QUEUE_RETRY_SECONDS = 30
CACHE_FILE = BASE_DIR / "enrollment_cache.json"  # face templates on disk —
                                                 # matching works offline
NET_STARTUP_ATTEMPTS = 2      # tries before declaring offline at boot
                              # (kiosk gets ready fast; the background
                              # reconnect announces when hotspot arrives)
NET_RECONNECT_SECONDS = 30    # background retry interval when offline
NET_PROBE_TIMEOUT = 6         # hard cap per startup network attempt
WRITE_TIMEOUT_SECONDS = 8     # hard cap per attendance write (then queue)
FIRESTORE_TIMEOUT = 10        # seconds per Firestore call (fail fast offline)
