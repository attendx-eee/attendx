# AttendX Raspberry Pi — Complete Setup Guide (fresh install)

Hardware: **Pi 4 Model B**, Raspberry Pi OS (Debian Trixie), **Camera
Module 3** (CSI ribbon), speaker via **PAM8403 amp** on the 3.5mm jack,
headless, Wi-Fi from a phone hotspot.

The Pi records raw check-in/check-out timestamps to `attendance_events`;
the app derives present/late/absent and sends notifications. Contract:
`../PI_INTEGRATION_NOTES.md`.

Kiosk flow: voice-guide the student into position (come closer / move
left / full face / lighting) → "blink your eyes to scan" (liveness) →
match against enrolled faces from Firestore → announce check-in/out.

---

## 0. Flash the OS (headless)

In Raspberry Pi Imager's ⚙ settings before writing the SD card:
- hostname `raspberrypi`, **enable SSH**, set username + password
- Wi-Fi = your phone hotspot's name + password, country IN

## 1. Find the Pi & connect VS Code

1. Hotspot on → Pi auto-connects. IP from the phone's connected-devices
   list, or `ping raspberrypi.local` from the laptop.
2. VS Code → **Remote - SSH** extension → `Ctrl+Shift+P` → Connect to
   Host → `<username>@<IP>` → open folder `~/attendx-pi` (create it:
   `mkdir ~/attendx-pi`). Terminal + files are now on the Pi.

## 2. Copy the project + secrets

From the laptop (in the `attendx.v1.1` repo folder):

```
scp -r raspberry_pi/* <username>@<IP>:~/attendx-pi/
scp assets/models/mobilefacenet.tflite <username>@<IP>:~/attendx-pi/
scp <path-to>/serviceAccountKey.json  <username>@<IP>:~/attendx-pi/
```

- `serviceAccountKey.json`: Firebase Console → ⚙ Project settings →
  Service accounts → Generate new private key → **rename to exactly
  `serviceAccountKey.json`**. Never commit it.
- `mobilefacenet.tflite` must be the same file the app uses.

## 3. Run setup (one command, safe to re-run)

```bash
cd ~/attendx-pi && bash setup.sh
```

Installs everything (picamera2, OpenCV, firebase-admin, tflite
interpreter, TTS), downloads the face + eye detector models, generates
voice prompts, points audio at the 3.5mm jack, sets IST + NTP, and
installs the boot service for **whatever user you're logged in as**
(the service won't start until the key + model files exist).

## 4. Checks

```bash
aplay prompts/starting.wav        # hear "Attendance system ready"
rpicam-hello --list-cameras       # imx708 listed
```

No sound? `aplay -l` must show a `Headphones` card — if missing, ensure
`dtparam=audio=on` in `/boot/firmware/config.txt`, reboot, re-run setup.

### Speaker wiring (lesson learned!)

Power the PAM8403 from a **separate 5V source** (phone charger / power
bank), NOT the Pi's 5V pin — the Pi's rail injects noise (garbled audio)
and wiring slips can kill the amp. The aux cable already provides the
shared ground. Keep the volume pot ≈ halfway; it clips near max.

## 5. Calibrate face matching (once — important!)

The app enrolls faces with ML Kit (phone); the Pi detects with YuNet.
Their face boxes differ, which wrecks similarity scores unless the crop
is calibrated:

```bash
./venv/bin/python tune_match.py
```

Stand in front, look straight, good lighting. Paste the printed
`CROP_EXPAND_*` / `SWAP_RGB` values into `config.py`, and adjust
`MATCH_THRESHOLD` if it tells you to.

## 6. Test, then go live

```bash
./venv/bin/python main.py         # watch logs, try a scan
# happy? Ctrl+C, then:
sudo systemctl start attendx-pi   # runs at every boot from now on
journalctl -u attendx-pi -f       # live logs
```

Logs show every match attempt with similarity scores, and
`event checkin/checkout for <uid>` on success.

### Live camera preview (debugging)

```bash
sudo systemctl stop attendx-pi
./venv/bin/python preview.py      # open http://<pi-ip>:8080 in browser
```

Shows the camera with the face box + the exact guidance decision
(red = what it would say, green = "would scan").

## 7. End-to-end test checklist

1. Enrolled student scans at 9:05 (9:00 first period) → dashboard
   Checked In, on time, notification fires.
2. Scan at 9:15 → present but late (Admin → Attendance Insights).
3. Unenrolled person → "Face not recognized."
4. Photo of a face → rejected (no blink).
5. Second scan >20 min later → check-out → "Completed" chip.
6. Hotspot off during scan → "will sync automatically" → back on →
   `replayed queued event` in logs, doc appears.
7. New student enrolled in app → `sudo systemctl restart attendx-pi`
   (or wait ≤6 h cache refresh) before their first scan.

## 8. Tuning (config.py)

`MATCH_THRESHOLD` (accept score), `CROP_EXPAND_*` + `SWAP_RGB` (from
tune_match.py), `BLINK_REQUIRED` / `BLINK_TIMEOUT_SECONDS`,
`DEBOUNCE_SECONDS` (60), `MIN_MINUTES_BEFORE_CHECKOUT` (20),
`HFLIP`/`VFLIP` (camera mounting), `MIRRORED` (left/right prompts),
`DEVICE_ID` (`pi-gate-1` — unique per gate), `LOG_MATCH_SCORES`
(set False once stable to quiet the logs).

## Firestore rules

Production rules live in `../firestore.rules` — already published. The
Pi's Admin SDK bypasses rules; the app depends on them.
