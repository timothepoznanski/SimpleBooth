#!/usr/bin/env python3
from escpos.printer import Serial
from PIL import Image

# Charger la photo haute résolution
img = Image.open('photos/photo_20251117_202125.jpg')
print(f'Image originale: {img.size} {img.mode}')

img = img.convert('L')  # Niveau de gris
img = img.resize((384, int(384 * img.height / img.width)))

print(f'Image redimensionnée: {img.size} {img.mode}')

# Connexion
p = Serial('/dev/ttyS0', baudrate=9600, timeout=1)

# Imprimer avec bitImageRaster
p.image(img, impl='bitImageRaster', high_density_vertical=False, high_density_horizontal=False)
p.text('\n\n\n')

p.close()
print('Test terminé')
