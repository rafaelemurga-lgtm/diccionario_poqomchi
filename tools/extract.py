#!/usr/bin/env python3
"""Extrae las entradas del Diccionario Poqomchi' (PROASE 2003) del PDF.

- Maneja el diseño a dos columnas con sangría francesa.
- Decodifica las páginas con la capa de texto corrupta ((cid:N) = glyph id).
- Conserva el estilo (negrita / cursiva / normal) de cada fragmento.
Salida: raw_entries.json  (lista de {page, runs:[[estilo, texto], ...]})
"""
import json, re, sys
from multiprocessing import Pool
import pdfplumber

PDF = sys.argv[1] if len(sys.argv) > 1 else '/mnt/user-data/uploads/Diccionario_PQM_2003.pdf'
FIRST, LAST = 17, int(sys.argv[2]) if len(sys.argv) > 2 else 851

# glyph id -> carácter, para las páginas con fuente sin mapeo Unicode
SPECIAL = {105: 'á', 112: 'é', 116: 'í', 121: 'ó', 126: 'ú', 120: 'ñ', 129: 'ü',
           163: '¡', 162: '¿', 182: '’', 177: '–', 179: '“', 180: '”',
           98: 'Á', 101: 'É', 102: 'Ñ', 103: 'Ó', 104: 'Ü'}


def decode(txt):
    m = re.fullmatch(r'\(cid:(\d+)\)', txt)
    if not m:
        return txt
    g = int(m.group(1))
    if g in SPECIAL:
        return SPECIAL[g]
    if 3 <= g <= 97:
        return chr(g + 29)
    return '?'


def style(font):
    f = font.lower()
    bold = 'bold' in f
    ital = 'italic' in f or 'oblique' in f
    return 'b' if bold else ('i' if ital else 'n')


_PDF = None


def page_entries(pn):
    global _PDF
    if _PDF is None:
        _PDF = pdfplumber.open(PDF)
    page = _PDF.pages[pn - 1]
    chars = [c for c in page.chars if c['top'] < 565 and not c['fontname'].endswith('ComicSansMS')]
    if len(chars) < 400:                    # portadilla de letra, sin entradas
        return []
    c1 = min(c['x0'] for c in chars)
    split = c1 + 190
    out = []
    for col, base in ((0, c1), (1, c1 + 196)):
        cc = [c for c in chars if (c['x0'] < split) == (col == 0)]
        cc.sort(key=lambda c: (c['top'], c['x0']))
        # agrupar en líneas por 'top'
        lines, cur, ytop = [], [], None
        for c in cc:
            if ytop is None or abs(c['top'] - ytop) <= 3:
                cur.append(c)
                ytop = c['top'] if ytop is None else ytop
            else:
                lines.append(cur); cur = [c]; ytop = c['top']
        if cur:
            lines.append(cur)
        for ln in lines:
            ln.sort(key=lambda c: c['x0'])
            runs, last_x1 = [], None
            for c in ln:
                t = decode(c['text'])
                if last_x1 is not None and c['x0'] - last_x1 > 1.5 and t != ' ':
                    runs.append(['n', ' ']) if not (runs and runs[-1][1].endswith(' ')) else None
                st = style(c['fontname'])
                if runs and runs[-1][0] == st:
                    runs[-1][1] += t
                else:
                    runs.append([st, t])
                last_x1 = c['x1']
            out.append({'page': pn, 'start': (ln[0]['x0'] - base) < 6, 'runs': runs})
    page.flush_cache()
    return out


def merge(lines):
    entries = []
    for ln in lines:
        if ln['start'] or not entries:
            entries.append({'page': ln['page'], 'runs': [r[:] for r in ln['runs']]})
        else:
            e = entries[-1]
            e['runs'].append(['n', ' '])
            e['runs'].extend(r[:] for r in ln['runs'])
    return entries


if __name__ == '__main__':
    with Pool(4) as p:
        pages = p.map(page_entries, range(FIRST, LAST + 1), chunksize=8)
    lines = [ln for pg in pages for ln in pg]
    entries = merge(lines)
    json.dump(entries, open('/home/claude/raw_entries.json', 'w'), ensure_ascii=False)
    print('líneas', len(lines), 'entradas', len(entries))
