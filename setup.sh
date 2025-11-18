#!/usr/bin/env bash
# ---------------------------------------------------------------------
# SimpleBooth Kiosk Installer Script (allégé)
# Auteur : Les Frères Poulain (modifié par Assistant)
# Description : Configuration automatisée pour Raspberry Pi OS
# ---------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# Fonctions d'affichage simplifiées
header()  { echo; echo "╭─────────────────────────────────────────────────────────────╮"; echo "│ $* │"; echo "╰─────────────────────────────────────────────────────────────╯"; echo; }
step()    { echo "▶ $*"; }
log()     { echo "  ℹ $*"; }
ok()      { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*"; }
error()   { echo "  ✗ $*" >&2; exit 1; }
progress() { echo "  ⟳ $*"; }

# -------------------- Variables --------------------
# Déduit le répertoire de l'application d'après l'emplacement du script
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$APP_DIR/venv"
INSTALL_USER="${SUDO_USER:-${USER}}"
HOME_DIR="$(eval echo ~${INSTALL_USER})"
AUTOSTART_DIR="$HOME_DIR/.config/autostart"
WAVE_ENABLED=true

# Vérification système critique
check_system() {
  [[ "$(uname -m)" =~ ^(arm|aarch64) ]] || error "Ce script est conçu pour Raspberry Pi (ARM)"
  [[ -n "$SUDO_USER" ]] || error "Utilisez sudo, pas su ou root direct"
}

# Détection du paquet Chromium
if apt-cache show chromium &>/dev/null; then
  CHROMIUM_PKG="chromium"
elif apt-cache show chromium-browser &>/dev/null; then
  CHROMIUM_PKG="chromium-browser"
else
  warn "Paquet Chromium introuvable, installation ignorée"
  CHROMIUM_PKG=""
fi

# -------------------- Trap erreurs --------------------
trap 'error "Échec à la ligne $LINENO"' ERR

# -------------------- Fonctions --------------------
require_root() { 
  (( EUID == 0 )) || error "Exécutez en root (sudo)"
  check_system
}
confirm() { 
  local prompt="${1:-Continuer? (o/N)}" 
  local default="${2:-N}" 
  local resp
  # Affichage simple sans codes couleur dans le prompt
  printf "❓ %s " "$prompt"
  read -r resp
  [[ "${resp:-$default}" =~ ^[Oo]$ ]]
}

update_system() {
  step "Mise à jour du système"
  
  progress "Téléchargement de la liste des paquets..."
  apt-get update || error "Échec téléchargement liste paquets"
  progress "Installation des mises à jour système..."
  apt-get upgrade -y || error "Échec mise à jour système"
  
  ok "Système mis à jour avec succès"
}

install_dependencies() {
  local pkgs=(python3 python3-venv python3-pip build-essential libcap2-bin libcap-dev xserver-xorg xinit x11-xserver-utils unclutter curl git)
  [[ -n "$CHROMIUM_PKG" ]] && pkgs+=("$CHROMIUM_PKG")
  step "Installation des dépendances"
  log "${#pkgs[@]} paquets à installer"
  
  progress "Installation de ${#pkgs[@]} paquets système..."
  apt-get install -y "${pkgs[@]}" || error "Échec installation des dépendances"
  
  # Vérification critique
  progress "Vérification des paquets critiques..."
  for pkg in python3 python3-venv curl; do
    dpkg -l "$pkg" &>/dev/null || error "Échec installation $pkg"
  done
  
  ok "Toutes les dépendances sont installées"
}

configure_waveshare() {
  [[ "$WAVE_ENABLED" == false ]] && { log "Configuration Waveshare ignorée"; return; }
  step "Configuration écran Waveshare DSI 7\""
  progress "Recherche du fichier config.txt..."
  local cfg=(/boot/firmware/config.txt /boot/config.txt) file=""
  for f in "${cfg[@]}"; do 
    [[ -f "$f" ]] && { file="$f"; break; }
  done
  [[ -n "$file" ]] || { error "config.txt introuvable - système non supporté"; }

  progress "Sauvegarde de la configuration..."
  cp "$file" "${file}.bak.$(date +%Y%m%d)"
  log "Sauvegarde créée: ${file}.bak.$(date +%Y%m%d)"

  # Ajouter dtoverlay avec rotation intégrée (ex: 270°)
  grep -q '^dtoverlay=vc4-kms-dsi-waveshare-panel' "$file" && \
    sed -i '/dtoverlay=vc4-kms-dsi-waveshare-panel/d' "$file"
  cat >> "$file" <<EOF

# Waveshare 7" DSI - SimpleBooth
dtoverlay=vc4-kms-dsi-waveshare-panel,7_0_inchC,i2c1
EOF
  ok "Écran Waveshare configuré avec succès"
}

configure_serial() {
  step "Configuration du port série GPIO"
  progress "Recherche du fichier config.txt..."
  local cfg=(/boot/firmware/config.txt /boot/config.txt) file=""
  for f in "${cfg[@]}"; do 
    [[ -f "$f" ]] && { file="$f"; break; }
  done
  [[ -n "$file" ]] || { error "config.txt introuvable - système non supporté"; }

  progress "Configuration du port série..."
  
  # Activer le port série UART (comme raspi-config)
  if ! grep -q '^dtparam=uart0=on' "$file"; then
    echo "dtparam=uart0=on" >> "$file"
    log "UART activé dans config.txt"
  else
    log "UART déjà activé"
  fi
  
  ok "Port série GPIO configuré avec succès"
  warn "Redémarrage requis pour activer le port série"
}

setup_python_env() {
  step "Configuration environnement Python"
  command -v python3 >/dev/null || error "Python 3 non installé"
  
  progress "Création de l'environnement virtuel..."
  python3 -m venv "$VENV_DIR" || error "Échec création environnement virtuel"
  
  source "$VENV_DIR/bin/activate" || error "Échec activation venv"
  
  progress "Mise à jour de pip..."
  pip install --upgrade pip || error "Échec mise à jour pip"
  
  if [[ -f "$APP_DIR/requirements.txt" ]]; then
    progress "Installation depuis requirements.txt..."
    pip install -r "$APP_DIR/requirements.txt" || {
      warn "Certains paquets ont échoué, tentative d'installation des paquets essentiels..."
      pip install flask pillow numpy pyserial python-escpos || error "Échec installation paquets essentiels"
    }
  else
    progress "Installation des paquets Python essentiels..."
    pip install flask pillow numpy pyserial python-escpos || error "Échec installation paquets Python"
  fi
  
  deactivate
  ok "Environnement Python configuré avec succès"
}

setup_kiosk() {
  step "Configuration du mode kiosk"
  
  # Vérifier que CHROMIUM_PKG est défini
  [[ -z "$CHROMIUM_PKG" ]] && CHROMIUM_PKG="chromium"
  
  mkdir -p "$AUTOSTART_DIR"
  
  # Créer le script de démarrage
  cat > "$HOME_DIR/start_simplebooth.sh" <<EOF
#!/usr/bin/env bash

# === SETUP ===
# Tuer les processus chromium existants pour éviter les conflits
pkill -f chromium
sleep 2

# Désactiver l'écran de veille et le verrouillage
xset s off
xset -dpms
xset s noblank

# Cacher le curseur de la souris
unclutter -idle 0.1 -root &

# Attendre que l'application Flask soit disponible
# (l'app est lancée par le service simplebooth-app.service)
echo "Attente du démarrage de l'application Flask..."
for i in {1..30}; do
  if curl -s http://localhost:5000 >/dev/null 2>&1; then
    echo "Application Flask prête!"
    break
  fi
  echo "Tentative \$i/30..."
  sleep 1
done

# === BROWSER ===
# Lancer Chromium en mode kiosk
exec $CHROMIUM_PKG --kiosk --no-sandbox --disable-infobars \
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
  http://localhost:5000
EOF
  chmod +x "$HOME_DIR/start_simplebooth.sh"
  chown "$INSTALL_USER:$INSTALL_USER" "$HOME_DIR/start_simplebooth.sh"
  
  cat > "$AUTOSTART_DIR/simplebooth.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SimpleBooth Kiosk
Exec=$HOME_DIR/start_simplebooth.sh
X-GNOME-Autostart-enabled=true
Comment=SimpleBooth Kiosk mode
EOF
  chown "$INSTALL_USER:$INSTALL_USER" "$AUTOSTART_DIR/simplebooth.desktop"
  
  ok "Mode kiosk configuré avec succès"
}

disable_keyring() {
  step "Désactivation du keyring GNOME"
  
  progress "Désactivation COMPLÈTE du keyring..."
  
  # Méthode RADICALE: Renommer les fichiers système d'autostart
  if [[ -f /etc/xdg/autostart/gnome-keyring-secrets.desktop ]]; then
    mv /etc/xdg/autostart/gnome-keyring-secrets.desktop /etc/xdg/autostart/gnome-keyring-secrets.desktop.disabled 2>/dev/null || true
    log "gnome-keyring-secrets.desktop désactivé"
  fi
  
  if [[ -f /etc/xdg/autostart/gnome-keyring-ssh.desktop ]]; then
    mv /etc/xdg/autostart/gnome-keyring-ssh.desktop /etc/xdg/autostart/gnome-keyring-ssh.desktop.disabled 2>/dev/null || true
    log "gnome-keyring-ssh.desktop désactivé"
  fi
  
  if [[ -f /etc/xdg/autostart/gnome-keyring-pkcs11.desktop ]]; then
    mv /etc/xdg/autostart/gnome-keyring-pkcs11.desktop /etc/xdg/autostart/gnome-keyring-pkcs11.desktop.disabled 2>/dev/null || true
    log "gnome-keyring-pkcs11.desktop désactivé"
  fi
  
  # Créer aussi les fichiers de masquage au niveau utilisateur (double sécurité)
  mkdir -p "$HOME_DIR/.config/autostart"
  
  for keyring_file in gnome-keyring-secrets gnome-keyring-ssh gnome-keyring-pkcs11; do
    cat > "$HOME_DIR/.config/autostart/${keyring_file}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${keyring_file}
Exec=/bin/true
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=false
EOF
  done

  # Variables d'environnement
  if ! grep -q "GNOME_KEYRING_CONTROL" "$HOME_DIR/.bashrc" 2>/dev/null; then
    cat >> "$HOME_DIR/.bashrc" <<EOF

# Désactiver GNOME Keyring
unset GNOME_KEYRING_CONTROL
unset GNOME_KEYRING_PID
unset SSH_AUTH_SOCK
unset GPG_AGENT_INFO
export GNOME_KEYRING_CONTROL=
EOF
  fi

  # Script pour tuer le keyring au démarrage de X
  cat > "$HOME_DIR/.xsessionrc" <<'EOF'
#!/bin/bash
# Tuer tous les processus keyring
pkill -f gnome-keyring-daemon 2>/dev/null
EOF
  chmod +x "$HOME_DIR/.xsessionrc"
  
  chown -R "$INSTALL_USER:$INSTALL_USER" "$HOME_DIR/.config" "$HOME_DIR/.bashrc" "$HOME_DIR/.xsessionrc" 2>/dev/null || true
  
  ok "Keyring GNOME complètement désactivé (fichiers système renommés)"
}

setup_systemd() {
  step "Configuration des services système"
  
  # S'assurer que les permissions sont correctes sur APP_DIR
  chown -R "$INSTALL_USER:$INSTALL_USER" "$APP_DIR"
  
  progress "Création du service Flask app..."
  
  cat > /etc/systemd/system/simplebooth-app.service <<EOF
[Unit]
Description=SimpleBooth Flask App
After=network.target

[Service]
Type=simple
User=$INSTALL_USER
Group=$INSTALL_USER
WorkingDirectory=$APP_DIR
Environment=PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=$VENV_DIR/bin/python $APP_DIR/app.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  
  progress "Création du service kiosk..."
  cat > /etc/systemd/system/simplebooth-kiosk.service <<EOF
[Unit]
Description=SimpleBooth Kiosk
After=graphical.target simplebooth-app.service
Wants=graphical.target
Requires=simplebooth-app.service

[Service]
Type=simple
User=$INSTALL_USER
Group=$INSTALL_USER
Environment=DISPLAY=:0
Environment=HOME=$HOME_DIR
Environment=XAUTHORITY=$HOME_DIR/.Xauthority
ExecStart=$HOME_DIR/start_simplebooth.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF
  
  progress "Rechargement des services systemd..."
  systemctl daemon-reload || error "Échec rechargement systemd"
  
  progress "Activation des services SimpleBooth..."
  systemctl enable simplebooth-app.service || error "Échec activation service app"
  systemctl enable simplebooth-kiosk.service || error "Échec activation service kiosk"
  
  ok "Services système configurés avec succès"
  
  # Configuration autologin
  progress "Configuration de la connexion automatique..."
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $INSTALL_USER --noclear %I \$TERM
EOF
  ok "Connexion automatique activée"
}

# -------------------- Main --------------------
main() {
  require_root
  
  # En-tête stylisé
  header " SIMPLEBOOTH INSTALLER "
  echo "Auteur: Les Frères Poulain"
  echo "Version: Raspberry Pi OS"
  echo "Répertoire: $APP_DIR"
  echo "Utilisateur: $INSTALL_USER"
  echo
  
  if confirm "Update system et install dependencies? (o/N)"; then
    update_system
    install_dependencies
  else
    log "Update et install ignorés"
  fi

  if confirm "Configurer écran Waveshare 7\" DSI? (o/N)"; then 
    configure_waveshare
  else 
    WAVE_ENABLED=false
    log "Configuration Waveshare ignorée"
  fi
  
  # Configuration du port série pour l'imprimante
  if confirm "Configurer le port série GPIO? (o/N)"; then
    configure_serial
  else
    log "Configuration port série ignorée"
  fi
  
  setup_python_env
  disable_keyring
  setup_kiosk
  setup_systemd
  
  # Créer les dossiers nécessaires pour l'application
  progress "Création des dossiers de l'application..."
  mkdir -p "$APP_DIR/photos" "$APP_DIR/static" "$APP_DIR/templates"
  chown -R "$INSTALL_USER:$INSTALL_USER" "$APP_DIR"
  ok "Dossiers créés avec succès"
  
  echo
  header "✨ INSTALLATION TERMINÉE ✨"
  log "Les services sont configurés et s'activeront au prochain démarrage:"
  log "  - simplebooth-app.service  (Flask application)"
  log "  - simplebooth-kiosk.service (Mode kiosk Chromium)"
  echo
  warn "Redémarrage REQUIS pour activer tous les services"
  confirm "Redémarrer maintenant? (o/N)" && reboot
}

main "$@"
