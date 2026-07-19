#!/bin/bash
# AttendX Pi complete setup — safe to re-run any time.
# Run ON the Raspberry Pi from inside this folder:  bash setup.sh
set -e
cd "$(dirname "$0")"
APP_DIR="$(pwd)"
RUN_USER="$(whoami)"

echo "==> [1/7] apt packages"
sudo apt update
sudo apt install -y python3-venv python3-pip python3-picamera2 \
  python3-opencv python3-numpy espeak-ng alsa-utils sox curl
sudo apt install -y libttspico-utils || true   # nicer TTS voice (non-free)

echo "==> [2/7] python venv + pip packages"
python3 -m venv --system-site-packages venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install firebase-admin
./venv/bin/pip install ai-edge-litert || ./venv/bin/pip install tflite-runtime

echo "==> [3/7] model downloads"
[ -f face_detection_yunet_2023mar.onnx ] || curl -L -o face_detection_yunet_2023mar.onnx \
  "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
[ -f haarcascade_eye.xml ] || curl -L -o haarcascade_eye.xml \
  "https://raw.githubusercontent.com/opencv/opencv/master/data/haarcascades/haarcascade_eye.xml"

echo "==> [4/7] voice prompts"
bash generate_prompts.sh

echo "==> [5/7] audio -> 3.5mm headphone jack"
if aplay -l 2>/dev/null | grep -qi headphones; then
  # By NAME, not number — card indices shuffle between boots
  cat > "$HOME/.asoundrc" <<'ASOUND'
pcm.!default {
    type plug
    slave.pcm "hw:Headphones,0"
}
ctl.!default {
    type hw
    card Headphones
}
ASOUND
  echo "    default audio set to card 'Headphones' (index-proof)"
  amixer -c Headphones sset PCM 100% >/dev/null 2>&1 || true
else
  echo "    WARNING: no Headphones card found. Check 'dtparam=audio=on' in"
  echo "    /boot/firmware/config.txt, reboot, and re-run setup.sh"
fi

echo "==> [6/7] time sync (IST date field depends on this)"
sudo timedatectl set-ntp true
sudo timedatectl set-timezone Asia/Kolkata

echo "==> [7/7] systemd service (user=$RUN_USER, dir=$APP_DIR)"
sed -e "s|@USER@|$RUN_USER|g" -e "s|@DIR@|$APP_DIR|g" attendx-pi.service \
  | sudo tee /etc/systemd/system/attendx-pi.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable attendx-pi
echo "    service installed + enabled (won't start until key & model exist)"

echo
echo "================= NEXT STEPS ================="
if [ ! -f serviceAccountKey.json ]; then
  echo "1. Copy serviceAccountKey.json into $APP_DIR"
fi
if [ ! -f mobilefacenet.tflite ]; then
  echo "2. Copy mobilefacenet.tflite (app's assets/models/) into $APP_DIR"
fi
echo "3. Sound check:        aplay prompts/starting.wav"
echo "4. Camera check:       rpicam-hello --list-cameras"
echo "5. CALIBRATE (once):   ./venv/bin/python tune_match.py"
echo "   -> paste the printed values into config.py"
echo "6. Test run:           ./venv/bin/python main.py"
echo "7. Go live:            sudo systemctl start attendx-pi"
echo "   Live logs:          journalctl -u attendx-pi -f"
echo "   Live camera view:   sudo systemctl stop attendx-pi && ./venv/bin/python preview.py"
echo "                       then open http://<pi-ip>:8080 on your laptop"
echo "=============================================="
