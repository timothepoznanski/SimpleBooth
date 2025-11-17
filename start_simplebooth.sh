#!/usr/bin/env bash
export GNOME_KEYRING_CONTROL=""
export SSH_AUTH_SOCK=""

# Nettoyer agressivement les instances Chromium existantes et leurs fichiers de lock
echo "Nettoyage des instances Chromium..."
pkill -9 -f chromium 2>/dev/null || true
pkill -9 -f chrome 2>/dev/null || true
killall -9 chromium 2>/dev/null || true
killall -9 chrome 2>/dev/null || true

# Supprimer les fichiers de lock Chromium et le user-data-dir temporaire
rm -f ~/.config/chromium/SingletonLock 2>/dev/null || true
rm -f ~/.config/chromium/SingletonSocket 2>/dev/null || true
rm -rf ~/.config/chromium/Singleton* 2>/dev/null || true
rm -rf /tmp/chromium-user-data 2>/dev/null || true

# Attendre plus longtemps que les processus se terminent
sleep 5

# Vérifier que Chromium n'est plus en cours d'exécution
if pgrep -f chromium >/dev/null || pgrep -f chrome >/dev/null; then
    echo "Erreur: Impossible de tuer Chromium, tentative finale..."
    pkill -9 -f chromium || true
    pkill -9 -f chrome || true
    sleep 2
    if pgrep -f chromium >/dev/null || pgrep -f chrome >/dev/null; then
        echo "Erreur critique: Impossible de tuer Chromium"
        exit 1
    fi
fi

echo "Chromium nettoyé avec succès."

xset s off dpms s noblank
unclutter -idle 0.1 -root &
cd "/home/admin/SimpleBooth"
source "/home/admin/SimpleBooth/venv/bin/activate"
python app.py &
FLASK_PID=$!

echo "Flask lancé avec PID: $FLASK_PID"

sleep 5

# Vérifier que l'app Flask répond avant de lancer Chromium
if ! curl -s --max-time 5 http://localhost:5000/ >/dev/null; then
    echo "Erreur: L'application Flask ne répond pas sur localhost:5000"
    kill $FLASK_PID 2>/dev/null || true
    exit 1
fi

echo "Application Flask prête, lancement de Chromium..."

chromium --kiosk --no-sandbox --disable-infobars \
  --disable-features=TranslateUI,Translate \
  --disable-translate \
  --disable-extensions \
  --disable-plugins \
  --disable-notifications \
  --disable-popup-blocking \
  --disable-default-apps \
  --disable-background-mode \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  --disable-field-trial-config \
  --disable-ipc-flooding-protection \
  --no-default-browser-check \
  --no-first-run \
  --disable-component-update \
  --lang=fr \
  --user-data-dir=/tmp/chromium-user-data \
  http://localhost:5000 &

CHROMIUM_PID=$!

echo "Chromium lancé avec PID: $CHROMIUM_PID"

# Fonction de nettoyage
cleanup() {
    echo "Nettoyage des processus..."
    kill $CHROMIUM_PID 2>/dev/null || true
    kill $FLASK_PID 2>/dev/null || true
    wait
    exit 0
}

# Gérer les signaux d'arrêt proprement
trap cleanup SIGTERM SIGINT

# Attendre que Chromium se termine
wait $CHROMIUM_PID

echo "Chromium s'est arrêté, arrêt du service."
cleanup
