# 📸 Photobooth Raspberry Pi

> **Application Flask pour photobooth tactile avec flux vidéo temps réel et capture instantanée** 

![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)
![Flask](https://img.shields.io/badge/Flask-2.3.3-green.svg)
![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-Compatible-red.svg)
![OpenCV](https://img.shields.io/badge/OpenCV-Support%20USB-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

### Introduction et crédits

Comme vous pouvez le voir, j'ai forké le projet des Frères Poulin. Bravo à eux pour ce superbe projet qui m'a inspiré.

Leur vidéo -> https://www.youtube.com/watch?v=GxFLX6c7Nos

J'avais un Raspberry Pi 4 qui trainait donc j'ai voulu en faire quelque chose. Quelques changements :

- Le code des FP ne fonctionnait pas sur mon Raspberry Pi 4 avec la dernière version de l'OS donc j'ai tout mis à jour dans mon code que vous trouverez ici.
- Ajout d'une page pour que les personnes puissent télécharger les photos sur leur téléphone plutôt que de passer par Telegram (fonctionnalité que j'ai retiré).
- Retrait des effets d'IA.
- Simplification de la page d'admin + ajout d'un bouton pour supprimer les photos.
- Retrait du code pour la caméra USB (je n'utilise que la caméra RPI)
- Ajout de deux boutons sur l'interface pour pouvoir redémarrer l'application depuis l'écran tactile si elle se plantait et un autre bouton pour fermer l'application (par exemple pour aller régler le wifi, connecter le bluetooth) car elle est en pleine écran.
- Séparation en deux services systemd, un pour l'application Flask et un pour la mise en plein écran en utilisant le mode Kiosk de Chromimum.
- J'ai préféré mettre la malette à l'horizontal pour faire plus appareil photo.

### Photos du produit terminé

A venir.

### Matériel

Note : C'est probablement compatible avec un Raspberry Pi 5 ou d'autres écrans tactiles, caméras ou imprimantes mais je donne juste la liste de ce que j'ai utilisé et qui fonctionne pour moi.

- Raspberry pi 4
- [Alimentation Raspberry Pi 5](https://amzlink.to/az01ijEmlFqxT)
- [Pi Camera 3](https://amzlink.to/az0eEXwhnxNvO)
- [Imprimante Thermique (AliExpress)](https://s.click.aliexpress.com/e/_oFyCgCI)
- [Ecran Waveshare (Amazon)](https://amzlink.to/az03G4UMruNnc)
- [Adaptateur pour le pied](https://www.amazon.fr/Adaptateur-Universel-Haut-Parleur-Support-Audio/dp/B0FLVCDQ3Z/ref=sr_1_3?__mk_fr_FR=%C3%85M%C3%85%C5%BD%C3%95%C3%91&crid=2PQYXCDU3URH3&dib=eyJ2IjoiMSJ9.EzWXaU9tqtqt_r9fitTRGz3jcJCAeJpEA_rf8RF4ZDxly436UhyFsO265HNIX7cJ9mY9fhr-eumveIpO54GCkCrDxdgoi93vEOD3jrewmg451FrqLfKBvWhqKhh8r_MzqsPW6VGyFcI7IiUphzF1CTyri1-Y_9pjilaYhCwnI0tH6z4hVXjG-OrQiqQ5wBC33e-7C8Y4pFB845YWY_va6LfgaTYIQh-hBWdjMXVmpRTrgPcZ4BeINS-hUWze9O_3qonXv4aS6Lk7hB8kTWlC4YxT5xVboAea2pcJ3V6LMpQ.g8f0G-EIdHUD2BkIRPXD-zpehx0dYZBGyRD87RMu_bo&dib_tag=se&keywords=Tr%C3%A9pied+rotatif+%C3%A0+montage+m%C3%A9tallique+de+35mm%2C+adaptateur+de+support+de+haut-parleur+DJ&qid=1763143196&sprefix=tr%C3%A9pied+rotatif+%C3%A0+montage+m%C3%A9tallique+de+35mm%2C+adaptateur+de+support+de+haut-parleur+dj%2Caps%2C137&sr=8-3)
- [Treppied](https://www.amazon.fr/dp/B07YCCPQT3/ref=sspa_dk_detail_4?psc=1&pd_rd_i=B07YCCPQT3&pd_rd_w=9q4q0&content-id=amzn1.sym.d28e3d6a-4412-4be7-a4f8-1c4a85ce86d9&pf_rd_p=d28e3d6a-4412-4be7-a4f8-1c4a85ce86d9&pf_rd_r=G8YMHV7S4AYJQ8X145KA&pd_rd_wg=dQ5pI&pd_rd_r=dc6c0d78-f35a-4863-88ae-faae9ffd255c&aref=jqCTNYneb6&sp_csd=d2lkZ2V0TmFtZT1zcF9kZXRhaWw)
- [Papier thermique](https://www.amazon.fr/dp/B0D7CRVMPD/ref=sspa_dk_detail_2?pd_rd_i=B0D7CRVMPD&pd_rd_w=2DTk5&content-id=amzn1.sym.d28e3d6a-4412-4be7-a4f8-1c4a85ce86d9&pf_rd_p=d28e3d6a-4412-4be7-a4f8-1c4a85ce86d9&pf_rd_r=TD1DEFVH6HWNPS42C8RY&pd_rd_wg=qutOS&pd_rd_r=5fd5a367-5d79-455e-a45e-721928a13620&aref=iomm1QRmr3&sp_csd=d2lkZ2V0TmFtZT1zcF9kZXRhaWw&th=1)
- [Pi cobbler](https://boutique.semageek.com/fr/347-pi-cobbler-plus-breakout-kit-pour-raspberry-pi-3007885588804.html)
- [Breadboard](https://www.amazon.fr/MMOBIEL-Breadboard-Prototype-Circuit-Imprim%C3%A9/dp/B0CPJRSLDX/ref=sr_1_4_sspa?crid=TWRN0LXQALDV&dib=eyJ2IjoiMSJ9.GjajzxMHxIX-ZrH72gyWL8k5vra-GVrjtYJgmDk12Q8wFdsa5QEFq5eQ1uMhlExblVH7KecB84RsqiFvMwH1qiXi72tLza1t0TmxetwJe0EYJYsWIa0tx6115ET1mbsmyesJVqNIjHb3yKzJMfh2QurYO0Ro617yQeeCGvnhlAX_jvE7kmx62ixWJH2xDGx7MO_xctshCGkdUsT_Zk7WV9u5j6aaV0ujkoYEBiz1MDrcfupT3u-2Y5gkhF2bSEdUt91335Z8LWuHTvwEaq6edVE1d7xD477bce1gObOFsgI.FP83Zh8DfXXTKLTPgU15DhmeuOiJMfotTPS6I_2mOvw&dib_tag=se&keywords=breadboard&qid=1763497238&sprefix=bread%2Caps%2C149&sr=8-4-spons&aref=REjXHa3Uu7&sp_csd=d2lkZ2V0TmFtZT1zcF9hdGY&th=1)
- Quelques fils pour relier l'écran et l'imprimante au cobbler

### Schéma de câblage

Les Frères Poulain n'indiquent nul part le cablâge à faire pour les différents éléments donc je vais mettre ce qui fonctionne dans mon cas ici. 

En cours de réalisation...

### Installation

Après un `git clone` :

```bash
cd Photobooth
sudo ./setup.sh
```

**Accéder à l'interface :**

   - Ouvrir un navigateur sur `http://localhost:5000`
   - Ou depuis un autre appareil : `http://[IP_RASPBERRY]:5000`

**Pages disponibles :**
   - `/` : Interface principale du photobooth
   - `/photos` : Galerie de gestion des photos
   - `/admin` : Panneau d'administration complet

### Configuration

La configuration est sauvegardée dans `config.json`

