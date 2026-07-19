"""Crop calibration: finds the crop expansion + color order that best
matches how the app enrolled your face.

Usage (attendance service must be stopped):
    sudo systemctl stop attendx-pi
    ./venv/bin/python tune_match.py

Stand in front of the camera looking straight ahead, good lighting.
It captures 12 face frames, tries every crop variant, and prints the
winning settings to paste into config.py.
"""

import itertools
import time

import cv2
import numpy as np
from picamera2 import Picamera2
from libcamera import Transform

import config
import face_matcher
import firestore_client


def main() -> None:
    db = firestore_client.init()
    cache = firestore_client.EnrollmentCache(db)
    cache.refresh()
    enr = cache.snapshot()
    if not enr:
        print("No enrollments in Firestore — enroll a student first.")
        return

    if len(enr) == 1:
        uid, data = next(iter(enr.items()))
    else:
        print("Enrolled students:")
        for u, d in enr.items():
            print(f"  regNo={d.get('regNo')}  name={d.get('name')}  uid={u}")
        reg = input("Enter YOUR regNo: ").strip()
        matches = [(u, d) for u, d in enr.items() if d.get("regNo") == reg]
        if not matches:
            print("regNo not found.")
            return
        uid, data = matches[0]

    print(f"Calibrating against: {data.get('name') or uid}")
    centroid = data["centroid"]
    poses = list((data.get("poses") or {}).values())

    embedder = face_matcher.FaceEmbedder()
    detector = face_matcher.FaceDetector()

    picam = Picamera2()
    picam.configure(picam.create_video_configuration(
        main={"size": config.FRAME_SIZE, "format": "RGB888"},
        transform=Transform(hflip=config.HFLIP, vflip=config.VFLIP),
    ))
    picam.start()
    time.sleep(1.5)

    print("Stand in front of the camera, look straight ahead...")
    frames = []
    while len(frames) < 12:
        frame = picam.capture_array()
        det = detector.largest_face(frame)
        if det is not None and det[1] >= config.DETECT_GOOD_SCORE:
            frames.append((frame.copy(), det[0]))
            print(f"  captured {len(frames)}/12")
            time.sleep(0.25)
    picam.stop()

    def best_sim(embedding: np.ndarray) -> float:
        s = float(np.dot(embedding, centroid))
        for p in poses:
            s = max(s, float(np.dot(embedding, p)))
        return s

    print("Testing crop variants (takes ~1 minute)...")
    results = []
    grid_top = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]
    grid_bottom = [0.0, 0.1, 0.2]
    grid_sides = [0.0, 0.1, 0.2, 0.3]
    for top, bottom, sides, swap in itertools.product(
        grid_top, grid_bottom, grid_sides, [False, True]
    ):
        sims = []
        for frame, box in frames:
            crop = face_matcher.crop_face(frame, box, top, bottom, sides)
            if crop is None:
                continue
            inp = crop[:, :, ::-1].copy() if swap else crop
            sims.append(best_sim(embedder.embed(inp)))
        if sims:
            results.append((float(np.mean(sims)), top, bottom, sides, swap))

    results.sort(reverse=True)
    print("\nTop 10 (mean cosine similarity — higher is better):")
    for m, t, b, s, sw in results[:10]:
        print(f"  {m:.3f}   TOP={t}  BOTTOM={b}  SIDES={s}  SWAP_RGB={sw}")

    m, t, b, s, sw = results[0]
    print("\nPaste into config.py:")
    print(f"  CROP_EXPAND_TOP = {t}")
    print(f"  CROP_EXPAND_BOTTOM = {b}")
    print(f"  CROP_EXPAND_SIDES = {s}")
    print(f"  SWAP_RGB = {sw}")
    if m >= 0.80:
        print(f"\nBest score {m:.3f}: solid — keep MATCH_THRESHOLD = 0.75.")
    elif m >= 0.70:
        print(f"\nBest score {m:.3f}: workable — set MATCH_THRESHOLD = {max(round(m - 0.07, 2), 0.6)}.")
    else:
        print(f"\nBest score {m:.3f}: still low — send this whole output to Claude.")


if __name__ == "__main__":
    main()
