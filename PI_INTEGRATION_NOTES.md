# Raspberry Pi Integration Notes — AttendX

The Pi is the attendance sensor: it recognizes a student's face at the
entrance and writes **raw check-in / check-out timestamps** to Firestore.
It does NOT decide present/absent/late — the app computes that from the
timetable. Keep the Pi dumb and the rules in one place (the app).

All names below must match `lib/core/constants/app_config.dart`.

---

## 1. Collection the Pi WRITES to

**Collection:** `attendance_events`
**Document ID:** `{uid}_{yyyy-MM-dd}`  → e.g. `aB3xYz12_2026-07-04`
(one document per student per day — never create a second doc for the
same student+date)

| Field       | Type      | Rule                                                          |
|-------------|-----------|---------------------------------------------------------------|
| `uid`       | string    | Firebase Auth UID of the student (see §3)                     |
| `regNo`     | string    | Student register number (digits only) — for human debugging   |
| `date`      | string    | `yyyy-MM-dd` in **local college time** (IST), zero-padded     |
| `checkIn`   | timestamp | First face match of the day. **Write once, never overwrite.** |
| `checkOut`  | timestamp | Latest exit match. **Overwrite on every exit.**               |
| `device`    | string    | Pi identifier, e.g. `pi-gate-1`                               |
| `updatedAt` | timestamp | `SERVER_TIMESTAMP` on every write                             |

Write pattern (idempotent, safe to retry):

```python
from firebase_admin import firestore

db = firestore.client()
doc_id = f"{uid}_{date_str}"              # date_str = time.strftime('%Y-%m-%d')
ref = db.collection("attendance_events").document(doc_id)

snap = ref.get()
payload = {
    "uid": uid,
    "regNo": reg_no,
    "date": date_str,
    "device": "pi-gate-1",
    "updatedAt": firestore.SERVER_TIMESTAMP,
}
if not (snap.exists and "checkIn" in (snap.to_dict() or {})):
    payload["checkIn"] = firestore.SERVER_TIMESTAMP   # first sighting only
else:
    payload["checkOut"] = firestore.SERVER_TIMESTAMP  # every later sighting

ref.set(payload, merge=True)              # ALWAYS merge=True
```

Rules the Pi must follow:
- **Always `set(..., merge=True)`** — never plain `set` (it would erase `checkIn`).
- **Never write `status`, `present`, or `late`** — the app derives these.
- Debounce: ignore repeat matches of the same student within ~60 seconds.
- Clock: enable NTP. `SERVER_TIMESTAMP` protects the timestamps, but the
  `date` string comes from the Pi's local clock — a wrong date puts the
  event on the wrong day.
- Date boundary: use local (IST) date, not UTC.

## 2. Collections the Pi READS from (read-only!)

- `student_face_enrollments/{uid}` — face templates:
  - `embeddings`: map of pose → 192-float array.
    **Iterate the map — never hardcode the key names.** Enrollment used
    to write exactly five (`front`, `left`, `right`, `up`, `down`); the
    scanning enrollment added `farLeft` and `farRight`, and may add more.
    `front` is still always present, and a staff template may contain
    only that one. Code that looked for specific keys is how the app's
    own face verification broke.
  - `quality` (v3+): `{meanQuality, sampleCount, binsCovered, band}` —
    the enrollment scorecard. Useful for spotting thin templates before
    they start failing at the gate; not needed for matching.
  - `centroid`: fused 192-float array — **match against this first** (cheapest),
    fall back to per-pose for the top candidates (same logic as the app's
    `AdaptiveFaceService`: cosine similarity, accept ≥ 0.75, require a
    0.04 margin over the runner-up)
  - `uid`, `regNo` — copy these into the event doc
  - Model: MobileFaceNet, 112×112 input, output normalized to unit length.
    The Pi must use the **same .tflite model** as the app
    (`assets/models/mobilefacenet.tflite`), same preprocessing
    (pixel − 127.5) / 127.5.
  - The app now builds every embedding (enrollment templates AND live
    login captures) with flip test-time-augmentation: run inference on
    the face crop AND its horizontal mirror, average the two raw
    192-float outputs, then normalize. This makes stored templates more
    stable/canonical, which should only help match scores against a
    plain single-frame Pi capture — but for best accuracy the Pi should
    eventually do the same (one extra inference on `cv2.flip(face, 1)`
    per check-in, averaged in before normalizing). Not required for
    compatibility, just a recommended upgrade.
  - Refresh cached templates periodically — the app **adapts embeddings
    over time** (adaptive learning), so re-download at least daily.
- `students/{uid}` — only if extra profile data is needed.

The Pi must NOT write to: `students`, `student_face_enrollments`,
`timetables`, `timetable_overrides`, `notifications`.

## 3. How the app interprets events (do not re-implement on the Pi)

- Timetable source: `timetables/{department}/{academicYear}/{year}/{Weekday}`
  (e.g. `timetables/EEE/2026-2027/3/Monday`), periods with `startTime`/`endTime` as `"HH:mm"`.
- Grace rules (in `AppConfig`):
  - `onTimeGraceMinutes = 10` — check-in ≤ 10 min after first period start = on time.
  - `presentGraceMinutes = 20` — the 10–20 min band is **present but late**
    (late students appear on the admin insights graph).
  - Check-in before the last period's end still counts present for the day;
    after it = absent.
- Days with no scheduled periods (Sundays, holidays, empty timetable) are
  excluded from totals.
- CR timetable overrides (`timetable_overrides`) adjust what students see;
  day-level attendance uses the base timetable.

## 4. Firebase setup for the Pi

- Use a dedicated **service account** (firebase-admin SDK), not a user login.
- Recommended security rules shape:
  - `attendance_events`: client apps **read only their own** (`resource.data.uid == request.auth.uid`); writes only via the service account (admin SDK bypasses rules — keep client writes blocked).
  - `student_face_enrollments`: readable by signed-in clients (needed for face login), writes by owner + admin SDK.
- Composite indexes: none needed for Pi queries (`uid ==` and `date ==` are single-field). The app's notification stream (`studentUid ==` + `orderBy createdAt`) needs one — Firestore logs a one-click creation link on first run.

## 5. Quick test checklist

1. Enroll a student in the app → confirm `student_face_enrollments/{uid}` exists with `centroid`.
2. Simulate a Pi check-in (script above) at 9:05 for a 9:00 first period → student dashboard "Today's Attendance" shows Checked In; month stats count a present day; not late (≤10 min).
3. Same at 9:15 → present + appears in Admin → Attendance Insights "Late students today" and the 7-day graph.
4. No event that day → counted absent in monthly stats.
5. Check-out event → "Completed" chip on the student dashboard card.
