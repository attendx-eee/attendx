"""Live camera preview for positioning/debugging (headless Pi).

Streams MJPEG with the detected face box, score, and the exact guidance
decision main.py would make. Open in a browser on your laptop:

    http://<pi-ip>:8080

The attendance service must be stopped first (camera is exclusive):
    sudo systemctl stop attendx-pi
    ./venv/bin/python preview.py
"""

import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2
from picamera2 import Picamera2
from libcamera import Transform

import config
import face_matcher

PORT = 8080

GOOD = (80, 220, 80)
BAD = (60, 60, 230)


def quality_label(face, score, frame) -> tuple[str, bool]:
    """Same decision tree as main.guide(), but returns a label to draw."""
    frame_h, frame_w = frame.shape[:2]
    x, y, w, h = face
    if score < config.DETECT_GOOD_SCORE:
        return "look straight at camera", False
    m = config.EDGE_MARGIN_PX
    if x <= m or y <= m or x + w >= frame_w - m or y + h >= frame_h - m:
        return "full face into frame", False
    if w < config.MIN_FACE_FRACTION * frame_w:
        return "come closer", False
    offset = ((x + w / 2) - frame_w / 2) / frame_w
    if abs(offset) > config.CENTER_TOLERANCE:
        return "move left" if offset > 0 else "move right", False
    gray = cv2.cvtColor(frame[y : y + h, x : x + w], cv2.COLOR_BGR2GRAY)
    if gray.mean() < config.MIN_BRIGHTNESS:
        return "too dark", False
    if cv2.Laplacian(gray, cv2.CV_64F).var() < config.MIN_SHARPNESS:
        return "hold still (blur)", False
    return "GOOD - would scan", True


class Stream(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path != "/":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header(
            "Content-Type", "multipart/x-mixed-replace; boundary=frame"
        )
        self.end_headers()
        try:
            while True:
                frame = picam.capture_array()
                detected = detector.largest_face(frame)
                if detected is None:
                    cv2.putText(frame, "no face", (20, 45),
                                cv2.FONT_HERSHEY_SIMPLEX, 1.2, BAD, 3)
                else:
                    (x, y, w, h), score = detected
                    label, ok = quality_label((x, y, w, h), score, frame)
                    color = GOOD if ok else BAD
                    cv2.rectangle(frame, (x, y), (x + w, y + h), color, 3)
                    cv2.putText(frame, f"{label}  ({score:.2f})", (20, 45),
                                cv2.FONT_HERSHEY_SIMPLEX, 1.2, color, 3)
                _, jpg = cv2.imencode(".jpg", frame,
                                      [cv2.IMWRITE_JPEG_QUALITY, 75])
                self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n\r\n")
                self.wfile.write(jpg.tobytes())
                self.wfile.write(b"\r\n")
                time.sleep(0.08)  # ~12 fps
        except (BrokenPipeError, ConnectionResetError):
            pass  # viewer closed the tab

    def log_message(self, *args):  # silence request spam
        pass


if __name__ == "__main__":
    picam = Picamera2()
    picam.configure(picam.create_video_configuration(
        main={"size": config.FRAME_SIZE, "format": "RGB888"},
        transform=Transform(hflip=config.HFLIP, vflip=config.VFLIP),
    ))
    picam.start()
    time.sleep(1.5)
    detector = face_matcher.FaceDetector()
    print(f"Preview running: http://<pi-ip>:{PORT}  (Ctrl+C to stop)")
    ThreadingHTTPServer(("0.0.0.0", PORT), Stream).serve_forever()
