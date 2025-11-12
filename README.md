# 📸 Photobooth Raspberry Pi

> **Application Flask pour photobooth tactile avec flux vidéo temps réel et capture instantanée**

![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)
![Flask](https://img.shields.io/badge/Flask-2.3.3-green.svg)
![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-Compatible-red.svg)
![OpenCV](https://img.shields.io/badge/OpenCV-Support%20USB-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 🎯 Aperçu

Cette application transforme votre Raspberry Pi en un photobooth professionnel avec :
- **Flux vidéo temps réel** en MJPEG 1280x720 (16:9)
- **Support multi-caméras** : Pi Camera ou caméra USB avec détection automatique
- **Interface tactile optimisée** pour écran 7 pouces
- **Capture photo instantanée** directement depuis le flux vidéo
- **Galerie de photos intégrée** avec gestion complète
- **Diaporama automatique** configurable après période d'inactivité
- **Impression thermique** avec configuration avancée et détection des ports
- **Interface d'administration** complète avec contrôles système
- **Mode kiosk automatique** pour démarrage au boot
- **API de statut** pour surveillance de l'imprimante

## 🔧️ Matériel requis

### Matériel supporté

- **Caméra** : 
  - Raspberry Pi Camera (v1, v2, v3, HQ) - Détection automatique
  - Caméra USB standard (webcam) - Détection automatique des ports
- **Écran tactile** : Écran 7 pouces recommandé
- **Imprimante thermique Série** : Compatible avec détection automatique des ports série

### 🛒 Liens d'achat (Affiliation)

Voici une liste de matériel compatible. Les liens sont affiliés et aident à soutenir le projet.

- **Raspberry Pi & Accessoires :**
  - [Raspberry Pi 5](https://amzlink.to/az0ncNNUsGjUH)
  - [Alimentation Raspberry Pi 5](https://amzlink.to/az01ijEmlFqxT)
- **Caméras :**
  - [Pi Camera 3](https://amzlink.to/az0eEXwhnxNvO)
  - [Pi Camera 2.1](https://amzlink.to/az0mgp7Sob1xh)
- **Imprimantes Thermiques :**
  - [Imprimante Thermique (Amazon)](https://amzlink.to/az0wTKS9Bfig2)
  - [Imprimante Thermique (AliExpress)](https://s.click.aliexpress.com/e/_oFyCgCI)
  - [Imprimante Thermique (France)](https://www.gotronic.fr/art-imprimante-thermique-ada597-21349.htm)
- **Écran :**
  - [Ecran Waveshare (Amazon)](https://amzlink.to/az03G4UMruNnc)

### Installation

### 🚀 Installation

L'installation peut se faire de deux manières : automatiquement via un script (recommandé sur Raspberry Pi) ou manuellement.

#### Méthode 1 : Installation automatique avec `setup.sh` (Recommandé)

Un script `setup.sh` est fourni pour automatiser l'ensemble du processus sur un système basé sur Debian (comme Raspberry Pi OS).

1.  **Rendre le script exécutable :**
    ```bash
    chmod +x setup.sh
    ```

2.  **Lancer le script d'installation :**
    ```bash
    ./setup.sh
    ```
    Ce script s'occupe de :
    - Mettre à jour les paquets système.
    - Installer les dépendances système (`libcamera-apps`, `python3-opencv`).
    - Créer un environnement virtuel `venv`.
    - Installer les dépendances Python de `requirements.txt` dans cet environnement.
    - Creer un mode kiosk automatique au demarrage du systeme.

#### Méthode 2 : Installation manuelle

Suivez ces étapes pour une installation manuelle.

1.  **Créer et activer un environnement virtuel :**
    Il est fortement recommandé d'utiliser un environnement virtuel pour isoler les dépendances du projet.
    ```bash
    # Créer l'environnement
    python3 -m venv venv

    # Activer l'environnement
    source venv/bin/activate
    ```
    > Pour quitter l'environnement virtuel, tapez simplement `deactivate`.

2.  **Sur Raspberry Pi, installer les dépendances système :**
    Si vous ne l'avez pas déjà fait, installez les paquets nécessaires pour les caméras.
    ```bash
    sudo apt update
    sudo apt upgrade
    sudo apt install libcamera-apps python3-opencv
    ```

3.  **Installer les dépendances Python :**
    ```bash
    pip install -r requirements.txt
    ```

## Utilisation

1. **Lancer l'application :**
```bash
python3 app.py
```

2. **Accéder à l'interface :**
   - Ouvrir un navigateur sur `http://localhost:5000`
   - Ou depuis un autre appareil : `http://[IP_RASPBERRY]:5000`

3. **Pages disponibles :**
   - `/` : Interface principale du photobooth
   - `/photos` : Galerie de gestion des photos
   - `/admin` : Panneau d'administration complet

## Configuration des caméras

L'application supporte deux types de caméras avec détection automatique :

### Pi Camera (par défaut)

- Utilise `rpicam-vid` pour le flux vidéo temps réel (1280x720@15fps)
- Utilise `rpicam-still` pour les captures haute qualité (2304x1296)
- Détection automatique de la caméra Pi
- Compatible avec toutes les caméras officielles Raspberry Pi

### Caméra USB

- Utilise OpenCV (`cv2`) pour capturer le flux vidéo
- Détection automatique des caméras USB disponibles
- Interface de sélection dans l'administration
- Compatible avec la plupart des webcams USB standard
- Configuration automatique :
  1. Les caméras USB sont détectées automatiquement
  2. Sélection dans le menu déroulant de l'administration
  3. Test de connexion en temps réel

> **Note** : 
> - La détection automatique facilite la configuration
> - Les permissions sont gérées automatiquement par le script `setup.sh`
> - Support du hot-plug (connexion à chaud) des caméras USB

## 📂 Structure des fichiers

Le projet est organisé de manière modulaire pour une meilleure maintenance :

```
SimpleBooth/
├── app.py                 # Application Flask principale (routes, logique)
├── camera_utils.py        # Utilitaires pour la gestion des caméras (Pi Camera, USB)
├── config_utils.py        # Utilitaires pour charger/sauvegarder la configuration
├── ScriptPythonPOS.py     # Script autonome pour l'impression thermique
├── setup.sh               # Script d'installation automatisée pour Raspberry Pi
├── requirements.txt       # Dépendances Python
├── TROUBLESHOOTING.md     # Guide de dépannage
├── static/                # Fichiers statiques
│   └── manifest.json      # Manifest PWA
├── templates/             # Templates HTML (Jinja2)
│   ├── index.html         # Interface principale du photobooth
│   ├── review.html        # Page de prévisualisation et d'action post-capture
│   ├── photos.html        # Galerie de gestion des photos
│   ├── admin.html         # Panneau d'administration avancé
│   └── base.html          # Template de base commun
├── photos/                # Dossier pour les photos (créé au lancement)
└── config.json            # Fichier de configuration (créé au lancement)
```

## Configuration

La configuration est sauvegardée dans `config.json` :

### Général
- `footer_text` : Texte en pied de photo
- `timer_seconds` : Délai avant capture (1-10 secondes)

### Caméra
- `camera_type` : Type de caméra (`picamera` ou `usb`)
- `usb_camera_id` : ID de la caméra USB (0, 1, 2...)

### Impression
- `printer_enabled` : Activer/désactiver l'impression
- `printer_port` : Port série de l'imprimante (détection automatique disponible)
- `printer_baudrate` : Vitesse de communication (9600, 19200, 38400...)
- `print_resolution` : Résolution d'impression (384 standard, 576+ haute qualité)

### Diaporama
- `slideshow_enabled` : Activer/désactiver le diaporama automatique
- `slideshow_delay` : Délai d'inactivité avant affichage du diaporama (10-300 secondes)
- `slideshow_source` : Source des photos pour le diaporama

## 🆕 Nouvelles fonctionnalités

### Galerie de photos intégrée
- Page dédiée `/photos` pour la gestion des photos
- Prévisualisation, téléchargement et suppression
- Réimpression directe depuis la galerie
- Métadonnées complètes (taille, date)

### Administration avancée
- Détection automatique des caméras USB disponibles
- Détection automatique des ports série
- Contrôle du mode kiosk (arrêt/redémarrage)
- Arrêt complet de l'application
- Surveillance en temps réel de l'imprimante

### API et surveillance
- `/api/slideshow` : Données du diaporama
- `/api/printer_status` : État de l'imprimante
- Logs détaillés et gestion d'erreurs améliorée

## Dépannage

- **Caméra non détectée** : Vérifier que la caméra est activée dans `raspi-config`
- **Erreur d'impression** : Utiliser la détection automatique des ports ou vérifier `/dev/ttyAMA0`
- **Mode kiosk bloqué** : Accéder à `/admin` puis utiliser les contrôles système
- **Caméra USB non reconnue** : Vérifier dans `/admin` la liste des caméras détectées
