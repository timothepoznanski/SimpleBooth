#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from flask import Flask, render_template, request, jsonify, send_from_directory, redirect, url_for, flash, Response, abort
import os
import time
import subprocess
import threading
import requests
import logging
import signal
import atexit
import sys
from datetime import datetime
from config_utils import (
    PHOTOS_FOLDER,
    load_config,
    save_config,
    ensure_directories,
)
from camera_utils import UsbCamera, detect_cameras

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'photobooth_secret_key_2024')

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

# Initialiser les dossiers nécessaires
ensure_directories()

def check_printer_status():
    """Vérifier l'état de l'imprimante thermique"""
    try:
        # Vérifier si le module escpos est disponible
        try:
            from escpos.printer import Serial
        except ImportError:
            return {
                'status': 'error',
                'message': 'Module escpos manquant. Installez-le avec: pip install python-escpos',
                'paper_status': 'unknown'
            }
        
        # Récupérer la configuration de l'imprimante
        printer_port = config.get('printer_port', '/dev/ttyS0')
        printer_baudrate = config.get('printer_baudrate', 9600)
        
        # Vérifier si l'imprimante est activée
        if not config.get('printer_enabled', True):
            return {
                'status': 'disabled',
                'message': 'Imprimante désactivée dans la configuration',
                'paper_status': 'unknown'
            }
        
        # Tenter de se connecter à l'imprimante
        try:
            printer = Serial(printer_port, baudrate=printer_baudrate, timeout=1)
            
            # Vérifier l'état du papier (commande ESC/POS standard)
            printer._raw(b'\x10\x04\x01')  # Commande de statut en temps réel
            
            # Lire la réponse (si disponible)
            # Note: Cette partie peut varier selon le modèle d'imprimante
            
            printer.close()
            
            return {
                'status': 'ok',
                'message': 'Imprimante connectée',
                'paper_status': 'ok',
                'port': printer_port,
                'baudrate': printer_baudrate
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'message': f'Erreur de connexion: {str(e)}',
                'paper_status': 'unknown',
                'port': printer_port,
                'baudrate': printer_baudrate
            }
            
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Erreur lors de la vérification: {str(e)}',
            'paper_status': 'unknown'
        }


# Fonction pour détecter les ports série disponibles
def detect_serial_ports():
    """Détecte les ports série disponibles sur le système"""
    available_ports = []
    
    # Détection selon le système d'exploitation
    if sys.platform.startswith('win'):  # Windows
        # Vérifier les ports COM1 à COM20
        import serial.tools.list_ports
        try:
            ports = list(serial.tools.list_ports.comports())
            for port in ports:
                available_ports.append((port.device, f"{port.device} - {port.description}"))
        except ImportError:
            # Si pyserial n'est pas installé, on fait une détection basique
            for i in range(1, 21):
                port = f"COM{i}"
                available_ports.append((port, port))
    
    elif sys.platform.startswith('linux'):  # Linux (Raspberry Pi)
        # Vérifier les ports série courants sur Linux
        common_ports = [
            '/dev/ttyS0', '/dev/ttyS1', '/dev/ttyAMA0',
            '/dev/ttyUSB0', '/dev/ttyUSB1', '/dev/ttyUSB2',
            '/dev/ttyACM0', '/dev/ttyACM1', '/dev/ttyACM2'
        ]
        
        for port in common_ports:
            if os.path.exists(port):
                available_ports.append((port, port))
    
    # Si aucun port n'est trouvé, ajouter des options par défaut
    if not available_ports:
        if sys.platform.startswith('win'):
            available_ports = [('COM1', 'COM1'), ('COM3', 'COM3')]
        else:
            available_ports = [('/dev/ttyS0', '/dev/ttyS0'), ('/dev/ttyAMA0', '/dev/ttyAMA0')]
    
    return available_ports


# Variables globales
config = load_config()
current_photo = None
camera_active = False
camera_process = None
usb_camera = None

@app.route('/')
def index():
    """Page principale avec aperçu vidéo"""
    return render_template('index.html', timer=config['timer_seconds'])

# Variable globale pour stocker la dernière frame MJPEG
last_frame = None
frame_lock = threading.Lock()

@app.route('/capture', methods=['POST'])
def capture_photo():
    """Capturer une photo selon le type de caméra configuré"""
    global current_photo, last_frame
    
    try:
        # Générer un nom de fichier unique
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f'photo_{timestamp}.jpg'
        filepath = os.path.join(PHOTOS_FOLDER, filename)
        
        camera_type = config.get('camera_type', 'picamera')
        
        # Mode Pi Camera - utiliser rpicam-still pour une capture haute qualité
        if camera_type == 'picamera':
            logger.info("[CAPTURE] Utilisation de rpicam-still pour capture haute qualité")
            try:
                cmd = [
                    'rpicam-still',
                    '-o', filepath,
                    '--timeout', '1000',
                    '--width', '2304',      # Résolution plus élevée pour la photo
                    '--height', '1296',
                    '--nopreview'
                ]
                
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0 and os.path.exists(filepath):
                    current_photo = filename
                    logger.info(f"Photo Pi Camera capturée avec succès: {filename}")
                    
                    return jsonify({'success': True, 'filename': filename})
                else:
                    raise Exception(f"Échec rpicam-still: {result.stderr}")
                    
            except Exception as e:
                logger.info(f"Erreur rpicam-still, fallback vers frame MJPEG: {e}")
                # Fallback vers la méthode frame MJPEG
        
        # Mode USB ou fallback - capturer la frame actuelle du flux MJPEG
        with frame_lock:
            if last_frame is not None:
                # Sauvegarder la frame directement
                with open(filepath, 'wb') as f:
                    f.write(last_frame)
                
                current_photo = filename
                logger.info(f"Frame MJPEG capturée avec succès: {filename}")
                
                return jsonify({'success': True, 'filename': filename})
            else:
                logger.info("Aucune frame disponible dans le flux")
                return jsonify({'success': False, 'error': 'Aucune frame disponible'})
            
    except Exception as e:
        logger.info(f"Erreur lors de la capture: {e}")
        return jsonify({'success': False, 'error': f'Erreur de capture: {str(e)}'})

@app.route('/review')
def review_photo():
    """Page de révision de la photo"""
    if not current_photo:
        return redirect(url_for('index'))
    return render_template('review.html', photo=current_photo, config=config)

@app.route('/print_photo', methods=['POST'])
def print_photo():
    """Imprimer la photo actuelle"""
    global current_photo
    
    if not current_photo:
        return jsonify({'success': False, 'error': 'Aucune photo à imprimer'})
    
    try:
        # Vérifier si l'imprimante est activée
        if not config.get('printer_enabled', True):
            return jsonify({'success': False, 'error': 'Imprimante désactivée dans la configuration'})
        
        # Chercher la photo dans le dossier photos
        photo_path = os.path.join(PHOTOS_FOLDER, current_photo)
        if not os.path.exists(photo_path):
            return jsonify({'success': False, 'error': 'Photo introuvable'})
        
        # Vérifier l'existence du script d'impression
        script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ScriptPythonPOS.py')
        if not os.path.exists(script_path):
            return jsonify({'success': False, 'error': 'Script d\'impression introuvable (ScriptPythonPOS.py)'})
        
        # Construire la commande d'impression avec les nouveaux paramètres
        venv_python = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'venv', 'bin', 'python')
        cmd = [venv_python, 'ScriptPythonPOS.py', '--image', photo_path]
        
        # Ajouter les paramètres de port et baudrate
        printer_port = config.get('printer_port', '/dev/ttyS0')
        printer_baudrate = config.get('printer_baudrate', 9600)
        cmd.extend(['--port', printer_port, '--baudrate', str(printer_baudrate)])
        
        # Ajouter le texte de pied de page si configuré
        footer_text = config.get('footer_text', '')
        if footer_text:
            cmd.extend(['--text', footer_text])
        
        # Ajouter l'option haute résolution selon la configuration
        print_resolution = config.get('print_resolution', 384)
        if print_resolution > 384:
            cmd.append('--hd')
        
        # Exécuter l'impression
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
        
        if result.returncode == 0:
            return jsonify({'success': True, 'message': 'Photo imprimée avec succès!'})
        elif result.returncode == 2:
            # Code d'erreur spécifique pour manque de papier
            return jsonify({'success': False, 'error': 'Plus de papier dans l\'imprimante', 'error_type': 'no_paper'})
        else:
            error_msg = result.stderr.strip() if result.stderr else 'Erreur inconnue'
            if 'ModuleNotFoundError' in error_msg and 'escpos' in error_msg:
                return jsonify({'success': False, 'error': 'Module escpos manquant. Installez-le avec: pip install python-escpos'})
            else:
                return jsonify({'success': False, 'error': f'Erreur d\'impression: {error_msg}'})
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/delete_current', methods=['POST'])
def delete_current_photo():
    """Supprimer la photo actuelle"""
    global current_photo
    
    if current_photo:
        try:
            # Chercher la photo dans le dossier photos
            photo_path = os.path.join(PHOTOS_FOLDER, current_photo)
            
            if os.path.exists(photo_path):
                os.remove(photo_path)
                current_photo = None
                return jsonify({'success': True})
            else:
                return jsonify({'success': False, 'error': 'Photo introuvable'})
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)})
    
    return jsonify({'success': False, 'error': 'Aucune photo à supprimer'})

@app.route('/photos')
def photos_page():
    """Page dédiée à la gestion des photos"""
    # Vérifier si le dossier photos existe
    if not os.path.exists(PHOTOS_FOLDER):
        os.makedirs(PHOTOS_FOLDER)
    
    # Récupérer la liste des photos avec leurs métadonnées
    photos = []
    
    # Récupérer les photos du dossier PHOTOS_FOLDER
    if os.path.exists(PHOTOS_FOLDER):
        for filename in os.listdir(PHOTOS_FOLDER):
            if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
                file_path = os.path.join(PHOTOS_FOLDER, filename)
                file_size_kb = os.path.getsize(file_path) / 1024  # Taille en KB
                file_date = datetime.fromtimestamp(os.path.getmtime(file_path))
                
                photos.append({
                    'filename': filename,
                    'size_kb': file_size_kb,
                    'date': file_date.strftime("%d/%m/%Y %H:%M"),
                    'type': 'photo',
                    'folder': PHOTOS_FOLDER
                })
    
    # Trier les photos par date (plus récentes en premier)
    photos.sort(key=lambda x: datetime.strptime(x['date'], "%d/%m/%Y %H:%M"), reverse=True)
    
    # Compter les photos
    photo_count = len(photos)
    
    return render_template('photos.html', 
                           photos=photos,
                           photo_count=photo_count,
                           config=config)

@app.route('/admin')
def admin():
    # Vérifier si le dossier photos existe
    if not os.path.exists(PHOTOS_FOLDER):
        os.makedirs(PHOTOS_FOLDER)
    
    # Récupérer la liste des photos avec leurs métadonnées
    photos = []
    
    # Récupérer les photos du dossier PHOTOS_FOLDER
    if os.path.exists(PHOTOS_FOLDER):
        for filename in os.listdir(PHOTOS_FOLDER):
            if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
                file_path = os.path.join(PHOTOS_FOLDER, filename)
                file_size_kb = os.path.getsize(file_path) / 1024  # Taille en KB
                file_date = datetime.fromtimestamp(os.path.getmtime(file_path))
                
                photos.append({
                    'filename': filename,
                    'size_kb': file_size_kb,
                    'date': file_date.strftime("%d/%m/%Y %H:%M"),
                    'type': 'photo',
                    'folder': PHOTOS_FOLDER
                })
    
    # Trier les photos par date (plus récentes en premier)
    photos.sort(key=lambda x: datetime.strptime(x['date'], "%d/%m/%Y %H:%M"), reverse=True)
    
    # Compter les photos
    photo_count = len(photos)
    
    # Détecter les caméras USB disponibles
    available_cameras = detect_cameras()
    
    # Détecter les ports série disponibles
    available_serial_ports = detect_serial_ports()
    
    # Charger la configuration
    config = load_config()
    
    return render_template('admin.html', 
                           config=config, 
                           photos=photos,
                           photo_count=photo_count,
                           available_cameras=available_cameras,
                           available_serial_ports=available_serial_ports,
                           show_toast=request.args.get('show_toast', False))

@app.route('/admin/save', methods=['POST'])
def save_admin_config():
    """Sauvegarder la configuration admin"""
    global config
    
    try:
        config['footer_text'] = request.form.get('footer_text', '')
        
        # Gestion sécurisée des champs numériques
        timer_seconds = request.form.get('timer_seconds', '3').strip()
        config['timer_seconds'] = int(timer_seconds) if timer_seconds else 3
        
        config['high_density'] = 'high_density' in request.form
        
        # Configuration de la caméra
        config['camera_type'] = request.form.get('camera_type', 'picamera')
        
        # Récupérer l'ID de la caméra USB sélectionnée
        selected_camera = request.form.get('usb_camera_select', '0')
        # L'ID est stocké comme premier caractère de la valeur
        try:
            config['usb_camera_id'] = int(selected_camera)
        except ValueError:
            config['usb_camera_id'] = 0
        
        # Configuration de l'imprimante
        config['printer_enabled'] = 'printer_enabled' in request.form
        config['printer_port'] = request.form.get('printer_port', '/dev/ttyS0')
        
        printer_baudrate = request.form.get('printer_baudrate', '9600').strip()
        try:
            config['printer_baudrate'] = int(printer_baudrate)
        except ValueError:
            config['printer_baudrate'] = 9600
        
        print_resolution = request.form.get('print_resolution', '384').strip()
        try:
            config['print_resolution'] = int(print_resolution)
        except ValueError:
            config['print_resolution'] = 384
        
        save_config(config)
        flash('Configuration sauvegardée avec succès!', 'success')
        
    except Exception as e:
        flash(f'Erreur lors de la sauvegarde: {str(e)}', 'error')
    
    return redirect(url_for('admin'))

@app.route('/admin/delete_photos', methods=['POST'])
def delete_all_photos():
    """Supprimer toutes les photos"""
    try:
        deleted_count = 0
        
        # Supprimer toutes les photos
        if os.path.exists(PHOTOS_FOLDER):
            for filename in os.listdir(PHOTOS_FOLDER):
                if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
                    os.remove(os.path.join(PHOTOS_FOLDER, filename))
                    deleted_count += 1
        
        flash(f'{deleted_count} photo(s) supprimée(s) avec succès!', 'success')
    except Exception as e:
        flash(f'Erreur lors de la suppression: {str(e)}', 'error')
    
    return redirect(url_for('admin'))

@app.route('/admin/delete_photo/<filename>', methods=['POST'])
def delete_photo(filename):
    """Supprimer une photo spécifique"""
    try:
        file_path = os.path.join(PHOTOS_FOLDER, filename)
        if os.path.exists(file_path):
            os.remove(file_path)
            return jsonify({'success': True, 'message': 'Photo supprimée avec succès'})
        else:
            return jsonify({'success': False, 'error': 'Photo introuvable'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/admin/download_photo/<filename>')
def download_photo(filename):
    """Télécharger une photo spécifique"""
    try:
        # Chercher la photo dans le dossier photos
        if os.path.exists(os.path.join(PHOTOS_FOLDER, filename)):
            return send_from_directory(PHOTOS_FOLDER, filename, as_attachment=True)
        else:
            flash('Photo introuvable', 'error')
            return redirect(url_for('admin'))
    except Exception as e:
        flash(f'Erreur lors du téléchargement: {str(e)}', 'error')
        return redirect(url_for('admin'))

@app.route('/admin/reprint_photo/<filename>', methods=['POST'])
def reprint_photo(filename):
    """Réimprimer une photo spécifique"""
    try:
        # Chercher la photo dans le dossier photos
        photo_path = os.path.join(PHOTOS_FOLDER, filename)
        
        if os.path.exists(photo_path):
            # Vérifier si le script d'impression existe
            script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ScriptPythonPOS.py')
            if not os.path.exists(script_path):
                flash('Script d\'impression introuvable (ScriptPythonPOS.py)', 'error')
                return redirect(url_for('admin'))
            
            # Utiliser le script d'impression existant
            import subprocess
            venv_python = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'venv', 'bin', 'python')
            cmd = [
                venv_python, 'ScriptPythonPOS.py',
                '--image', photo_path
            ]
            
            # Ajouter les paramètres de port et baudrate
            printer_port = config.get('printer_port', '/dev/ttyS0')
            printer_baudrate = config.get('printer_baudrate', 9600)
            cmd.extend(['--port', printer_port, '--baudrate', str(printer_baudrate)])
            
            # Ajouter le texte de pied de page si défini
            footer_text = config.get('footer_text', '')
            if footer_text:
                cmd.extend(['--text', footer_text])
            
            # Ajouter l'option HD si la résolution est élevée
            print_resolution = config.get('print_resolution', 384)
            if print_resolution > 384:
                cmd.append('--hd')
            
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
            
            # Logger les détails
            logger.info(f"[REPRINT] Command: {' '.join(cmd)}")
            logger.info(f"[REPRINT] Return code: {result.returncode}")
            logger.info(f"[REPRINT] Stdout: {result.stdout}")
            logger.info(f"[REPRINT] Stderr: {result.stderr}")
            
            if result.returncode == 0:
                flash('Photo réimprimée avec succès!', 'success')
                logger.info("[REPRINT] Success!")
            else:
                error_msg = result.stderr.strip() if result.stderr else 'Erreur inconnue'
                if 'ModuleNotFoundError' in error_msg and 'escpos' in error_msg:
                    flash('Module escpos manquant. Installez-le avec: pip install python-escpos', 'error')
                else:
                    flash(f'Erreur d\'impression: {error_msg}', 'error')
        else:
            flash('Photo introuvable', 'error')
    except Exception as e:
        flash(f'Erreur lors de la réimpression: {str(e)}', 'error')
    
    return redirect(url_for('admin'))

# Diaporama feature removed: /api/slideshow endpoint deleted

@app.route('/api/printer_status')
def get_printer_status():
    """API pour vérifier l'état de l'imprimante"""
    return jsonify(check_printer_status())

@app.route('/photos/<filename>')
def serve_photo(filename):
    """Servir les photos"""
    # Vérifier dans le dossier photos
    if os.path.exists(os.path.join(PHOTOS_FOLDER, filename)):
        return send_from_directory(PHOTOS_FOLDER, filename)
    else:
        abort(404)

@app.route('/video_stream')
def video_stream():
    """Flux vidéo MJPEG en temps réel"""
    return Response(generate_video_stream(),
                   mimetype='multipart/x-mixed-replace; boundary=frame')

def generate_video_stream():
    """Générer le flux vidéo MJPEG selon le type de caméra configuré"""
    global camera_process, usb_camera, last_frame
    
    # Déterminer le type de caméra à utiliser
    camera_type = config.get('camera_type', 'picamera')
    
    try:
        # Arrêter tout processus caméra existant
        stop_camera_process()
        
        # Utiliser la caméra USB si configurée
        if camera_type == 'usb':
            logger.info("[CAMERA] Démarrage de la caméra USB...")
            camera_id = config.get('usb_camera_id', 0)
            usb_camera = UsbCamera(camera_id=camera_id)
            if not usb_camera.start():
                raise Exception(f"Impossible de démarrer la caméra USB avec ID {camera_id}")
            
            # Générateur de frames pour la caméra USB
            while True:
                frame = usb_camera.get_frame()
                if frame:
                    # Stocker la frame pour capture instantanée
                    with frame_lock:
                        last_frame = frame
                    
                    # Envoyer la frame au navigateur
                    yield (b'--frame\r\n'
                           b'Content-Type: image/jpeg\r\n'
                           b'Content-Length: ' + str(len(frame)).encode() + b'\r\n\r\n' +
                           frame + b'\r\n')
                else:
                    time.sleep(0.03)  # Attendre si pas de frame disponible
        
        # Utiliser la Pi Camera par défaut
        else:
            logger.info("[CAMERA] Démarrage de la Pi Camera...")
            # Commande rpicam-vid pour flux MJPEG - résolution 16/9
            cmd = [
                'rpicam-vid',
                '--codec', 'mjpeg',
                '--width', '1280',   # Résolution native plus compatible
                '--height', '720',   # Vrai 16/9 sans bandes noires
                '--framerate', '15', # Framerate plus élevé pour cette résolution
                '--timeout', '0',    # Durée infinie
                '--output', '-',     # Sortie vers stdout
                '--inline',          # Headers inline
                '--flush',           # Flush immédiat
                '--nopreview'        # Pas d'aperçu local
            ]
            
            camera_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                bufsize=0
            )
            
            # Buffer pour assembler les frames JPEG
            buffer = b''
            
            while camera_process and camera_process.poll() is None:
                try:
                    # Lire les données par petits blocs
                    chunk = camera_process.stdout.read(1024)
                    if not chunk:
                        break
                        
                    buffer += chunk
                    
                    # Chercher les marqueurs JPEG
                    while True:
                        # Chercher le début d'une frame JPEG (0xFFD8)
                        start = buffer.find(b'\xff\xd8')
                        if start == -1:
                            break
                            
                        # Chercher la fin de la frame JPEG (0xFFD9)
                        end = buffer.find(b'\xff\xd9', start + 2)
                        if end == -1:
                            break
                            
                        # Extraire la frame complète
                        jpeg_frame = buffer[start:end + 2]
                        buffer = buffer[end + 2:]
                        
                        # Stocker la frame pour capture instantanée
                        with frame_lock:
                            last_frame = jpeg_frame
                        
                        # Envoyer la frame au navigateur
                        yield (b'--frame\r\n'
                               b'Content-Type: image/jpeg\r\n'
                               b'Content-Length: ' + str(len(jpeg_frame)).encode() + b'\r\n\r\n' +
                               jpeg_frame + b'\r\n')
                               
                except Exception as e:
                    logger.info(f"[CAMERA] Erreur lecture flux: {e}")
                    break
                
    except Exception as e:
        logger.info(f"Erreur flux vidéo: {e}")
        # Envoyer une frame d'erreur
        error_msg = f"Erreur caméra: {str(e)}"
        yield (b'--frame\r\n'
               b'Content-Type: text/plain\r\n\r\n' +
               error_msg.encode() + b'\r\n')
    finally:
        stop_camera_process()

def stop_camera_process():
    """Arrêter proprement le processus caméra (Pi Camera ou USB)"""
    global camera_process, usb_camera
    
    # Arrêter la caméra USB si active
    if usb_camera:
        try:
            usb_camera.stop()
        except Exception as e:
            logger.info(f"[CAMERA] Erreur lors de l'arrêt de la caméra USB: {e}")
        usb_camera = None
    
    # Arrêter le processus libcamera-vid si actif
    if camera_process:
        try:
            camera_process.terminate()
            camera_process.wait(timeout=2)
        except:
            try:
                camera_process.kill()
            except:
                pass
        camera_process = None

@app.route('/start_camera')
def start_camera():
    """Démarrer l'aperçu caméra"""
    global camera_active
    camera_active = True
    return jsonify({'status': 'camera_started'})

@app.route('/stop_camera')
def stop_camera():
    """Arrêter l'aperçu caméra"""
    global camera_active
    camera_active = False
    stop_camera_process()
    return jsonify({'status': 'camera_stopped'})

@app.route('/admin/kiosk_control', methods=['POST'])
def kiosk_control():
    """Contrôler le mode kiosk (arrêter/redémarrer)"""
    try:
        action = request.json.get('action')
        
        if action == 'stop':
            # Arrêter le service kiosk
            subprocess.run(['sudo', 'systemctl', 'stop', 'simplebooth-kiosk.service'], check=True)
            subprocess.run(['sudo', 'systemctl', 'disable', 'simplebooth-kiosk.service'], check=True)
            # Arrêter Chromium
            subprocess.run(['sudo', 'pkill', '-f', 'chromium'], check=False)
            return jsonify({
                'status': 'success',
                'message': 'Mode kiosk arrêté. Vous pouvez maintenant utiliser l\'interface normale.'
            })
            
        elif action == 'restart':
            # Redémarrer le service kiosk
            subprocess.run(['sudo', 'systemctl', 'enable', 'simplebooth-kiosk.service'], check=True)
            subprocess.run(['sudo', 'systemctl', 'restart', 'simplebooth-kiosk.service'], check=True)
            return jsonify({
                'status': 'success',
                'message': 'Mode kiosk redémarré. L\'application va se relancer en plein écran.'
            })
            
        elif action == 'status':
            # Vérifier l'état du service kiosk
            result = subprocess.run(['sudo', 'systemctl', 'is-active', 'simplebooth-kiosk.service'], 
                                  capture_output=True, text=True, check=False)
            is_active = result.stdout.strip() == 'active'
            
            result_enabled = subprocess.run(['sudo', 'systemctl', 'is-enabled', 'simplebooth-kiosk.service'], 
                                          capture_output=True, text=True, check=False)
            is_enabled = result_enabled.stdout.strip() == 'enabled'
            
            return jsonify({
                'status': 'success',
                'kiosk_active': is_active,
                'kiosk_enabled': is_enabled,
                'message': f'Service kiosk: {"Actif" if is_active else "Inactif"} / {"Activé" if is_enabled else "Désactivé"}'
            })
            
        else:
            return jsonify({
                'status': 'error',
                'message': 'Action non reconnue'
            }), 400
            
    except subprocess.CalledProcessError as e:
        return jsonify({
            'status': 'error',
            'message': f'Erreur lors de l\'exécution de la commande: {str(e)}'
        }), 500
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Erreur: {str(e)}'
        }), 500

@app.route('/admin/shutdown', methods=['POST'])
def shutdown_application():
    """Arrêter complètement l'application (Chromium + app Python)"""
    try:
        # Arrêter Chromium
        subprocess.run(['sudo', 'pkill', '-f', 'chromium'], check=False)
        
        # Arrêter l'application Python
        subprocess.run(['sudo', 'pkill', '-f', 'python.*app.py'], check=False)
        
        return jsonify({
            'status': 'success',
            'message': 'Application arrêtée complètement. Redémarrez avec sudo reboot.'
        })
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Erreur: {str(e)}'
        }), 500

# Nettoyer les processus à la fermeture
@atexit.register
def cleanup():
    logger.info("[APP] Arrêt de l'application, nettoyage des ressources...")
    stop_camera_process()

def signal_handler(sig, frame):
    stop_camera_process()
    exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
