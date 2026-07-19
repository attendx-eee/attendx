"""Firestore access for the Pi (Admin SDK, service account).

Implements the exact write contract from PI_INTEGRATION_NOTES.md:
  - collection `attendance_events`, doc id `{uid}_{yyyy-MM-dd}` (IST date)
  - checkIn written once, never overwritten; checkOut overwritten on
    every later sighting; always set(..., merge=True)
  - never writes status/present/late — the app derives those
Plus an on-disk retry queue so a hotspot dropout doesn't lose events.
"""

import json
import logging
import os
import threading
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import numpy as np
import firebase_admin
from firebase_admin import credentials, firestore

import config

log = logging.getLogger("firestore")

_IST = ZoneInfo(config.TIMEZONE)


def init() -> firestore.client:
    if not firebase_admin._apps:  # idempotent — safe across restarts
        cred = credentials.Certificate(str(config.SERVICE_ACCOUNT_FILE))
        firebase_admin.initialize_app(cred)
    return firestore.client()


def local_date_str(dt: datetime | None = None) -> str:
    """yyyy-MM-dd in college local time (IST), zero-padded."""
    return (dt or datetime.now(_IST)).astimezone(_IST).strftime("%Y-%m-%d")


# --------------------------------------------------------------------------
# Enrollment cache
# --------------------------------------------------------------------------

class EnrollmentCache:
    """uid -> {centroid, poses, regNo, name}. Refreshed periodically because
    the app adapts embeddings over time."""

    def __init__(self, db) -> None:
        self.db = db
        self.data: dict[str, dict] = {}
        self.lock = threading.Lock()

    def refresh(self) -> None:
        """Pull enrollments from Firestore (raises if offline), then
        persist them to disk so matching keeps working without network."""
        t = config.FIRESTORE_TIMEOUT
        names = {}
        try:
            for doc in self.db.collection(config.STUDENTS_COLLECTION).get(timeout=t):
                names[doc.id] = (doc.to_dict() or {}).get("name", "")
        except Exception as exc:
            log.warning("could not load student names: %s", exc)

        fresh: dict[str, dict] = {}
        for doc in self.db.collection(config.ENROLLMENTS_COLLECTION).get(timeout=t):
            d = doc.to_dict() or {}
            centroid = d.get("centroid")
            if not centroid:
                continue
            c = np.asarray(centroid, dtype=np.float32)
            n = np.linalg.norm(c)
            if n > 0:
                c = c / n
            poses = {}
            for pose, emb in (d.get("embeddings") or {}).items():
                try:
                    p = np.asarray(emb, dtype=np.float32)
                    pn = np.linalg.norm(p)
                    poses[pose] = p / pn if pn > 0 else p
                except Exception:
                    continue
            uid = d.get("uid") or doc.id
            fresh[uid] = {
                "centroid": c,
                "poses": poses,
                "regNo": str(d.get("regNo", "")),
                "name": names.get(uid, ""),
            }

        with self.lock:
            self.data = fresh
        log.info("enrollment cache refreshed: %d students", len(fresh))
        self.save_disk()

    def save_disk(self) -> None:
        """Atomic write of the cache so a power cut can't corrupt it."""
        try:
            with self.lock:
                out = {
                    uid: {
                        "centroid": e["centroid"].tolist(),
                        "poses": {p: v.tolist() for p, v in e["poses"].items()},
                        "regNo": e["regNo"],
                        "name": e["name"],
                    }
                    for uid, e in self.data.items()
                }
            tmp = config.CACHE_FILE.with_suffix(".tmp")
            with open(tmp, "w") as f:
                json.dump(out, f)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, config.CACHE_FILE)
        except Exception as exc:
            log.warning("cache save failed: %s", exc)

    def load_disk(self) -> bool:
        """Load the last-known enrollments (offline startup). True if any."""
        try:
            raw = json.loads(config.CACHE_FILE.read_text())
        except Exception:
            return False
        data = {}
        for uid, e in raw.items():
            data[uid] = {
                "centroid": np.asarray(e["centroid"], dtype=np.float32),
                "poses": {p: np.asarray(v, dtype=np.float32)
                          for p, v in (e.get("poses") or {}).items()},
                "regNo": e.get("regNo", ""),
                "name": e.get("name", ""),
            }
        with self.lock:
            self.data = data
        log.info("enrollment cache loaded from disk: %d students", len(data))
        return len(data) > 0

    def snapshot(self) -> dict[str, dict]:
        with self.lock:
            return dict(self.data)

    def start_auto_refresh(self) -> None:
        def loop() -> None:
            while True:
                time.sleep(config.CACHE_REFRESH_HOURS * 3600)
                try:
                    self.refresh()
                except Exception as exc:
                    log.warning("cache refresh failed: %s", exc)

        threading.Thread(target=loop, daemon=True).start()


# --------------------------------------------------------------------------
# Attendance events
# --------------------------------------------------------------------------

class EventWriter:
    def __init__(self, db) -> None:
        self.db = db
        self.queue_lock = threading.Lock()

    def record(self, uid: str, reg_no: str) -> str:
        """Write a sighting. Returns 'checkin', 'checkout', 'skipped'
        (checkout guard) or 'queued' (offline)."""
        now = datetime.now(timezone.utc)
        try:
            return self._write(uid, reg_no, event_time=None, now=now)
        except Exception as exc:
            log.warning("write failed, queueing: %s", exc)
            self._enqueue(uid, reg_no, now)
            return "queued"

    def _write(self, uid: str, reg_no: str,
               event_time: datetime | None, now: datetime) -> str:
        """event_time=None -> SERVER_TIMESTAMP (live); a datetime is used
        when replaying queued offline events."""
        date_str = local_date_str(event_time or now)
        ref = self.db.collection(config.ATTENDANCE_COLLECTION).document(
            f"{uid}_{date_str}"
        )
        snap = ref.get(timeout=config.FIRESTORE_TIMEOUT)
        existing = snap.to_dict() or {}
        ts = event_time if event_time is not None else firestore.SERVER_TIMESTAMP

        payload = {
            "uid": uid,
            "regNo": reg_no,
            "date": date_str,
            "device": config.DEVICE_ID,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }

        if not (snap.exists and "checkIn" in existing):
            payload["checkIn"] = ts  # first sighting only — never overwrite
            result = "checkin"
        else:
            check_in = existing.get("checkIn")
            gap_min = config.MIN_MINUTES_BEFORE_CHECKOUT
            if gap_min > 0 and check_in is not None:
                ref_time = event_time or now
                try:
                    if (ref_time - check_in).total_seconds() < gap_min * 60:
                        return "skipped"
                except TypeError:
                    pass  # unexpected checkIn type — just record the checkout
            payload["checkOut"] = ts  # every later sighting overwrites
            result = "checkout"

        ref.set(payload, merge=True, timeout=config.FIRESTORE_TIMEOUT)
        return result

    # ---------------- offline queue ----------------

    def _load_queue(self) -> list[dict]:
        try:
            return json.loads(config.QUEUE_FILE.read_text())
        except Exception:
            return []

    def _save_queue(self, items: list[dict]) -> None:
        # Atomic write: a power cut mid-write can never corrupt the queue —
        # the old file stays intact until the new one is fully on disk.
        tmp = config.QUEUE_FILE.with_suffix(".tmp")
        with open(tmp, "w") as f:
            json.dump(items, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, config.QUEUE_FILE)

    def _enqueue(self, uid: str, reg_no: str, when: datetime) -> None:
        with self.queue_lock:
            items = self._load_queue()
            items.append({"uid": uid, "regNo": reg_no, "ts": when.isoformat()})
            self._save_queue(items)

    def start_retry_loop(self) -> None:
        def loop() -> None:
            while True:
                time.sleep(config.QUEUE_RETRY_SECONDS)
                with self.queue_lock:
                    items = self._load_queue()
                if not items:
                    continue
                remaining = []
                for item in items:
                    try:
                        when = datetime.fromisoformat(item["ts"])
                        self._write(item["uid"], item["regNo"],
                                    event_time=when,
                                    now=datetime.now(timezone.utc))
                        log.info("replayed queued event for %s", item["uid"])
                    except Exception:
                        remaining.append(item)
                with self.queue_lock:
                    self._save_queue(remaining)

        threading.Thread(target=loop, daemon=True).start()
