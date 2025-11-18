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

disable_keyring() {
  step "Désactivation du trousseau GNOME Keyring"

  local keyring_pkgs=(gnome-keyring libpam-gnome-keyring seahorse)
  local to_purge=()

  for pkg in "${keyring_pkgs[@]}"; do
    dpkg -l "$pkg" &>/dev/null && to_purge+=("$pkg")
  done

  if (( ${#to_purge[@]} > 0 )); then
    progress "Suppression des paquets ${to_purge[*]}..."
    if ! apt-get purge -y "${to_purge[@]}"; then
      warn "Impossible de purger tous les paquets keyring"
    fi
  else
    log "Aucun paquet keyring à supprimer"
  fi

  progress "Neutralisation de l'autostart keyring..."
  mkdir -p "$AUTOSTART_DIR"
  local autostart_entries=(gnome-keyring-secrets.desktop gnome-keyring-ssh.desktop gnome-keyring-pkcs11.desktop gnome-keyring-gpg.desktop)
  for desktop_file in "${autostart_entries[@]}"; do
    if [[ -f "/etc/xdg/autostart/$desktop_file" ]]; then
      cat > "$AUTOSTART_DIR/$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=${desktop_file%.desktop}
Exec=/usr/bin/true
Hidden=true
X-GNOME-Autostart-enabled=false
NoDisplay=true
EOF
      chown "$INSTALL_USER:$INSTALL_USER" "$AUTOSTART_DIR/$desktop_file"
    fi
  done

  progress "Nettoyage des trousseaux existants..."
  rm -rf "$HOME_DIR/.local/share/keyrings"
  mkdir -p "$HOME_DIR/.local/share"
  chown -R "$INSTALL_USER:$INSTALL_USER" "$HOME_DIR/.local"

  ok "GNOME Keyring désactivé"
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
  
  # Activer enable_uart pour activer le mini-UART (ttyS0) sur GPIO 14/15
  if ! grep -q '^enable_uart=1' "$file"; then
    echo "enable_uart=1" >> "$file"
    log "enable_uart=1 ajouté dans config.txt"
  else
    log "enable_uart déjà activé"
  fi
  
  # Forcer le mini-UART sur les GPIO 14/15 (si Bluetooth utilise UART0)
  if ! grep -q '^dtoverlay=miniuart-bt' "$file"; then
    echo "dtoverlay=miniuart-bt" >> "$file"
    log "miniuart-bt configuré - Bluetooth utilisera le mini-UART, ttyS0 sera l'UART0"
  else
    log "miniuart-bt déjà configuré"
  fi
  
  # Désactiver la console série dans cmdline.txt
  progress "Désactivation de la console série..."
  local cmdline_files=(/boot/firmware/cmdline.txt /boot/cmdline.txt)
  local cmdline_file=""
  for f in "${cmdline_files[@]}"; do 
    [[ -f "$f" ]] && { cmdline_file="$f"; break; }
  done
  
  if [[ -n "$cmdline_file" ]]; then
    # Sauvegarde du fichier original
    cp "$cmdline_file" "${cmdline_file}.bak.$(date +%Y%m%d)" 2>/dev/null || true
    log "Sauvegarde créée: ${cmdline_file}.bak.$(date +%Y%m%d)"
    
    # Retirer console=serial0,115200 et console=ttyS0,115200
    sed -i 's/console=serial0,[0-9]\+ //g' "$cmdline_file"
    sed -i 's/console=ttyS0,[0-9]\+ //g' "$cmdline_file"
    sed -i 's/console=ttyAMA0,[0-9]\+ //g' "$cmdline_file"
    log "Console série désactivée dans cmdline.txt"
  else
    warn "cmdline.txt introuvable - désactivation manuelle requise"
  fi
  
  # Désactiver le service getty sur les ports série
  progress "Désactivation des services getty sur ports série..."
  systemctl stop serial-getty@ttyS0.service 2>/dev/null || true
  systemctl disable serial-getty@ttyS0.service 2>/dev/null || true
  systemctl stop serial-getty@ttyAMA0.service 2>/dev/null || true
  systemctl disable serial-getty@ttyAMA0.service 2>/dev/null || true
  log "Services getty désactivés"
  
  # Ajouter l'utilisateur au groupe dialout pour accès au port série
  progress "Ajout de l'utilisateur $INSTALL_USER au groupe dialout..."
  usermod -a -G dialout "$INSTALL_USER" 2>/dev/null || true
  log "Utilisateur ajouté au groupe dialout"
  
  # Mettre à jour la configuration de l'application pour utiliser ttyAMA0
  progress "Mise à jour de la configuration de l'imprimante..."
  if [[ -f "$APP_DIR/config.json" ]]; then
    # Mettre à jour le port dans config.json existant
    sed -i 's|"printer_port": "/dev/ttyS0"|"printer_port": "/dev/ttyAMA0"|g' "$APP_DIR/config.json"
    log "config.json mis à jour avec ttyAMA0"
  else
    log "Pas de config.json - les paramètres par défaut seront utilisés"
  fi
  
  ok "Port série GPIO configuré avec succès"
  warn "Redémarrage REQUIS pour libérer le port série"
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
  setup_kiosk
  setup_systemd
  
  # Créer les dossiers nécessaires pour l'application
  progress "Création des dossiers de l'application..."
  mkdir -p "$APP_DIR/photos" "$APP_DIR/static" "$APP_DIR/templates"
  chown -R "$INSTALL_USER:$INSTALL_USER" "$APP_DIR"
  ok "Dossiers créés avec succès"

  disable_keyring
  
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
