"""Generate the Mero Swasthya brand assets from the supplied JPEG.

The source is a 1254x1254 JPEG on a white ground: a blue-to-green cross
holding a doctor and a patient folder, with the wordmark beneath it. Rows
263..795 are the mark, 822..972 the wordmark, separated by 26 blank rows.

Everything here is derived, so re-running it from the original is the only
way any of these files should ever change.
"""
import os
import numpy as np
from PIL import Image

SRC = r'C:/Users/Hazard/Downloads/logo.jpeg'
OUT = r'D:/mero_swasthya/assets/brand'
# The launcher-icon sources are read from disk by flutter_launcher_icons at
# build time and never at runtime, so they live one level down and are left out
# of the asset bundle: at 1024 square they were adding about 0.6 MB to every
# APK for nothing.
ICON_OUT = os.path.join(OUT, 'icon')

MARK_ROWS = (263, 796)      # end-exclusive
WORD_ROWS = (822, 973)

TOL_LO = 12                 # below this distance from white -> fully transparent
TOL_HI = 44                 # above this -> fully opaque; between -> a soft edge

DARK_INK = (241, 245, 249)  # AppColors dark-mode onSurface, for the dark wordmark

os.makedirs(OUT, exist_ok=True)
os.makedirs(ICON_OUT, exist_ok=True)


def dewhite(rgb):
    """White ground -> alpha, with the white un-blended out of soft edges.

    A plain threshold leaves a pale halo: an edge pixel is ink blended with
    white, so painting it unchanged over a dark background shows the white it
    was mixed with. Dividing the white back out is what keeps the mark clean
    against the dark theme as well as the light one.
    """
    a = rgb.astype(np.float64)
    dist = np.abs(a - 255.0).max(axis=2)
    alpha = np.clip((dist - TOL_LO) / (TOL_HI - TOL_LO), 0.0, 1.0)

    safe = np.where(alpha > 0.0, alpha, 1.0)[..., None]
    straight = (a - 255.0 * (1.0 - safe)) / safe
    straight = np.clip(straight, 0, 255)

    out = np.zeros(a.shape[:2] + (4,), dtype=np.uint8)
    out[..., :3] = straight.astype(np.uint8)
    out[..., 3] = (alpha * 255).astype(np.uint8)
    return out


def trim(rgba):
    """Crop to the alpha bounding box."""
    alpha = rgba[..., 3]
    ys, xs = np.nonzero(alpha > 8)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def fit_square(rgba, canvas, fraction):
    """Centre `rgba` on a transparent square, longest side = fraction of it."""
    h, w = rgba.shape[:2]
    target = int(round(canvas * fraction))
    scale = target / max(h, w)
    new = Image.fromarray(rgba, 'RGBA').resize(
        (max(1, int(round(w * scale))), max(1, int(round(h * scale)))),
        Image.LANCZOS,
    )
    out = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    out.paste(new, ((canvas - new.width) // 2, (canvas - new.height) // 2), new)
    return out


src = np.asarray(Image.open(SRC).convert('RGB'))
rgba = dewhite(src)

mark = trim(rgba[MARK_ROWS[0]:MARK_ROWS[1]])
word = rgba[WORD_ROWS[0]:WORD_ROWS[1]]
full = trim(rgba[MARK_ROWS[0]:WORD_ROWS[1]])

# --- logo_full: mark + wordmark, transparent, trimmed ----------------------
Image.fromarray(full, 'RGBA').save(os.path.join(OUT, 'logo_full.png'))

# --- logo_full_dark: the same, with the navy wordmark lifted to a light ink.
# The wordmark's "Mero" is #084E8A, which is 1.5:1 against the dark theme's
# #0F172A scaffold. The mark keeps its own colours; only the type changes.
dark = rgba[MARK_ROWS[0]:WORD_ROWS[1]].copy()
word_off = WORD_ROWS[0] - MARK_ROWS[0]
band = dark[word_off:]
opaque = band[..., 3] > 8
for i, v in enumerate(DARK_INK):
    ch = band[..., i]
    ch[opaque] = v
Image.fromarray(trim(dark), 'RGBA').save(
    os.path.join(OUT, 'logo_full_dark.png'))

# --- logo_mark: the mark alone, filling ~70 % of its square ----------------
# 256 for the bundle: the biggest in-app use is the 40 dp settings footer,
# which is 120 px on a 3x screen.
fit_square(mark, 256, 0.70).save(os.path.join(OUT, 'logo_mark.png'))

# --- logo_mark_white: the same silhouette in white ------------------------
# The doctor and the folder are white *in the source*, so they are already
# transparent here; painting the rest white leaves them as cut-outs, which is
# what makes the mark readable on the brand-blue app bar and what Android 13's
# themed icon expects.
white = mark.copy()
white[..., 0] = 255
white[..., 1] = 255
white[..., 2] = 255
fit_square(white, 256, 0.70).save(os.path.join(OUT, 'logo_mark_white.png'))

# --- icon_foreground: adaptive icons crop the outer ring ------------------
fit_square(mark, 1024, 0.66).save(os.path.join(ICON_OUT, 'icon_foreground.png'))

# --- icon_monochrome: the themed-icon layer, on the same safe zone ---------
# Not logo_mark_white: that one is sized 70 % for the app bar, and at that
# size Android 13's circular themed mask cropped the top and bottom off the
# cross. The monochrome layer has to respect the same 66 % safe zone as the
# foreground it sits under.
fit_square(white, 1024, 0.66).save(os.path.join(ICON_OUT, 'icon_monochrome.png'))

# --- logo_mark_on_white: the legacy launcher icon needs a ground ----------
legacy = Image.new('RGBA', (1024, 1024), (255, 255, 255, 255))
legacy.alpha_composite(fit_square(mark, 1024, 0.70))
legacy.convert('RGB').save(os.path.join(ICON_OUT, 'logo_mark_on_white.png'))

# --- native splash marks -------------------------------------------------
# Android 12+ draws its own splash from the launcher icon, but the legacy
# windowBackground path is still what older handsets use, and it needs a real
# bitmap per density rather than an asset from the Flutter bundle (which is not
# mounted yet when the window is drawn).
RES = r'D:/mero_swasthya/android/app/src/main/res'
for folder, px in [('drawable-mdpi', 96), ('drawable-hdpi', 144),
                   ('drawable-xhdpi', 192), ('drawable-xxhdpi', 288),
                   ('drawable-xxxhdpi', 384)]:
    d = os.path.join(RES, folder)
    os.makedirs(d, exist_ok=True)
    img = Image.fromarray(mark, 'RGBA')
    scale = px / max(img.size)
    img = img.resize((max(1, round(img.width * scale)),
                      max(1, round(img.height * scale))), Image.LANCZOS)
    canvas = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    canvas.paste(img, ((px - img.width) // 2, (px - img.height) // 2), img)
    canvas.save(os.path.join(d, 'splash_mark.png'))
print('splash marks written to android/app/src/main/res/drawable-*/')

for folder, label in [(OUT, 'bundled '), (ICON_OUT, 'icon-only')]:
    for name in sorted(os.listdir(folder)):
        p = os.path.join(folder, name)
        if not os.path.isfile(p):
            continue
        with Image.open(p) as im:
            print('%s %-24s %-5s %-9s %8d bytes' % (
                label, name, im.mode, '%dx%d' % im.size, os.path.getsize(p)))
