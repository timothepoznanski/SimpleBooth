#!/usr/bin/env bash
# ---------------------------------------------------------------------
# SimpleBooth Kiosk Installer Script (allégé)
# Auteur : Les Frères Poulain (modifié par Assistant)
# Description : Configuration automatisée pour Raspberry Pi OS
# ---------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# -------------------- Couleurs et Affichage --------------------
# Vérifier si le terminal supporte les couleurs
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
  # Terminal avec support couleur
  declare -A COLORS=(
    [R]="\033[0;31m"   # Rouge
    [G]="\033[0;32m"   # Vert
    [Y]="\033[1;33m"   # Jaune
    [C]="\033[0;36m"   # Cyan
    [B]="\033[0;34m"   # Bleu
    [P]="\033[0;35m"   # Pourpre
    [W]="\033[1;37m"   # Blanc
    [GRAY]="\033[0;90m" # Gris
    [N]="\033[0m"      # Reset
    [BOLD]="\033[1m"   # Gras
    [DIM]="\033[2m"    # Atténué
  )
else
  # Terminal sans couleur - utiliser des caractères simples
  declare -A COLORS=(
    [R]="" [G]="" [Y]="" [C]="" [B]="" [P]="" [W]="" [GRAY]="" [N]="" [BOLD]="" [DIM]=""
  )
fi

# Fonctions d'affichage simplifiées (sans codes couleur problématiques)
header()  { echo; echo "╭─────────────────────────────────────────────────────────────╮"; echo "│ $* │"; echo "╰─────────────────────────────────────────────────────────────╯"; echo; }
step()    { echo "▶ $*"; }
log()     { echo "  ℹ $*"; }
ok()      { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*"; }
error()   { echo "  ✗ $*" >&2; exit 1; }
progress() { echo "  ⟳ $*"; }

#!/usr/bin/env bash
# ---------------------------------------------------------------------
# SimpleBooth Kiosk Installer Script (allégé)
# Auteur : Les Frères Poulain (modifié par Assistant)
# Description : Configuration automatisée pour Raspberry Pi OS
# ---------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# -------------------- Variables --------------------
# Déduit le répertoire de l'application d'après l'emplacement du script
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$APP_DIR/venv"
INSTALL_USER="${SUDO_USER:-${USER}}"
HOME_DIR="$(eval echo ~${INSTALL_USER})"

# -------------------- Fonctions --------------------
require_root() { 
  (( EUID == 0 )) || error "Exécutez en root (sudo)"
  [[ "$(uname -m)" =~ ^(arm|aarch64) ]] || error "Ce script est conçu pour Raspberry Pi (ARM)"
  [[ -n "$SUDO_USER" ]] || error "Utilisez sudo, pas su ou root direct"
}

# -------------------- Main rapide --------------------
main_quick() {
  require_root
  
  echo "🚀 Installation rapide SimpleBooth"
  echo "=================================="
  
  # Mise à jour système
  echo "📦 Mise à jour système..."
  apt-get update && apt-get upgrade -y
  
  # Installation dépendances
  echo "🔧 Installation dépendances..."
  apt-get install -y python3 python3-venv python3-pip build-essential libcap2-bin libcap-dev xserver-xorg xinit x11-xserver-utils unclutter chromium-browser
  
  # Configuration Python
  echo "🐍 Configuration Python..."
  python3 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install -r "$APP_DIR/requirements.txt"
  deactivate
  
  # Configuration kiosk
  echo "🖥️ Configuration kiosk..."
  mkdir -p "$HOME_DIR/.config/autostart"
  cp "$APP_DIR/start_simplebooth.sh" "$HOME_DIR/"
  chmod +x "$HOME_DIR/start_simplebooth.sh"
  
  cat > "$HOME_DIR/.config/autostart/simplebooth.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SimpleBooth Kiosk
Exec=$HOME_DIR/start_simplebooth.sh
X-GNOME-Autostart-enabled=true
Comment=SimpleBooth Kiosk mode
EOF
  
  # Configuration systemd
  echo "⚙️ Configuration systemd..."
  cp "$APP_DIR/systemd/simplebooth-kiosk.service" /etc/systemd/system/
  sed -i "s/User=.*/User=$INSTALL_USER/" /etc/systemd/system/simplebooth-kiosk.service
  sed -i "s/Group=.*/Group=$INSTALL_USER/" /etc/systemd/system/simplebooth-kiosk.service
  sed -i "s|Environment=HOME=.*|Environment=HOME=$HOME_DIR|" /etc/systemd/system/simplebooth-kiosk.service
  sed -i "s|ExecStart=.*|ExecStart=$HOME_DIR/start_simplebooth.sh|" /etc/systemd/system/simplebooth-kiosk.service
  
  systemctl daemon-reload
  systemctl enable simplebooth-kiosk.service
  
  # Autologin
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $INSTALL_USER --noclear %I \$TERM
EOF
  
  echo "✅ Installation terminée !"
  echo "🔄 Redémarrage recommandé"
}

# Mode rapide si argument --quick
if [[ "${1:-}" == "--quick" ]]; then
  main_quick
  exit 0
fi
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
  local pkgs=(python3 python3-venv python3-pip build-essential libcap2-bin libcap-dev xserver-xorg xinit x11-xserver-utils unclutter)
  [[ -n "$CHROMIUM_PKG" ]] && pkgs+=("$CHROMIUM_PKG")
  step "Installation des dépendances"
  log "${#pkgs[@]} paquets à installer"
  
  progress "Installation de ${#pkgs[@]} paquets système..."
  apt-get install -y "${pkgs[@]}" || error "Échec installation des dépendances"
  
  # Vérification critique
  progress "Vérification des paquets critiques..."
  for pkg in python3 python3-venv; do
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
    pip install -r "$APP_DIR/requirements.txt" || error "Échec installation requirements.txt"
  else
    progress "Installation des paquets Python (flask, pillow, numpy)..."
    pip install flask pillow numpy || error "Échec installation paquets Python"
  fi
  
  deactivate
  ok "Environnement Python configuré avec succès"
}

setup_kiosk() {
  step "Configuration du mode kiosk"
  local autostart="$HOME_DIR/.config/autostart"
  mkdir -p "$autostart"
  cat > "$HOME_DIR/start_simplebooth.sh" <<EOF
#!/usr/bin/env bash
xset s off dpms s noblank
unclutter -idle 0.1 -root &
cd "$APP_DIR"
source "$VENV_DIR/bin/activate"
python app.py &
sleep 5
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
  cat > "$autostart/simplebooth.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SimpleBooth Kiosk
Exec=$HOME_DIR/start_simplebooth.sh
X-GNOME-Autostart-enabled=true
Comment=SimpleBooth Kiosk mode
EOF
  ok "Mode kiosk configuré avec succès"
}

setup_systemd() {
  step "Configuration des services système"
  # S'assurer que le script de démarrage existe
  [[ -f "$HOME_DIR/start_simplebooth.sh" ]] || error "Script de démarrage manquant"
  progress "Création du service systemd..."
  
  cat > /etc/systemd/system/simplebooth-kiosk.service <<EOF
[Unit]
Description=SimpleBooth Kiosk
After=graphical.target
Wants=graphical.target

[Service]
Type=simple
User=$INSTALL_USER
Group=$INSTALL_USER
Environment=DISPLAY=:0
Environment=HOME=$HOME_DIR
ExecStart=$HOME_DIR/start_simplebooth.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF
  
  progress "Rechargement des services systemd..."
  systemctl daemon-reload || error "Échec rechargement systemd"
  progress "Activation du service SimpleBooth..."
  systemctl enable simplebooth-kiosk.service || error "Échec activation service"
  ok "Services système configurés avec succès"
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
  echo
  
  if confirm "Update system et install dependencies? (o/N)"; then
    update_system
    install_dependencies
  else
    log "Update et install ignored"
  fi

  if confirm "Configurer écran Waveshare 7\" DSI? (o/N)"; then 
    configure_waveshare
  else 
    WAVE_ENABLED=false
    log "Configuration Waveshare ignorée"
  fi
  
  # Configuration du port série pour l'imprimante
  if confirm "Configurer le port série GPIO (/dev/ttyAMA0)? (o/N)"; then
    configure_serial
  else
    log "Configuration port série ignorée"
  fi
  
  setup_python_env
  setup_kiosk
  setup_systemd
  
  echo
  header "✨ INSTALLATION TERMINÉE ✨"
  warn "Redémarrage recommandé pour activer tous les services"
  confirm "Redémarrer maintenant? (o/N)" && reboot
}

main "$@"
