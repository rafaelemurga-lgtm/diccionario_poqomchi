#!/usr/bin/env python3
"""raw_entries.json -> diccionario.db (SQLite) + diccionario.json

Tablas:
  entradas(id, palabra, palabra_norm, palabra_fuzzy, categoria, glosa, texto, sinonimos, pagina)
  indice_es(termino, entrada_id)   -- palabras del español (glosa) para buscar español -> poqomchi'
"""
import json, re, sqlite3, unicodedata, sys

RAW = '/home/claude/raw_entries.json'
OUT_DB = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/diccionario.db'
OUT_JSON = OUT_DB.replace('.db', '.json')

APOS = "’'‘`´ʼʻ"
STOP = set('de la el los las un una unos unas y o a en con por para que se su sus al del lo le les me mi es son ser '
           'esta este esto estos estas ese esa eso muy mas no si como ya fue qué cual cuando donde'.split())


def strip_accents(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def norm(s):
    s = strip_accents(s.lower())
    s = re.sub('[' + re.escape(APOS) + r'+\-–\.\?¿!¡:;,()\[\]=]', '', s)
    return re.sub(r'\s+', ' ', s).strip()


def fuzzy(s):
    """norm + vocales largas colapsadas (aa->a, ee->e...) para tolerar escritura sin vocal larga."""
    return re.sub(r'([aeiou])\1+', r'\1', norm(s))


def text_of(runs):
    return ''.join(t for _, t in runs)


def clean(s):
    s = s.replace('○', ' ')
    return re.sub(r'\s+', ' ', s).strip()


def load_entries():
    raw = json.load(open(RAW))
    merged = []
    for e in raw:
        t = clean(text_of(e['runs']))
        if e['page'] >= 852 or re.search(r'BIBLIOG', t):   # fin del diccionario
            break
        if not t or re.fullmatch(r'[\s○]*', t):
            continue
        first_bold = e['runs'][0][0] == 'b' and clean(e['runs'][0][1]) != ''
        if first_bold or not merged:
            merged.append({'page': e['page'], 'runs': [r[:] for r in e['runs']]})
        else:                                   # línea de continuación sin negrita
            merged[-1]['runs'].append(['n', ' '])
            merged[-1]['runs'].extend(r[:] for r in e['runs'])
    return merged


POS_RE = re.compile(r'^(?:\d\.-\s*)?((?:s|v|adj|adv|prep|pron|conj|part|num|interj)\.[a-z0-9\.\s]{0,12}?)(?=\s[^\s]|$)', re.I)
POS_TOKEN = re.compile(r'^(?:\d\.-\s*)?((?:s\.(?:n\.p|s\.p|c\.v|iv|st|a)|v\.(?:e\.i|d\.i|d\.e|d\.2|d|r|m\.r|mr|p)|adj|adv|f)\.|v\.d\.2)')


PROT = re.compile(r'\b(M|V|F|f|a|p|Tr|Intr|part|Sin[óo]n|fig|etc|pl|dim|Lit|lit|s|v|r|d|i|e|n|c|st|iv|m|adj|adv|Marc|pers|pref|pos)\.(?=\s?[A-Za-z0-9]|\s|-)')


def first_sentence(txt):
    t = PROT.sub(lambda m: m.group(0).replace('.', '\u2024'), txt)
    t = re.split(r'\.\s+', t, maxsplit=1)[0]
    t = re.split(r'\s(?:M\u2024\s?(?:Tr|Intr)\u2024|V\u2024\s?p\u2024|Sin[óo]n\u2024)', t, maxsplit=1)[0]
    return clean(t.replace('\u2024', '.')).rstrip('.')


def make_gloss(body):
    parts = re.split(r'(?:^|\s)\d\.-\s*', body)
    parts = [p for p in parts if p.strip()]
    glosses = []
    for p in parts[:4]:
        p = clean(p)
        mt = POS_TOKEN.match(p)
        if mt:
            p = clean(p[mt.end():])
        g = first_sentence(p)
        if re.match(r'^(M|V)\.', g):                     # forma gramatical: "M. Tr. de xxx"
            mm = re.match(r'(.*?\bde\s+[^\s.:]+)', g)
            g = clean(mm.group(1)) if mm else g
        elif ':' in g:                                    # se coló un ejemplo "poqomchi': español"
            pre = g.split(':', 1)[0]
            cut = max(pre.rfind('? '), pre.rfind('. '))
            g = pre[:cut + 1] if cut > 0 else pre
        g = clean(g).rstrip('.')
        if g and g not in glosses:
            glosses.append(g)
    g = '; '.join(glosses)
    if len(g) < 2:
        mm = re.match(r'(.*?\bde\s+[^\s.:]+)', body)
        g = clean(mm.group(1)) if mm else clean(body[:80])
    return g


def parse(e):
    runs = e['runs']
    # palabra clave = texto en negrita inicial
    head = ''
    i = 0
    while i < len(runs) and runs[i][0] == 'b':
        head += runs[i][1]
        i += 1
    rest = ''.join(t for _, t in runs[i:])
    if ':' in head:                              # los dos puntos venían dentro de la negrita
        head, extra = head.split(':', 1)
        rest = extra + rest
    head = clean(head)
    rest = clean(rest.lstrip(' :'))
    if not head or len(head) > 60:
        return None
    pos = ''
    m = POS_TOKEN.match(rest)
    body = rest
    if m:
        pos = m.group(1).rstrip('.') + '.'
        body = clean(rest[m.end():])
    # categoría para formas gramaticales ("M. Tr. de ...", "V. p. de ...")
    if not pos:
        mg = re.match(r'^(?:\d\.-\s*)?(M\.\s?(?:Tr|Intr)\.(?:\s(?:part|f\.\s?a)\.)?|V\.\s?p\.)', body)
        if mg:
            pos = clean(mg.group(1))
    gloss = make_gloss(body)
    syn = ''
    ms = re.search(r'Sin[óo]n\.\s*([^.]+)\.', body)
    if ms:
        syn = clean(ms.group(1))
    return {
        'palabra': head,
        'palabra_norm': norm(head),
        'palabra_fuzzy': fuzzy(head),
        'categoria': pos,
        'glosa': gloss,
        'texto': clean(rest),
        'sinonimos': syn,
        'pagina': e['page'],
    }


def spanish_terms(gloss):
    g = re.sub(r'\(.*?\)', ' ', gloss)
    out = set()
    for w in re.findall(r"[a-záéíóúüñ]+", g.lower()):
        if len(w) >= 3 and w not in STOP:
            out.add(strip_accents(w))
    return out


def main():
    entries = [p for p in (parse(e) for e in load_entries()) if p]
    for n, p in enumerate(entries, 1):
        p['id'] = n
    json.dump(entries, open(OUT_JSON, 'w'), ensure_ascii=False, indent=0)

    import os
    if os.path.exists(OUT_DB):
        os.remove(OUT_DB)
    db = sqlite3.connect(OUT_DB)
    db.executescript('''
    CREATE TABLE entradas(
      id INTEGER PRIMARY KEY, palabra TEXT, palabra_norm TEXT, palabra_fuzzy TEXT,
      categoria TEXT, glosa TEXT, texto TEXT, sinonimos TEXT, pagina INTEGER);
    CREATE TABLE indice_es(termino TEXT, entrada_id INTEGER);
    ''')
    db.executemany('INSERT INTO entradas VALUES(?,?,?,?,?,?,?,?,?)',
                   [(p['id'], p['palabra'], p['palabra_norm'], p['palabra_fuzzy'], p['categoria'],
                     p['glosa'], p['texto'], p['sinonimos'], p['pagina']) for p in entries])
    rows = [(t, p['id']) for p in entries for t in spanish_terms(p['glosa'])]
    db.executemany('INSERT INTO indice_es VALUES(?,?)', rows)
    db.executescript('''
    CREATE INDEX ix_norm ON entradas(palabra_norm);
    CREATE INDEX ix_fuzzy ON entradas(palabra_fuzzy);
    CREATE INDEX ix_es ON indice_es(termino);
    ''')
    db.commit(); db.execute('VACUUM'); db.close()
    print('entradas:', len(entries), '| términos en español:', len(rows))


if __name__ == '__main__':
    main()
