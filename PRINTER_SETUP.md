# Configuration de l'imprimante thermique QR701

Guide de configuration de l'imprimante thermique QR701 Mini 58mm sur Raspberry Pi 4.

## Matériel requis

- Imprimante thermique QR701 Mini 58mm (interface TTL)
- Raspberry Pi 4
- Connexion GPIO : TX, RX, GND, VCC (5-9V)

## Câblage GPIO

| QR701 | Raspberry Pi GPIO |
|-------|-------------------|
| TX    | GPIO 15 (RX)      |
| RX    | GPIO 14 (TX)      |
| GND   | GND               |
| VCC   | 5V ou 9V externe  |

**Note** : Alimentation 9V externe recommandée pour une impression optimale.

## 1. Activer l'UART sur le Raspberry Pi

Éditer `/boot/firmware/config.txt` :

```bash
sudo nano /boot/firmware/config.txt
```

Ajouter à la fin du fichier :

```
# Enable UART for thermal printer
dtparam=uart0=on
enable_uart=1
```

Redémarrer :

```bash
sudo reboot
```

## 2. Vérifier le port série

Après redémarrage, vérifier que `/dev/ttyS0` existe :

```bash
ls -l /dev/ttyS0
```

## 3. Désactiver le service getty sur le port série

**⚠️ ÉTAPE CRITIQUE - NE PAS OUBLIER ! ⚠️**

Le service `getty` (console série) utilise par défaut le port `/dev/ttyS0`. Si ce service n'est pas désactivé, il va interférer avec l'imprimante et causer des impressions intempestives de "My IP address" ou autres messages parasites.

Désactiver et arrêter le service :

```bash
sudo systemctl stop serial-getty@ttyS0.service
sudo systemctl disable serial-getty@ttyS0.service
```

Vérifier que le port est libre :

```bash
sudo lsof /dev/ttyS0
```

**Résultat attendu :** Aucune sortie (port libre)

**Si vous oubliez cette étape :** L'imprimante imprimera des messages parasites à chaque vérification de statut ou communication.

## 4. Configurer les permissions

Ajouter l'utilisateur au groupe `dialout` :

```bash
sudo usermod -a -G dialout admin
```

Configurer les permissions du port :

```bash
sudo chown root:dialout /dev/ttyS0
sudo chmod 660 /dev/ttyS0
```

## 5. Créer une règle udev permanente

Créer `/etc/udev/rules.d/99-serial-printer.rules` :

```bash
sudo nano /etc/udev/rules.d/99-serial-printer.rules
```

Contenu :

```
# Règle udev pour le port série de l'imprimante thermique
KERNEL=="ttyS0", GROUP="dialout", MODE="0660"
```

Recharger les règles udev :

```bash
sudo udevadm control --reload-rules
```

## 6. Installer les dépendances Python

Dans le venv SimpleBooth :

```bash
cd /home/admin/SimpleBooth
source venv/bin/activate
pip install python-escpos Pillow
```

## 7. Tester l'imprimante

Test basique :

```bash
cd /home/admin/SimpleBooth
source venv/bin/activate
python ScriptPythonPOS.py --image photos/photo_test.jpg --port /dev/ttyS0 --baudrate 9600
```

Test avec texte :

```bash
python ScriptPythonPOS.py --image photos/photo_test.jpg --port /dev/ttyS0 --baudrate 9600 --text "SimpleBooth"
```

## 8. Vérification du statut

Vérifier qui utilise le port série :

```bash
sudo lsof /dev/ttyS0
```

Résultat attendu : aucun processus (vide)

Vérifier les statistiques du driver série :

```bash
sudo cat /proc/tty/driver/serial
```

## Configuration dans SimpleBooth

Dans la page admin (http://IP:5000/admin), configurer :

- **Port série** : `/dev/ttyS0`
- **Baudrate** : `9600`
- **Résolution** : `384 pixels (Standard)` ou `576 pixels (High Density)`
- **Texte de pied de page** : Personnalisable

## Dépannage

### L'imprimante ne répond pas

1. Vérifier le câblage (TX/RX inversés ?)
2. Vérifier que le capot est bien fermé
3. Vérifier l'alimentation (9V recommandé)
4. Vérifier que getty est bien désactivé : `systemctl status serial-getty@ttyS0.service`

### Erreur "Permission denied"

```bash
sudo chmod 660 /dev/ttyS0
sudo chown root:dialout /dev/ttyS0
```

### LED clignote 4 fois

Problème de papier :
- Retirer et réinstaller le papier thermique
- Vérifier que le capot est bien fermé
- Nettoyer le capteur de papier

### Caractères chinois ou "my ip address"

L'imprimante fait un self-test. Causes possibles :
- Accès concurrent au port série (vérifier avec `lsof`)
- Données corrompues
- Redémarrer l'imprimante (débrancher/rebrancher)

## Informations techniques

- **Port série** : `/dev/ttyS0` (Raspberry Pi 4)
- **Baudrate** : 9600 (par défaut QR701)
- **Largeur papier** : 58mm
- **Résolution** : 384 pixels (standard) ou 576 pixels (HD)
- **Format image** : ESC/POS bitImageRaster

## Scripts utiles

Vérifier le statut complet :

```bash
echo "=== Port série ==="
ls -l /dev/ttyS0
echo ""
echo "=== Processus utilisant le port ==="
sudo lsof /dev/ttyS0
echo ""
echo "=== Groupes de l'utilisateur ==="
groups
echo ""
echo "=== Service getty ==="
systemctl status serial-getty@ttyS0.service
```
