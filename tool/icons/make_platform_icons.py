"""Generates every platform launcher icon from the masters in assets/icons.

Requires Pillow (pip install pillow). Run from the repository root after
`flutter test tool/icons/render_logo_test.dart`.
"""
import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
ICONS = ROOT / 'assets' / 'icons'
BACKGROUND = '#3E2723'

rounded = Image.open(ICONS / 'app_icon.png').convert('RGBA')
full = Image.open(ICONS / 'app_icon_full.png').convert('RGBA')
foreground = Image.open(ICONS / 'app_icon_foreground.png').convert('RGBA')


def save(image, size, path, opaque=False):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.LANCZOS)
    if opaque:
        base = Image.new('RGB', resized.size, BACKGROUND)
        base.paste(resized, mask=resized.split()[3])
        resized = base
    resized.save(path, optimize=True)


# Android: legacy launcher icons and adaptive icon foregrounds.
for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(rounded, size, f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
    save(foreground, int(size * 108 / 48), f'android/app/src/main/res/drawable-{density}/ic_launcher_foreground.png')
adaptive = ROOT / 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'
adaptive.parent.mkdir(parents=True, exist_ok=True)
adaptive.write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n', encoding='utf-8')
colors = ROOT / 'android/app/src/main/res/values/ic_launcher_background.xml'
colors.write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n</resources>\n', encoding='utf-8')

# iOS: every size listed in the asset catalog, opaque (iOS applies the mask).
ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((ios / 'Contents.json').read_text(encoding='utf-8'))['images']:
    if 'filename' not in entry:
        continue
    points = float(entry['size'].split('x')[0])
    scale = int(entry['scale'].rstrip('x'))
    save(full, round(points * scale), ios / entry['filename'], opaque=True)

# macOS asset catalog.
macos = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((macos / 'Contents.json').read_text(encoding='utf-8'))['images']:
    if 'filename' in entry:
        points = float(entry['size'].split('x')[0])
        scale = int(entry['scale'].rstrip('x'))
        save(rounded, round(points * scale), macos / entry['filename'])

# Web: standard, maskable and favicon.
save(rounded, 192, 'web/icons/Icon-192.png')
save(rounded, 512, 'web/icons/Icon-512.png')
save(full, 192, 'web/icons/Icon-maskable-192.png', opaque=True)
save(full, 512, 'web/icons/Icon-maskable-512.png', opaque=True)
save(rounded, 32, 'web/favicon.png')

# Windows: multi-resolution .ico.
rounded.save(ROOT / 'windows/runner/resources/app_icon.ico',
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

print('platform icons written')
