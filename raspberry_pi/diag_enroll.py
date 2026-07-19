"""Diagnose WHERE the face-match mismatch comes from.

Checks (1) is the enrollment data internally coherent, and (2) is the
Pi's own pipeline self-consistent. Run with the enrolled person standing
in front of the camera:

    sudo systemctl stop attendx-pi
    ./venv/bin/python diag_enroll.py
"""

import time

import numpy as np
from picamera2 import Picamera2
from libcamera import Transform

import config
import face_matcher
import firestore_client


def cos(a, b):
    return round(float(np.dot(a, b)), 3)


def main() -> None:
    db = firestore_client.init()
    cache = firestore_client.EnrollmentCache(db)
    cache.refresh()
    enr = cache.snapshot()
    uid, data = next(iter(enr.items()))
    print(f"\n=== ENROLLMENT DATA: {data.get('name') or uid} ===")

    # raw (pre-normalization) norms straight from Firestore
    doc = db.collection(config.ENROLLMENTS_COLLECTION).document(uid).get().to_dict()
    raw_centroid = np.asarray(doc.get("centroid"), dtype=np.float32)
    print(f"centroid: len={len(raw_centroid)} raw_norm={np.linalg.norm(raw_centroid):.4f}")
    for pose, emb in (doc.get("embeddings") or {}).items():
        v = np.asarray(emb, dtype=np.float32)
        print(f"pose {pose:6s}: len={len(v)} raw_norm={np.linalg.norm(v):.4f}")

    centroid = data["centroid"]
    poses = data["poses"]
    print("\ncoherence (normalized cosine, expect 0.7+ within one person):")
    for pose, v in poses.items():
        print(f"  centroid vs {pose:6s}: {cos(centroid, v)}")
    keys = list(poses)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            print(f"  {keys[i]:6s} vs {keys[j]:6s}: {cos(poses[keys[i]], poses[keys[j]])}")

    print("\n=== PI PIPELINE SELF-TEST ===")
    embedder = face_matcher.FaceEmbedder()
    detector = face_matcher.FaceDetector()
    picam = Picamera2()
    picam.configure(picam.create_video_configuration(
        main={"size": config.FRAME_SIZE, "format": "RGB888"},
        transform=Transform(hflip=config.HFLIP, vflip=config.VFLIP),
    ))
    picam.start()
    time.sleep(1.5)

    print("capturing 4 face frames — stand still, look straight...")
    embs = []
    while len(embs) < 4:
        frame = picam.capture_array()
        det = detector.largest_face(frame)
        if det is None or det[1] < config.DETECT_GOOD_SCORE:
            continue
        crop = face_matcher.crop_face(frame, det[0])
        if crop is None:
            continue
        inp = crop[:, :, ::-1].copy() if config.SWAP_RGB else crop
        embs.append(embedder.embed(inp))
        print(f"  captured {len(embs)}/4")
        time.sleep(0.5)
    picam.stop()

    print("\nself-similarity (same person, seconds apart — expect 0.9+):")
    for i in range(len(embs)):
        for j in range(i + 1, len(embs)):
            print(f"  capture{i} vs capture{j}: {cos(embs[i], embs[j])}")

    print("\nlive vs enrollment (expect 0.75+ if same person + pipelines match):")
    for i, e in enumerate(embs):
        best_pose = max(poses, key=lambda p: cos(e, poses[p])) if poses else None
        pose_s = cos(e, poses[best_pose]) if best_pose else None
        print(f"  capture{i}: vs centroid={cos(e, centroid)}"
              f"  best pose ({best_pose})={pose_s}")

    print("\nInterpretation:")
    print("  coherence low (<0.6)      -> enrollment data is bad: re-enroll in app")
    print("  self-similarity low (<0.85)-> Pi capture unstable: lighting/focus")
    print("  both high, live-vs-enroll low -> pipeline mismatch or different person")


if __name__ == "__main__":
    main()
