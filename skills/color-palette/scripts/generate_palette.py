#!/usr/bin/env python3
import argparse, json, math, os, re, sys

SHADES = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
NAN = float('nan')

FAMILIES = [
    ('Red', 'fef2f2 fee2e2 fecaca fca5a5 f87171 ef4444 dc2626 b91c1c 991b1b 7f1d1d 450a0a'),
    ('Orange', 'fff7ed ffedd5 fed7aa fdba74 fb923c f97316 ea580c c2410c 9a3412 7c2d12 431407'),
    ('Amber', 'fffbeb fef3c7 fde68a fcd34d fbbf24 f59e0b d97706 b45309 92400e 78350f 451a03'),
    ('Yellow', 'fefce8 fef9c3 fef08a fde047 facc15 eab308 ca8a04 a16207 854d0e 713f12 422006'),
    ('Lime', 'f7fee7 ecfccb d9f99d bef264 a3e635 84cc16 65a30d 4d7c0f 3f6212 365314 1a2e05'),
    ('Green', 'f0fdf4 dcfce7 bbf7d0 86efac 4ade80 22c55e 16a34a 15803d 166534 14532d 052e16'),
    ('Emerald', 'ecfdf5 d1fae5 a7f3d0 6ee7b7 34d399 10b981 059669 047857 065f46 064e3b 022c22'),
    ('Teal', 'f0fdfa ccfbf1 99f6e4 5eead4 2dd4bf 14b8a6 0d9488 0f766e 115e59 134e4a 042f2e'),
    ('Cyan', 'ecfeff cffafe a5f3fc 67e8f9 22d3ee 06b6d4 0891b2 0e7490 155e75 164e63 083344'),
    ('Sky', 'f0f9ff e0f2fe bae6fd 7dd3fc 38bdf8 0ea5e9 0284c7 0369a1 075985 0c4a6e 082f49'),
    ('Blue', 'eff6ff dbeafe bfdbfe 93c5fd 60a5fa 3b82f6 2563eb 1d4ed8 1e40af 1e3a8a 172554'),
    ('Indigo', 'eef2ff e0e7ff c7d2fe a5b4fc 818cf8 6366f1 4f46e5 4338ca 3730a3 312e81 1e1b4b'),
    ('Violet', 'f5f3ff ede9fe ddd6fe c4b5fd a78bfa 8b5cf6 7c3aed 6d28d9 5b21b6 4c1d95 2e1065'),
    ('Purple', 'faf5ff f3e8ff e9d5ff d8b4fe c084fc a855f7 9333ea 7e22ce 6b21a8 581c87 3b0764'),
    ('Fuchsia', 'fdf4ff fae8ff f5d0fe f0abfc e879f9 d946ef c026d3 a21caf 86198f 701a75 4a044e'),
    ('Pink', 'fdf2f8 fce7f3 fbcfe8 f9a8d4 f472b6 ec4899 db2777 be185d 9d174d 831843 500724'),
    ('Rose', 'fff1f2 ffe4e6 fecdd3 fda4af fb7185 f43f5e e11d48 be123c 9f1239 881337 4c0519'),
    ('Slate', 'f8fafc f1f5f9 e2e8f0 cbd5e1 94a3b8 64748b 475569 334155 1e293b 0f172a 020617'),
    ('Gray', 'f9fafb f3f4f6 e5e7eb d1d5db 9ca3af 6b7280 4b5563 374151 1f2937 111827 030712'),
    ('Zinc', 'fafafa f4f4f5 e4e4e7 d4d4d8 a1a1aa 71717a 52525b 3f3f46 27272a 18181b 09090b'),
    ('Neutral', 'fafafa f5f5f5 e5e5e5 d4d4d4 a3a3a3 737373 525252 404040 262626 171717 0a0a0a'),
    ('Stone', 'fafaf9 f5f5f4 e7e5e4 d6d3d1 a8a29e 78716c 57534e 44403c 292524 1c1917 0c0a09'),
    ('Yellow Mud', 'fefee8 fcfdc5 fcfc8f faf54f f5e91d e2d10c c0a607 977b09 7c610f 695113 3d2c06'),
    ('Mud', 'fcfee8 f6fdc7 f0fb94 e7f756 def025 cbdb0f aeb609 8d8e0b 737110 625f13 383606'),
]

GRAYS = {'Slate', 'Gray', 'Zinc', 'Stone'}
FAMILIES = [(n, [s for s in v.split()]) for n, v in FAMILIES]

_M_RGB2XYZ = ((0.4124564390896922, 0.357576077643909, 0.18043748326639894),
              (0.21267285140562253, 0.715152155287818, 0.07217499330655958),
              (0.0193338955823293, 0.11919202588130297, 0.9503040785363679))
_WHITE = (0.95047, 1.0, 1.08883)
_KE = 216 / 24389
_KK = 24389 / 27

def _srgb_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def hex_to_lab(h):
    rgb = [_srgb_lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)]
    xyz = [sum(_M_RGB2XYZ[i][j] * rgb[j] for j in range(3)) / _WHITE[i] for i in range(3)]
    fx, fy, fz = [t ** (1 / 3) if t > _KE else (_KK * t + 16) / 116 for t in xyz]
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)

def delta_e(h1, h2):
    L1, a1, b1 = hex_to_lab(h1)
    L2, a2, b2 = hex_to_lab(h2)
    rad = math.radians
    deg = math.degrees
    Lm = (L1 + L2) / 2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    a1p, a2p = a1 * (1 + G), a2 * (1 + G)
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    Cmp = (C1p + C2p) / 2
    h1p, h2p = deg(math.atan2(b1, a1p)), deg(math.atan2(b2, a2p))
    h1p = h1p if h1p >= 0 else h1p + 360
    h2p = h2p if h2p >= 0 else h2p + 360
    Hm = (h1p + h2p + 360) / 2 if abs(h1p - h2p) > 180 else (h1p + h2p) / 2
    T = (1 - 0.17 * math.cos(rad(Hm - 30)) + 0.24 * math.cos(rad(2 * Hm))
         + 0.32 * math.cos(rad(3 * Hm + 6)) - 0.2 * math.cos(rad(4 * Hm - 63)))
    dh = h2p - h1p
    dh = dh if abs(dh) <= 180 else (dh + 360 if h2p <= h1p else dh - 360)
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(rad(dh) / 2)
    dL, dC = L2 - L1, C2p - C1p
    SL = 1 + 0.015 * (Lm - 50) ** 2 / math.sqrt(20 + (Lm - 50) ** 2)
    SC = 1 + 0.045 * Cmp
    SH = 1 + 0.015 * Cmp * T
    dTheta = 30 * math.exp(-(((Hm - 275) / 25) ** 2))
    RC = 2 * math.sqrt(Cmp ** 7 / (Cmp ** 7 + 25 ** 7))
    RT = -RC * math.sin(2 * rad(dTheta))
    d = math.sqrt((dL / SL) ** 2 + (dC / SC) ** 2 + (dHp / SH) ** 2 + RT * (dC / SC) * (dHp / SH))
    return max(0.0, min(100.0, d))

def _div(a, b):
    try:
        return a / b
    except ZeroDivisionError:
        return NAN if a == 0 or a != a else math.copysign(float('inf'), a)

def hex_to_hsl(h):
    r, g, b = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    mn, mx = min(r, g, b), max(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        return NAN, 0.0, l
    s = (mx - mn) / (mx + mn) if l < 0.5 else (mx - mn) / (2 - mx - mn)
    if r == mx:
        hh = (g - b) / (mx - mn)
    elif g == mx:
        hh = 2 + (b - r) / (mx - mn)
    else:
        hh = 4 + (r - g) / (mx - mn)
    hh *= 60
    if hh < 0:
        hh += 360
    return hh, s, l

def hsl_to_hex(h, s, l):
    if s == 0:
        rgb = [l * 255] * 3
    else:
        t2 = l * (1 + s) if l < 0.5 else l + s - l * s
        t1 = 2 * l - t2
        d = h / 360
        out = []
        for t3 in (d + 1 / 3, d, d - 1 / 3):
            if t3 < 0:
                t3 += 1
            if t3 > 1:
                t3 -= 1
            if 6 * t3 < 1:
                v = t1 + (t2 - t1) * 6 * t3
            elif 2 * t3 < 1:
                v = t2
            elif 3 * t3 < 2:
                v = t1 + (t2 - t1) * (2 / 3 - t3) * 6
            else:
                v = t1
            out.append(v * 255)
        rgb = out
    return ''.join('{:02x}'.format(0 if v != v else int(math.floor(max(0, min(255, v)) + 0.5))) for v in rgb)

def _fmod(a, b):
    return math.fmod(a, b) if a == a else NAN

def _pick_min(vals):
    k = 0
    for i in range(1, len(vals)):
        if not vals[k] < vals[i]:
            k = i
    return k

def closest_family(hx):
    sat = hex_to_hsl(hx)[1]
    fams = [(n, s) for n, s in FAMILIES if n != 'Neutral' and ((n in GRAYS) != (sat > 0.15))]
    best = None
    for n, shades in fams:
        deltas = [delta_e(hx, s) for s in shades]
        k = _pick_min(deltas)
        if best is None or not best[0] < deltas[k]:
            best = (deltas[k], n, shades)
    _, name, shades = best
    inp_l = hex_to_hsl(hx)[2]
    diffs = [abs(hex_to_hsl(s)[2] - inp_l) for s in shades]
    idx = _pick_min(diffs)
    return name, shades, idx

def build(hex_in, base=None):
    hx = hex_in.lstrip('#').lower()
    if len(hx) == 3:
        hx = ''.join(c * 2 for c in hx)
    name, shades, idx = closest_family(hx)
    hi, si, _ = hex_to_hsl(hx)
    hl, sl, _ = hex_to_hsl(shades[idx])
    shift = hi - (hl if hl == hl and hl != 0 else 0)
    ratio = _div(si, sl)
    pal = {}
    for k, sh in zip(SHADES, shades):
        hh, ss, ll = hex_to_hsl(sh)
        w = _fmod(hh + shift, 360)
        if w < 0:
            w += 360
        p = hsl_to_hex(hh, ss * ratio, ll)
        _, ps_, pl = hex_to_hsl(p)
        pal[k] = hsl_to_hex(w, ps_, pl)
    pal[SHADES[idx]] = hx
    used = SHADES[idx]
    if base is not None and base != used:
        pal = lock_shade(hx, pal, base)
        used = base
    return {k: v.upper() for k, v in pal.items()}, used

def lock_shade(hx, pal, base):
    hi, si, li = hex_to_hsl(hx)
    hr, sr, lr = hex_to_hsl(pal[base])
    lr *= 100
    dl, ds, dh = li * 100 - lr, si * 100 - sr * 100, hi - hr
    out = {}
    for k in SHADES:
        hh, ss, ll = hex_to_hsl(pal[k])
        L = ll * 100
        c = _div(L, lr) if L < lr + 1 else _div(100 - L, lr)
        c = min(1, c)
        p = hsl_to_hex(hh, ss, (L + c * dl) / 100)
        ph, ps_, pl = hex_to_hsl(p)
        p = hsl_to_hex(ph, (ss * 100 + ds) / 100, pl)
        ph, ps_, pl = hex_to_hsl(p)
        out[k] = hsl_to_hex(hh + dh, ps_, pl)
    out[base] = hx
    return out

ORDINALS = ['Primary', 'Secondary', 'Tertiary', 'Quaternary', 'Quinary',
            'Senary', 'Septenary', 'Octonary', 'Nonary', 'Denary']

def parse_color(arg):
    name = None
    hx = arg
    if '=' in arg:
        name, hx = arg.split('=', 1)
        name = name.strip() or None
    h = hx.strip().lstrip('#')
    if len(h) not in (3, 6) or any(c not in '0123456789abcdefABCDEF' for c in h):
        sys.exit(f'Invalid hex: "{arg}". Use 3 or 6 digits, for example F9AE00 or #F9AE00')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return name, h.upper()

def name_colors(parsed):
    out = []
    for i, (name, h) in enumerate(parsed):
        if not name:
            name = ORDINALS[i] if i < len(ORDINALS) else f'Color {i + 1}'
        out.append((name, h))
    names = [n.lower() for n, _ in out]
    dup = {n for n in names if names.count(n) > 1}
    if dup:
        sys.exit('Duplicate color names: ' + ', '.join(sorted(dup)))
    return out

def figma_alias(path):
    return {
        '$type': 'color',
        '$value': '{' + path + '}',
        '$extensions': {'com.figma.scopes': ['ALL_SCOPES']},
    }

def figma_token(hex6):
    r, g, b = [int(hex6[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return {
        '$type': 'color',
        '$value': {'colorSpace': 'srgb', 'components': [r, g, b], 'alpha': 1, 'hex': '#' + hex6},
        '$extensions': {'com.figma.scopes': ['ALL_SCOPES']},
    }

def figma_json(colors, base, mode, include_bw, bw_group='Tailwind'):
    out = {}
    if include_bw:
        out[bw_group] = {'White': figma_token('FFFFFF'), 'Black': figma_token('000000')}
    for name, h in colors:
        pal, used = build(h, base)
        print(f'{name}: #{h} placed at shade {used}', file=sys.stderr)
        group = {'DEFAULT': figma_alias(f'{name}.{used}')}
        group.update({str(k): figma_token(pal[k]) for k in SHADES})
        out[name] = group
    out['$extensions'] = {'com.figma.modeName': mode}
    return out

def safe_filename(name):
    return re.sub(r'[\\/:*?"<>|]+', '-', name).strip() or 'colors'

def color_values(hex6):
    r, g, b = [int(hex6[i:i + 2], 16) for i in (0, 2, 4)]
    rf, gf, bf = r / 255, g / 255, b / 255
    k = 1 - max(rf, gf, bf)
    if k >= 1:
        c = m = y = 0.0
    else:
        c, m, y = [(1 - v - k) / (1 - k) for v in (rf, gf, bf)]
    mx, mn = max(rf, gf, bf), min(rf, gf, bf)
    l = (mx + mn) / 2
    d = mx - mn
    if d == 0:
        h = sat = 0.0
    else:
        sat = d / (1 - abs(2 * l - 1))
        if mx == rf:
            h = ((gf - bf) / d) % 6
        elif mx == gf:
            h = (bf - rf) / d + 2
        else:
            h = (rf - gf) / d + 4
        h *= 60
    pct = lambda v: v * 100
    return (r, g, b), (pct(c), pct(m), pct(y), pct(k)), (h % 360, pct(sat), pct(l))

def fmt(v):
    return ('%.2f' % v).rstrip('0').rstrip('.')

def print_info(name, hex6):
    rgb, cmyk, hsl = color_values(hex6)
    print(f'{name}: #{hex6}')
    print(f'RGB: ({rgb[0]}, {rgb[1]}, {rgb[2]})')
    print('CMYK: (' + ', '.join(fmt(v) + '%' for v in cmyk) + ')')
    print(f'HSL: ({fmt(hsl[0])}, {fmt(hsl[1])}%, {fmt(hsl[2])}%)')

def print_simple(fmt, name, h, base, css_name):
    pal, used = build(h, base)
    print(f'{name}: #{h} placed at shade {used}', file=sys.stderr)
    orig = '#' + h
    if fmt == 'info':
        print_info('default', h)
    elif fmt == 'text':
        print(f'default: {orig}')
        for k in SHADES:
            print(f'{k}: #{pal[k]}')
    elif fmt == 'css':
        print('@theme {')
        print(f'  --color-{css_name}: var(--color-{css_name}-{used});')
        for k in SHADES:
            print(f'  --color-{css_name}-{k}: #{pal[k]};')
        print('}')
    elif fmt == 'tailwind':
        print('colors: {\n  ' + css_name + ': {')
        print(f"    DEFAULT: '{orig}',")
        for k in SHADES:
            print(f"    {k}: '#{pal[k]}',")
        print('  },\n}')
    else:
        print(json.dumps({'default': orig, **{str(k): '#' + pal[k] for k in SHADES}}, indent=2))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('colors', nargs='+', help='Hex (F9AE00, #F9AE00) or Name=Hex')
    ap.add_argument('--format', choices=['figma', 'info', 'text', 'css', 'tailwind', 'json'], default='figma')
    ap.add_argument('--filename', '--collection', dest='filename', default='Value', help='Name of the .json file (Figma uses it to name the mode when importing). Default: Value')
    ap.add_argument('--mode', default='Value', help='Mode name (values column) inside the JSON. Default: Value')
    ap.add_argument('--out-dir', default='.', help='Folder where the Figma JSON is saved')
    ap.add_argument('--bw-group', default='Tailwind', help='Name of the group that holds White and Black (default: Tailwind)')
    ap.add_argument('--no-bw', action='store_true', help='Do not include White and Black in the Figma JSON')
    ap.add_argument('--base', type=int, default=None, choices=SHADES,
                    help='Shade where the input color is placed (default: automatic)')
    ap.add_argument('--name', default='brand', help='Color name in css/tailwind formats (single color)')
    a = ap.parse_args()

    parsed = [parse_color(c) for c in a.colors]

    if a.format == 'figma':
        data = figma_json(name_colors(parsed), a.base, a.mode, not a.no_bw, a.bw_group)
        os.makedirs(a.out_dir, exist_ok=True)
        path = os.path.join(a.out_dir, safe_filename(a.filename) + '.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write('\n')
        print(f'FILE: {path}')
        print()
        colors = name_colors(parsed)
        for i, (name, h) in enumerate(colors):
            if len(colors) > 1:
                print(f'## {name}')
            print_info('default', h)
            if i < len(colors) - 1:
                print()
        return

    named = name_colors(parsed) if len(parsed) > 1 else [(parsed[0][0] or a.name, parsed[0][1])]
    for i, (name, h) in enumerate(named):
        if len(named) > 1:
            print(f'## {name}')
        print_simple(a.format, name, h, a.base, name.lower().replace(' ', '-') if len(named) > 1 or parsed[0][0] else a.name)
        if len(named) > 1 and i < len(named) - 1:
            print()

if __name__ == '__main__':
    main()
