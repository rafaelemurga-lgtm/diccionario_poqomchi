# Diccionario Poqomchi' – Español (Flutter, offline)

Contiene 21,549 entradas extraídas del PDF *Diccionario Poqomchi'* (PROASE, 2003).

## Ejecutar la app
```bash
flutter create diccionario_poqomchi      # genera android/ios/etc.
# copia sobre ese proyecto: lib/, assets/ y pubspec.yaml de esta carpeta
cd diccionario_poqomchi
rm -f test/widget_test.dart              # el test de ejemplo ya no aplica
flutter pub get
flutter run
```

## Cómo se generó la base de datos (carpeta `tools/`)
```bash
pip install pdfplumber
python3 tools/extract.py Diccionario_PQM_2003.pdf 856   # -> raw_entries.json
python3 tools/build_db.py                               # -> diccionario.db
```
(las rutas dentro de los scripts apuntan a /home/claude y /mnt/user-data; ajústalas).
Las páginas 381-408, 478-509 y otras tenían la capa de texto del PDF con un
código desplazado; `extract.py` las decodifica automáticamente.

## Búsqueda
- Poqomchi' → Español: ignora saltillos (’), acentos y colapsa vocales largas (aa → a).
- Español → Poqomchi': usa un índice de palabras de las glosas en español.

## Revisión pendiente
La extracción es automática; conviene revisar entradas con glosas raras
(p. ej. formas gramaticales "M. Tr. de …") antes de publicar.
Verifica además los derechos de uso del diccionario (ALMG / PROASE / autor Marcel Dobbels).
