# Renders Astra's orange speed-streak app icon (KP, 2026-11-13).
# Square icon: python3 render_app_icon.py out.png
# Apple TV layer: python3 render_app_icon.py out.png 800 480 0.95
import sys, numpy as np
from PIL import Image, ImageDraw, ImageFilter
N = 2048
def hexrgb(h): return np.array([int(h[i:i+2], 16) for i in (1, 3, 5)], float)
def L(img): return np.asarray(img, float) / 255
def blur(a, r): return L(Image.fromarray((np.clip(a,0,1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)))

def render(out, W=1024, Hh=1024, z=1.0, rows=7, fade_len=0.7, dx=0.0, body_a=0.9, bloom_a=0.16, glow_a=0.40,
           tails=(0.17, 0.25, 0.13, 0.21, 0.15, 0.27, 0.18)):
    H = N; Wp = int(round(N * W / Hh))
    py, px = np.mgrid[0:H, 0:Wp].astype(float)
    xx = (px - Wp / 2) / (H * z) + 0.5
    yy = (py - H / 2) / (H * z) + 0.5
    PX = lambda x, k=1: ((x - 0.5) * H * z + Wp / 2) * k
    PY = lambda y, k=1: ((y - 0.5) * H * z + H / 2) * k
    t = np.clip((xx * 0.35 + yy * 0.9) / 1.1, 0, 1)[..., None]
    img = hexrgb('#1A1511') * (1 - t) + hexrgb('#050404') * t
    d = np.sqrt(((xx - 0.58) / 0.40) ** 2 + ((yy - 0.5) / 0.34) ** 2)
    img += hexrgb('#FF6A1A') * (np.clip(1 - d, 0, 1) ** 2.2)[..., None] * bloom_a

    x0, x1, yc, hh = 0.42 + dx, 0.84 + dx, 0.50, 0.29
    band = 2 * hh / rows; bar_h = band * 0.6
    S = 4  # extra AA on shapes
    tri = Image.new('L', (Wp, H), 0)
    ImageDraw.Draw(tri).polygon([(PX(x0), PY(yc-hh)), (PX(x1), PY(yc)), (PX(x0), PY(yc+hh))], fill=255)
    tri = L(tri.filter(ImageFilter.GaussianBlur(N*0.02)).point(lambda v: 255 if v > 127 else 0))
    tri = blur(tri, 1.2)
    k = S/2; bars = Image.new('L', (int(Wp*k), int(H*k)), 0); dr = ImageDraw.Draw(bars)
    for i in range(rows):
        cy = yc - hh + band * (i + 0.5)
        xr = x0 + (x1 - x0) * (1 - abs(cy - yc) / hh) - 0.012
        xr = max(xr, x0 + 0.05)
        dr.rounded_rectangle((PX(tails[i],k), PY(cy-bar_h/2,k), PX(xr,k), PY(cy+bar_h/2,k)), radius=bar_h*H*z*k/2, fill=255)
    bars = L(bars.resize((Wp, H), Image.LANCZOS))
    fade = np.zeros((H, Wp))
    for i in range(rows):
        cy = yc - hh + band * (i + 0.5)
        xr = max(x0 + (x1 - x0) * (1 - abs(cy - yc) / hh) - 0.012, x0 + 0.05)
        m = np.abs(yy - cy) < band / 2
        f = np.clip((xx - tails[i]) / (fade_len * (xr - tails[i])), 0, 1) ** 1.5
        fade = np.where(m, f, fade)

    u = np.clip((xx - 0.10) / (x1 - 0.10), 0, 1)
    c_tail, c_mid, c_tip = hexrgb('#8A2C0B'), hexrgb('#F06A24'), hexrgb('#FFBE6E')
    col = np.where((u < 0.6)[..., None], c_tail + (c_mid - c_tail) * (u / 0.6)[..., None],
                   c_mid + (c_tip - c_mid) * ((u - 0.6) / 0.4)[..., None])
    col *= (1.06 - 0.14 * np.clip((yy - (yc - hh)) / (2 * hh), 0, 1))[..., None]
    a_bars = bars * fade
    a_body = tri * body_a * np.clip((xx - x0) / 0.40, 0, 1) ** 1.6
    alpha = np.clip(a_body + a_bars * (1 - a_body), 0, 1)
    img += hexrgb('#FF5A10') * blur(alpha, N*0.04)[..., None] * glow_a
    img = img * (1 - alpha[..., None]) + col * alpha[..., None]
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((W, Hh), Image.LANCZOS).save(out, optimize=True)

if __name__ == '__main__':
    a = sys.argv[1:]
    render(a[0], int(a[1]), int(a[2]), float(a[3])) if len(a) > 1 else render(a[0])
