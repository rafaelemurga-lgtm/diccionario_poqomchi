import 'dart:async';

import 'package:flutter/material.dart';

import 'dictionary_db.dart';

void main() => runApp(const DiccionarioApp());

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
      appBar: AppBar(title: const Text('Diccionario Poqomchi’')),
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
            '“ab’aj” o “abaj”.',
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
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = _results[i];
        return ListTile(
          title: Text(
            e.palabra,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(e.glosa, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: e.categoria.isEmpty
              ? null
              : Text(e.categoria, style: theme.textTheme.labelSmall),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EntryPage(entry: e)),
          ),
        );
      },
    );
  }
}

class EntryPage extends StatelessWidget {
  const EntryPage({super.key, required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(entry.palabra)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
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
            const SizedBox(height: 24),
            Text(
              'Diccionario Poqomchi’ – Español (PROASE, 2003), p. ${entry.pagina}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
