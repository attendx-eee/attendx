"""Face embedding + matching.

Must mirror the app's AdaptiveFaceService exactly:
  - MobileFaceNet .tflite, 112x112 input, preprocessing (pixel-127.5)/127.5
  - output L2-normalized to unit length
  - match against each student's fused `centroid` first, then fall back to
    per-pose embeddings for the top candidates
  - accept cosine similarity >= 0.75 with a 0.04 margin over the runner-up
"""

import logging
import math

import cv2
import numpy as np

import config

log = logging.getLogger("face")

# tflite interpreter: tflite-runtime (py<=3.11), ai-edge-litert (newer
# Debian Trixie / py3.12+), or full tensorflow — whichever is installed.
try:
    from tflite_runtime.interpreter import Interpreter
except ImportError:
    try:
        from ai_edge_litert.interpreter import Interpreter
    except ImportError:
        from tensorflow.lite import Interpreter  # last resort


class FaceEmbedder:
    def __init__(self) -> None:
        self.interpreter = Interpreter(model_path=str(config.MODEL_FILE))
        self.interpreter.allocate_tensors()
        self.input_detail = self.interpreter.get_input_details()[0]
        self.output_detail = self.interpreter.get_output_details()[0]
        _, self.in_h, self.in_w, _ = self.input_detail["shape"]

    def embed(self, face_bgr: np.ndarray) -> np.ndarray:
        """BGR face crop -> unit-length embedding (float32[192])."""
        rgb = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2RGB)
        # Cubic to match the app (img.copyResize interpolation: cubic)
        rgb = cv2.resize(rgb, (self.in_w, self.in_h),
                         interpolation=cv2.INTER_CUBIC)
        inp = (rgb.astype(np.float32) - 127.5) / 127.5
        inp = np.expand_dims(inp, 0)

        self.interpreter.set_tensor(self.input_detail["index"], inp)
        self.interpreter.invoke()
        out = self.interpreter.get_tensor(self.output_detail["index"])[0]

        norm = np.linalg.norm(out)
        return out / norm if norm > 0 else out


class FaceDetector:
    """YuNet detector (bundled with OpenCV >= 4.5.4)."""

    def __init__(self) -> None:
        self.size = config.FRAME_SIZE
        # Low threshold on purpose: weak detections (partial/turned faces)
        # are used to voice-guide the user; main.py decides what's "good".
        self.det = cv2.FaceDetectorYN.create(
            str(config.YUNET_FILE), "", self.size,
            config.DETECT_LOW_SCORE, 0.3, 5000,
        )

    def largest_face(self, frame_bgr: np.ndarray):
        """Returns ((x, y, w, h), score, eyes) of the largest face, or None.
        eyes = ((right_eye_x, y), (left_eye_x, y)) from YuNet landmarks."""
        h, w = frame_bgr.shape[:2]
        if (w, h) != self.size:
            self.det.setInputSize((w, h))
            self.size = (w, h)
        _, faces = self.det.detect(frame_bgr)
        if faces is None or len(faces) == 0:
            return None
        best = max(faces, key=lambda f: f[2] * f[3])
        score = float(best[-1])
        x, y, fw, fh = best[:4]
        eyes = ((float(best[4]), float(best[5])),
                (float(best[6]), float(best[7])))
        x0 = max(int(x), 0)
        y0 = max(int(y), 0)
        x1 = min(int(x + fw), w)
        y1 = min(int(y + fh), h)
        if x1 - x0 < 20 or y1 - y0 < 20:
            return None
        return (x0, y0, x1 - x0, y1 - y0), score, eyes


def crop_face(frame: np.ndarray, box, top: float | None = None,
              bottom: float | None = None, sides: float | None = None):
    """Expand the raw detector box (fractions of box size) and crop.
    Defaults come from config — tune_match.py passes explicit values."""
    top = config.CROP_EXPAND_TOP if top is None else top
    bottom = config.CROP_EXPAND_BOTTOM if bottom is None else bottom
    sides = config.CROP_EXPAND_SIDES if sides is None else sides
    x, y, w, h = box
    H, W = frame.shape[:2]
    x0 = max(int(x - w * sides), 0)
    x1 = min(int(x + w * (1 + sides)), W)
    y0 = max(int(y - h * top), 0)
    y1 = min(int(y + h * (1 + bottom)), H)
    if x1 - x0 < 20 or y1 - y0 < 20:
        return None
    return frame[y0:y1, x0:x1]


def aligned_crop(frame: np.ndarray, box, eyes,
                 top: float | None = None, bottom: float | None = None,
                 sides: float | None = None):
    """Rotate so the eyes are level (the same alignment the app performs
    at enrollment), then crop. Alignment is a standard FRS accuracy
    booster — tilted faces otherwise score much lower."""
    try:
        (rx, ry), (lx, ly) = eyes
        angle = math.degrees(math.atan2(ly - ry, lx - rx))
    except Exception:
        angle = 0.0
    if abs(angle) >= 3.0:  # ignore negligible tilt
        h, w = frame.shape[:2]
        cx = box[0] + box[2] / 2.0
        cy = box[1] + box[3] / 2.0
        m = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)
        frame = cv2.warpAffine(frame, m, (w, h))
    return crop_face(frame, box, top, bottom, sides)


class EyeDetector:
    """Eyes open/closed via Haar cascade — used for blink-to-scan liveness."""

    def __init__(self) -> None:
        import os

        candidates = []
        try:
            candidates.append(cv2.data.haarcascades + "haarcascade_eye.xml")
        except AttributeError:
            pass
        candidates += [
            "/usr/share/opencv4/haarcascades/haarcascade_eye.xml",
            "/usr/share/opencv/haarcascades/haarcascade_eye.xml",
            str(config.EYE_CASCADE_FILE),
        ]
        for path in candidates:
            if os.path.exists(path):
                self.cascade = cv2.CascadeClassifier(path)
                if not self.cascade.empty():
                    log.info("eye cascade: %s", path)
                    return
        raise FileNotFoundError(
            "haarcascade_eye.xml not found — run: curl -L -o "
            f"{config.EYE_CASCADE_FILE} https://raw.githubusercontent.com/"
            "opencv/opencv/master/data/haarcascades/haarcascade_eye.xml"
        )

    def eyes_open(self, face_bgr: np.ndarray) -> bool:
        gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)  # more robust in uneven lighting
        h, w = gray.shape
        roi = gray[: int(h * 0.6)]  # eyes live in the upper part of the face
        min_side = max(w // 12, 12)
        eyes = self.cascade.detectMultiScale(
            roi, scaleFactor=1.1, minNeighbors=3, minSize=(min_side, min_side)
        )
        return len(eyes) >= 1


class BlinkGate:
    """Passes once we see eyes open (2+ frames) -> closed -> open again."""

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.open_frames = 0
        self.saw_closed = False
        self.deadline: float | None = None

    def update(self, eyes_open: bool, now: float) -> bool:
        """Feed one frame's eye state. Returns True when a blink completed."""
        if self.deadline is None:
            self.deadline = now + config.BLINK_TIMEOUT_SECONDS
        if not self.saw_closed:
            if eyes_open:
                self.open_frames += 1
            elif self.open_frames >= 2:
                self.saw_closed = True  # eyes were open, now closed
        elif eyes_open:
            return True  # reopened — blink complete
        return False

    def timed_out(self, now: float) -> bool:
        return self.deadline is not None and now > self.deadline


def _cosine(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.dot(a, b))  # both unit length


def top_scores(embedding: np.ndarray, enrollments: dict, k: int = 3) -> list:
    """[(score, 'name/regNo/uid'), ...] best-first — for diagnostics."""
    scored = sorted(
        (
            (_cosine(embedding, e["centroid"]), uid)
            for uid, e in enrollments.items()
            if e.get("centroid") is not None
        ),
        reverse=True,
    )
    out = []
    for s, uid in scored[:k]:
        e = enrollments[uid]
        label = e.get("name") or e.get("regNo") or uid
        out.append((round(s, 3), label))
    return out


def identify(embedding: np.ndarray, enrollments: dict) -> dict:
    """EXACT port of the app's AdaptiveFaceService.identify():
    - Stage 1: rank all candidates by centroid similarity (prefilter only)
    - Stage 2: per-pose scoring on the top-K shortlist — the best pose
      score is what decides acceptance (threshold 0.75)
    - margin (0.04) is only measured against OTHER users, and is skipped
      entirely when <= 1 student is enrolled
    """
    if not enrollments:
        return {"uid": None, "score": -1.0, "pose": "", "margin": 0.0,
                "accepted": False}

    ranked = sorted(
        (
            (_cosine(embedding, e["centroid"]), uid)
            for uid, e in enrollments.items()
            if e.get("centroid") is not None
        ),
        reverse=True,
    )
    shortlist = [uid for _, uid in ranked[: config.POSE_FALLBACK_TOP_K]]

    best_uid: str | None = None
    best_pose = ""
    best_score = -1.0
    second_best_other = -1.0

    for uid in shortlist:
        poses = enrollments[uid].get("poses") or {}
        cand_best, cand_pose = -1.0, ""
        for pose, vec in poses.items():
            s = _cosine(embedding, vec)
            if s > cand_best:
                cand_best, cand_pose = s, pose
        if cand_best > best_score:
            if best_uid is not None and best_uid != uid:
                second_best_other = max(second_best_other, best_score)
            best_score, best_pose, best_uid = cand_best, cand_pose, uid
        elif uid != best_uid:
            second_best_other = max(second_best_other, cand_best)

    margin = 1.0 if second_best_other < 0 else best_score - second_best_other
    accepted = (
        best_score >= config.MATCH_THRESHOLD
        and (len(enrollments) <= 1 or margin >= config.MATCH_MARGIN)
    )
    return {"uid": best_uid if accepted else None, "score": best_score,
            "pose": best_pose, "margin": margin, "accepted": accepted}


def match(embedding: np.ndarray, enrollments: dict) -> str | None:
    """Returns the matching uid or None (thin wrapper over identify)."""
    return identify(embedding, enrollments)["uid"]
