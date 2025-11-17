#!/usr/bin/env bash

# Nettoyage complet de Chromium
pkill -9 chromium 2>/dev/null || true
pkill -9 chrome 2>/dev/null || true
rm -rf /tmp/chromium-user-data 2>/dev/null || true
rm -rf ~/.config/chromium/Singleton* 2>/dev/null || true
sleep 3

# Désactiver l'écran de veille
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Masquer le curseur
unclutter -idle 0.1 -root &

# Démarrer Flask
cd /home/admin/SimpleBooth
source venv/bin/activate
python app.py &

# Attendre que Flask soit prêt
sleep 8

# Lancer Chromium en mode kiosk
chromium --kiosk --no-sandbox --disable-infobars \
  --disable-translate \
  --no-first-run \
  --disable-session-crashed-bubble \
  --disable-infobars \
  http://localhost:5000
