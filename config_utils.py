import os
import json
import logging

PHOTOS_FOLDER = 'photos'
CONFIG_FILE = 'config.json'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}

DEFAULT_CONFIG = {
    'footer_text': 'Photobooth',
    'timer_seconds': 3,
    'printer_enabled': True,
    'printer_port': '/dev/ttyAMA0',
    'printer_baudrate': 9600,
    'print_resolution': 384
}

logger = logging.getLogger(__name__)

def ensure_directories():
    """Create photos folder if missing"""
    logger.info(f"[DEBUG] Création du dossier photos: {PHOTOS_FOLDER}")
    os.makedirs(PHOTOS_FOLDER, exist_ok=True)
    logger.info(f"[DEBUG] Dossier créé - Photos: {os.path.exists(PHOTOS_FOLDER)}")

def load_config():
    """Load configuration from JSON"""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    return DEFAULT_CONFIG.copy()

def save_config(config_data):
    """Save configuration to JSON"""
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(config_data, f, indent=2, ensure_ascii=False)
