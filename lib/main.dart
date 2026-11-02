import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dictionary_db.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  runApp(const DiccionarioApp());
}

class DiccionarioApp extends StatelessWidget {
  const DiccionarioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diccionario Poqomchi’',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

Future<bool> _confirm(
    BuildContext context, String title, String message, String action) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

// =============================================================== PANTALLA PRINCIPAL

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  DictionaryDb? _db;
  Object? _error;
  int _total = 0;
  Direction _dir = Direction.pqmToEs;
  List<Entry> _results = [];
  Timer? _debounce;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final db = await DictionaryDb.open();
      final n = await db.count();
      if (!mounted) return;
      setState(() {
        _db = db;
        _total = n;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _onChanged(String _) {
    setState(() {}); // actualiza el botón de borrar texto
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _runSearch);
  }

  Future<void> _runSearch() async {
    final db = _db;
    if (db == null) return;
    final seq = ++_searchSeq;
    final res = await db.search(_controller.text, _dir);
    if (!mounted || seq != _searchSeq) return; // descarta resultados viejos
    setState(() => _results = res);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEntry(Entry e) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EntryPage(entry: e, db: _db!)),
    );
    if (changed == true) _runSearch();
  }

  Future<void> _addWord() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditEntryPage(db: _db!)),
    );
    if (saved == true) {
      _snack('Palabra agregada');
      _runSearch();
    }
  }

  Future<void> _openContributions() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ContributionsPage(db: _db!)),
    );
    _runSearch();
  }

  Future<void> _exportBackup() async {
    final json = await _db!.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    _snack('Respaldo copiado. Pégalo en tus notas, correo o WhatsApp para guardarlo.');
  }

  Future<void> _importBackup() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar respaldo'),
        content: TextField(
          controller: c,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Pega aquí el respaldo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              c.text = data?.text ?? '';
            },
            child: const Text('Pegar'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Importar')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final n = await _db!.importJson(text);
      _snack('Se importaron $n aportes');
      _runSearch();
    } on FormatException {
      _snack('Ese texto no es un respaldo válido');
    } catch (e) {
      _snack('No se pudo importar: $e');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diccionario Poqomchi’'),
        actions: [
          if (_db != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'mine':
                    _openContributions();
                  case 'export':
                    _exportBackup();
                  case 'import':
                    _importBackup();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'mine', child: Text('Mis aportes')),
                PopupMenuItem(value: 'export', child: Text('Copiar respaldo')),
                PopupMenuItem(value: 'import', child: Text('Importar respaldo')),
              ],
            ),
        ],
      ),
      floatingActionButton: _db == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addWord,
              icon: const Icon(Icons.add),
              label: const Text('Agregar palabra'),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<Direction>(
                segments: const [
                  ButtonSegment(
                    value: Direction.pqmToEs,
                    label: Text('Poqomchi’ → Español'),
                  ),
                  ButtonSegment(
                    value: Direction.esToPqm,
                    label: Text('Español → Poqomchi’'),
                  ),
                ],
                selected: {_dir},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _dir = s.first);
                  _runSearch();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: _dir == Direction.pqmToEs
                      ? 'Escribe una palabra en poqomchi’…'
                      : 'Escribe una palabra en español…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _results = []);
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null) {
      return Center(child: Text('No se pudo abrir el diccionario:\n$_error'));
    }
    if (_db == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '$_total entradas\nFunciona sin internet.\n\n'
            'Puedes buscar con o sin saltillos (’) y con vocales simples: '
            '“ab’aj” o “abaj”.\n\n'
            'Usa “Agregar palabra” para sumar tus propios términos.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('Sin resultados'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = _results[i];
        final tag = e.isNew ? 'nueva' : (e.isEdited ? 'editada' : '');
        return ListTile(
          title: Text.rich(TextSpan(children: [
            TextSpan(
              text: e.palabra,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (tag.isNotEmpty)
              TextSpan(
                text: '   $tag',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
          ])),
          subtitle: Text(e.glosa, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: e.categoria.isEmpty
              ? null
              : Text(e.categoria, style: theme.textTheme.labelSmall),
          onTap: () => _openEntry(e),
        );
      },
    );
  }
}

// ======================================================================== DETALLE

class EntryPage extends StatelessWidget {
  const EntryPage({super.key, required this.entry, required this.db});
  final Entry entry;
  final DictionaryDb db;

  Future<void> _edit(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditEntryPage(db: db, entry: entry)),
    );
    if (saved == true && context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _onMenu(BuildContext context, String action) async {
    if (action == 'hide') {
      final ok = await _confirm(
        context,
        'Ocultar entrada',
        'Dejará de aparecer en las búsquedas. Puedes restaurarla en '
            '“Mis aportes”.',
        'Ocultar',
      );
      if (!ok) return;
      await db.hideBase(entry);
    } else if (action == 'restore') {
      final ok = await _confirm(
        context,
        'Restaurar original',
        'Se descartará tu edición y volverá la entrada del diccionario '
            'original.',
        'Restaurar',
      );
      if (!ok) return;
      await db.restoreBase(entry.baseId!);
    } else if (action == 'delete') {
      final ok = await _confirm(
        context,
        'Eliminar palabra',
        'Se borrará esta palabra que agregaste. No se puede deshacer.',
        'Eliminar',
      );
      if (!ok) return;
      await db.deleteUser(entry.userId!);
    }
    if (context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = entry.isNew
        ? 'Palabra agregada por ti'
        : (entry.isEdited ? 'Entrada original editada por ti' : '');
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.palabra),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit),
            onPressed: () => _edit(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, v),
            itemBuilder: (_) => [
              if (entry.isNew)
                const PopupMenuItem(value: 'delete', child: Text('Eliminar palabra')),
              if (entry.isEdited)
                const PopupMenuItem(
                    value: 'restore', child: Text('Restaurar original')),
              if (entry.isOriginal)
                const PopupMenuItem(value: 'hide', child: Text('Ocultar entrada')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (note.isNotEmpty) ...[
              Text(note,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 8),
            ],
            SelectableText(
              entry.palabra,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (entry.categoria.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.categoria, style: theme.textTheme.labelLarge),
            ],
            const SizedBox(height: 16),
            SelectableText(entry.glosa, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Entrada completa', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(entry.texto, style: theme.textTheme.bodyLarge),
            if (entry.sinonimos.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Sinónimo(s)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(entry.sinonimos),
            ],
            if (!entry.isNew && entry.pagina > 0) ...[
              const SizedBox(height: 24),
              Text(
                'Diccionario Poqomchi’ – Español (PROASE, 2003), p. ${entry.pagina}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================================================================== AGREGAR / EDITAR

class EditEntryPage extends StatefulWidget {
  const EditEntryPage({super.key, required this.db, this.entry});
  final DictionaryDb db;
  final Entry? entry; // null = palabra nueva

  @override
  State<EditEntryPage> createState() => _EditEntryPageState();
}

class _EditEntryPageState extends State<EditEntryPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _palabra;
  late final TextEditingController _categoria;
  late final TextEditingController _glosa;
  late final TextEditingController _texto;
  late final TextEditingController _sinonimos;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _palabra = TextEditingController(text: e?.palabra ?? '');
    _categoria = TextEditingController(text: e?.categoria ?? '');
    _glosa = TextEditingController(text: e?.glosa ?? '');
    _texto = TextEditingController(text: e?.texto ?? '');
    _sinonimos = TextEditingController(text: e?.sinonimos ?? '');
  }

  @override
  void dispose() {
    _palabra.dispose();
    _categoria.dispose();
    _glosa.dispose();
    _texto.dispose();
    _sinonimos.dispose();
    super.dispose();
  }

  /// Inserta el saltillo (’) en la posición del cursor.
  void _insertSaltillo(TextEditingController c) {
    final sel = c.selection;
    final start = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, end, '’'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  Widget _saltilloButton(TextEditingController c) => IconButton(
        tooltip: 'Insertar saltillo (’)',
        icon: const Text('’',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        onPressed: () => _insertSaltillo(c),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final e = widget.entry;
    try {
      await widget.db.saveEntry(
        userId: e?.userId,
        baseId: e?.baseId,
        palabraOriginal: (e != null && e.isOriginal) ? e.palabra : null,
        palabra: _palabra.text,
        categoria: _categoria.text,
        glosa: _glosa.text,
        texto: _texto.text,
        sinonimos: _sinonimos.text,
        pagina: e?.pagina ?? 0,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar entrada' : 'Agregar palabra'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Guardar'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _palabra,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Palabra en poqomchi’ *',
                  border: const OutlineInputBorder(),
                  suffixIcon: _saltilloButton(_palabra),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escribe la palabra'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _glosa,
                decoration: const InputDecoration(
                  labelText: 'Significado en español *',
                  hintText: 'p. ej.: piedra, roca',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escribe el significado'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoria,
                decoration: const InputDecoration(
                  labelText: 'Categoría (opcional)',
                  hintText: 'p. ej.: s.n.p., v.d.i.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _texto,
                minLines: 3,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: 'Entrada completa / ejemplos (opcional)',
                  helperText:
                      'Si lo dejas vacío se usará “palabra: significado”.',
                  border: const OutlineInputBorder(),
                  suffixIcon: _saltilloButton(_texto),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sinonimos,
                decoration: const InputDecoration(
                  labelText: 'Sinónimos (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================= MIS APORTES

class ContributionsPage extends StatefulWidget {
  const ContributionsPage({super.key, required this.db});
  final DictionaryDb db;

  @override
  State<ContributionsPage> createState() => _ContributionsPageState();
}

class _ContributionsPageState extends State<ContributionsPage> {
  List<Entry>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.listAportes();
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _edit(Entry e) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => EditEntryPage(db: widget.db, entry: e)),
    );
    _load();
  }

  Future<void> _remove(Entry e) async {
    final ok = await _confirm(
      context,
      e.isNew ? 'Eliminar palabra' : 'Restaurar original',
      e.isNew
          ? 'Se borrará esta palabra que agregaste. No se puede deshacer.'
          : 'Volverá a verse la entrada del diccionario original.',
      e.isNew ? 'Eliminar' : 'Restaurar',
    );
    if (!ok) return;
    if (e.isNew) {
      await widget.db.deleteUser(e.userId!);
    } else {
      await widget.db.restoreBase(e.baseId!);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis aportes')),
      body: SafeArea(
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aún no has agregado ni editado nada.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = items[i];
                      final kind = e.hidden
                          ? 'Entrada original oculta'
                          : (e.isNew
                              ? 'Palabra nueva'
                              : 'Edición de una entrada original');
                      return ListTile(
                        title: Text(
                          e.palabra,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration:
                                e.hidden ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text('$kind\n${e.glosa}',
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        onTap: e.hidden ? null : () => _edit(e),
                        trailing: e.isNew
                            ? IconButton(
                                tooltip: 'Eliminar',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _remove(e),
                              )
                            : TextButton(
                                onPressed: () => _remove(e),
                                child: const Text('Restaurar'),
                              ),
                      );
                    },
                  ),
      ),
    );
  }
}
