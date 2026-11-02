import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Si actualizas assets/diccionario.db, sube este número para que la app
/// vuelva a copiar la base original al teléfono (o al navegador en web).
/// Los aportes del usuario viven en otro archivo (aportes.db) y NO se tocan.
const int kDbVersion = 1;

const String _backupFormat = 'diccionario_poqomchi_aportes';

enum Direction { pqmToEs, esToPqm }

class Entry {
  /// id en el diccionario original (null = palabra nueva agregada por el usuario).
  final int? baseId;

  /// id en la tabla de aportes (null = entrada original sin modificar).
  final int? userId;
  final String palabra;
  final String categoria;
  final String glosa;
  final String texto;
  final String sinonimos;
  final int pagina;

  /// Entrada original que el usuario ocultó.
  final bool hidden;

  const Entry({
    this.baseId,
    this.userId,
    required this.palabra,
    required this.categoria,
    required this.glosa,
    required this.texto,
    required this.sinonimos,
    required this.pagina,
    this.hidden = false,
  });

  bool get isNew => baseId == null;
  bool get isEdited => baseId != null && userId != null && !hidden;
  bool get isOriginal => userId == null;

  factory Entry.fromBase(Map<String, Object?> m) => Entry(
        baseId: m['id'] as int,
        palabra: (m['palabra'] ?? '') as String,
        categoria: (m['categoria'] ?? '') as String,
        glosa: (m['glosa'] ?? '') as String,
        texto: (m['texto'] ?? '') as String,
        sinonimos: (m['sinonimos'] ?? '') as String,
        pagina: (m['pagina'] ?? 0) as int,
      );

  factory Entry.fromUser(Map<String, Object?> m) => Entry(
        baseId: m['base_id'] as int?,
        userId: m['id'] as int,
        palabra: (m['palabra'] ?? '') as String,
        categoria: (m['categoria'] ?? '') as String,
        glosa: (m['glosa'] ?? '') as String,
        texto: (m['texto'] ?? '') as String,
        sinonimos: (m['sinonimos'] ?? '') as String,
        pagina: (m['pagina'] ?? 0) as int,
        hidden: ((m['eliminado'] ?? 0) as int) == 1,
      );
}

const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n',
};

final _ignored = RegExp(r"[’'‘`´ʼʻ+\-–\.\?¿!¡:;,()\[\]=%_]");

/// Misma normalización que tools/build_db.py: minúsculas, sin acentos,
/// sin apóstrofos (saltillos) ni signos.
String normalize(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(_ignored, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Además colapsa vocales largas (aa -> a) para tolerar escritura simplificada.
String fuzzy(String s) =>
    normalize(s).replaceAllMapped(RegExp(r'([aeiou])\1+'), (m) => m.group(1)!);

class DictionaryDb {
  DictionaryDb._(this._base, this._user);

  final Database _base; // diccionario original (solo se consulta)
  final Database _user; // aportes del usuario, lectura y escritura
  Set<int> _overridden = {}; // ids originales editados u ocultos

  static const _aportesSchema = '''
    CREATE TABLE aportes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      base_id INTEGER,
      eliminado INTEGER NOT NULL DEFAULT 0,
      palabra TEXT NOT NULL,
      palabra_norm TEXT NOT NULL,
      palabra_fuzzy TEXT NOT NULL,
      categoria TEXT NOT NULL DEFAULT '',
      glosa TEXT NOT NULL DEFAULT '',
      glosa_norm TEXT NOT NULL DEFAULT '',
      texto TEXT NOT NULL DEFAULT '',
      sinonimos TEXT NOT NULL DEFAULT '',
      pagina INTEGER NOT NULL DEFAULT 0,
      palabra_original TEXT,
      actualizado TEXT NOT NULL
    )''';

  static Future<void> _onCreateAportes(Database db, int version) async {
    await db.execute(_aportesSchema);
    await db.execute(
        'CREATE UNIQUE INDEX ux_base ON aportes(base_id) WHERE base_id IS NOT NULL');
  }

  static Future<DictionaryDb> open() async {
    final Database base;
    final Database user;

    if (kIsWeb) {
      // En web no hay carpetas: las bases viven en el almacenamiento del
      // navegador (IndexedDB) y se identifican solo por su nombre.
      final baseName = 'diccionario_v$kDbVersion.db';
      if (!await databaseFactory.databaseExists(baseName)) {
        final data = await rootBundle.load('assets/diccionario.db');
        await databaseFactory.writeDatabaseBytes(
          baseName,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      base = await openDatabase(baseName);
      user = await openDatabase(
        'aportes.db',
        version: 1,
        onCreate: _onCreateAportes,
      );
    } else {
      final dir = await getApplicationDocumentsDirectory();

      final basePath = p.join(dir.path, 'diccionario_v$kDbVersion.db');
      if (!await File(basePath).exists()) {
        final data = await rootBundle.load('assets/diccionario.db');
        await File(basePath).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      base = await openDatabase(basePath, readOnly: true);
      user = await openDatabase(
        p.join(dir.path, 'aportes.db'),
        version: 1,
        onCreate: _onCreateAportes,
      );
    }

    final d = DictionaryDb._(base, user);
    await d._refreshOverridden();
    return d;
  }

  Future<void> _refreshOverridden() async {
    final r = await _user
        .rawQuery('SELECT base_id FROM aportes WHERE base_id IS NOT NULL');
    _overridden = r.map((e) => e['base_id'] as int).toSet();
  }

  Future<int> count() async {
    final r = await _base.rawQuery('SELECT COUNT(*) AS n FROM entradas');
    return (r.first['n'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------- búsqueda

  Future<List<Entry>> search(String query, Direction dir,
      {int limit = 80}) async {
    final n = normalize(query);
    if (n.isEmpty) return [];
    final extra = _overridden.length;
    final user = dir == Direction.pqmToEs
        ? await _userPqm(query, limit)
        : await _userEs(query, limit);
    final base = dir == Direction.pqmToEs
        ? await _searchPqm(query, limit + extra)
        : await _searchEs(query, limit + extra);
    final visible = base.where((e) => !_overridden.contains(e.baseId));
    return [...user, ...visible].take(limit).toList(); // tus aportes primero
  }

  Future<List<Entry>> _userPqm(String query, int limit) async {
    final n = normalize(query);
    final f = fuzzy(query);
    final rows = await _user.rawQuery('''
      SELECT * FROM aportes
      WHERE eliminado = 0 AND (palabra_norm LIKE ? OR palabra_fuzzy LIKE ?
                               OR palabra_norm LIKE ? OR palabra_fuzzy LIKE ?)
      ORDER BY CASE WHEN palabra_norm = ? THEN 0 ELSE 1 END,
               length(palabra_norm)
      LIMIT ?''', ['$n%', '$f%', '%$n%', '%$f%', n, limit]);
    return rows.map(Entry.fromUser).toList();
  }

  Future<List<Entry>> _userEs(String query, int limit) async {
    final tokens = normalize(query).split(' ').where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return [];
    final where = tokens.map((_) => 'glosa_norm LIKE ?').join(' AND ');
    final rows = await _user.rawQuery(
      'SELECT * FROM aportes WHERE eliminado = 0 AND $where '
      'ORDER BY length(glosa) LIMIT ?',
      [...tokens.map((t) => '%$t%'), limit],
    );
    return rows.map(Entry.fromUser).toList();
  }

  Future<List<Entry>> _searchPqm(String query, int limit) async {
    final n = normalize(query);
    final f = fuzzy(query);
    var rows = await _base.rawQuery('''
      SELECT * FROM entradas
      WHERE palabra_norm LIKE ? OR palabra_fuzzy LIKE ?
      ORDER BY CASE WHEN palabra_norm = ? THEN 0
                    WHEN palabra_fuzzy = ? THEN 1
                    WHEN palabra_norm LIKE ? THEN 2 ELSE 3 END,
               length(palabra_norm), palabra_norm
      LIMIT ?''', ['$n%', '$f%', n, f, '$n%', limit]);
    // Pocas coincidencias por prefijo: ampliar a "contiene".
    if (rows.length < 10) {
      final more = await _base.rawQuery('''
        SELECT * FROM entradas
        WHERE palabra_norm LIKE ? OR palabra_fuzzy LIKE ?
        ORDER BY length(palabra_norm) LIMIT ?''', ['%$n%', '%$f%', limit]);
      final seen = rows.map((r) => r['id']).toSet();
      rows = [...rows, ...more.where((r) => !seen.contains(r['id']))]
          .take(limit)
          .toList();
    }
    return rows.map(Entry.fromBase).toList();
  }

  Future<List<Entry>> _searchEs(String query, int limit) async {
    final tokens = normalize(query).split(' ')
      ..sort((a, b) => b.length - a.length);
    final main = tokens.first;
    final rows = await _base.rawQuery('''
      SELECT e.*, MIN(CASE WHEN i.termino = ? THEN 0 ELSE 1 END) AS rango
      FROM indice_es i JOIN entradas e ON e.id = i.entrada_id
      WHERE i.termino LIKE ?
      GROUP BY e.id
      ORDER BY rango, length(e.glosa)
      LIMIT ?''', [main, '$main%', limit * 3]);
    final rest = tokens.skip(1).toList();
    return rows
        .map(Entry.fromBase)
        .where((e) => rest.every((t) => normalize(e.glosa).contains(t)))
        .take(limit)
        .toList();
  }

  // ------------------------------------------------------------------ aportes

  Map<String, Object?> _values({
    required int? baseId,
    required bool hidden,
    required String palabra,
    required String categoria,
    required String glosa,
    required String texto,
    required String sinonimos,
    required int pagina,
    required String? palabraOriginal,
  }) {
    final w = palabra.trim();
    final g = glosa.trim();
    final t = texto.trim();
    return {
      'base_id': baseId,
      'eliminado': hidden ? 1 : 0,
      'palabra': w,
      'palabra_norm': normalize(w),
      'palabra_fuzzy': fuzzy(w),
      'categoria': categoria.trim(),
      'glosa': g,
      'glosa_norm': normalize(g),
      'texto': t.isEmpty ? '$w: $g' : t,
      'sinonimos': sinonimos.trim(),
      'pagina': pagina,
      'palabra_original': palabraOriginal,
      'actualizado': DateTime.now().toIso8601String(),
    };
  }

  /// Agrega una palabra nueva, o guarda la edición de una existente:
  ///  - nueva:                userId == null, baseId == null
  ///  - editar original:      userId == null, baseId != null
  ///  - editar tu aporte:     userId != null
  Future<void> saveEntry({
    int? userId,
    int? baseId,
    String? palabraOriginal,
    required String palabra,
    String categoria = '',
    required String glosa,
    String texto = '',
    String sinonimos = '',
    int pagina = 0,
  }) async {
    final values = _values(
      baseId: baseId,
      hidden: false,
      palabra: palabra,
      categoria: categoria,
      glosa: glosa,
      texto: texto,
      sinonimos: sinonimos,
      pagina: pagina,
      palabraOriginal: palabraOriginal,
    );
    if (userId != null) {
      values.remove('base_id');
      values.remove('palabra_original');
      await _user
          .update('aportes', values, where: 'id = ?', whereArgs: [userId]);
    } else {
      await _user.insert('aportes', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _refreshOverridden();
  }

  /// Oculta una entrada del diccionario original (reversible).
  Future<void> hideBase(Entry e) async {
    await _user.insert(
      'aportes',
      _values(
        baseId: e.baseId,
        hidden: true,
        palabra: e.palabra,
        categoria: e.categoria,
        glosa: e.glosa,
        texto: e.texto,
        sinonimos: e.sinonimos,
        pagina: e.pagina,
        palabraOriginal: e.palabra,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _refreshOverridden();
  }

  /// Quita la edición u ocultamiento: vuelve a verse la entrada original.
  Future<void> restoreBase(int baseId) async {
    await _user.delete('aportes', where: 'base_id = ?', whereArgs: [baseId]);
    await _refreshOverridden();
  }

  /// Elimina una palabra nueva creada por el usuario.
  Future<void> deleteUser(int userId) async {
    await _user.delete('aportes', where: 'id = ?', whereArgs: [userId]);
    await _refreshOverridden();
  }

  Future<List<Entry>> listAportes() async {
    final rows = await _user.query('aportes', orderBy: 'actualizado DESC');
    return rows.map(Entry.fromUser).toList();
  }

  Future<int> userCount() async {
    final r = await _user.rawQuery('SELECT COUNT(*) AS n FROM aportes');
    return (r.first['n'] as int?) ?? 0;
  }

  // ------------------------------------------------------------------ respaldo

  Future<String> exportJson() async {
    final rows = await _user.query('aportes', orderBy: 'id');
    final list = rows.map((r) {
      final m = Map<String, Object?>.from(r);
      m.remove('id');
      return m;
    }).toList();
    return jsonEncode({
      'formato': _backupFormat,
      'version': 1,
      'exportado': DateTime.now().toIso8601String(),
      'aportes': list,
    });
  }

  /// Importa un respaldo. Devuelve cuántos aportes se incorporaron.
  /// Lanza FormatException si el texto no es un respaldo válido.
  Future<int> importJson(String source) async {
    final dynamic data = jsonDecode(source.trim());
    if (data is! Map ||
        data['formato'] != _backupFormat ||
        data['aportes'] is! List) {
      throw const FormatException('Formato de respaldo no reconocido');
    }
    var count = 0;
    await _user.transaction((txn) async {
      for (final raw in data['aportes'] as List) {
        if (raw is! Map) continue;
        final palabra = (raw['palabra'] ?? '').toString().trim();
        final glosa = (raw['glosa'] ?? '').toString().trim();
        final hidden = raw['eliminado'] == 1;
        if (palabra.isEmpty || (!hidden && glosa.isEmpty)) continue;
        final baseId = raw['base_id'] is int ? raw['base_id'] as int : null;
        if (baseId == null) {
          final dup = await txn.rawQuery(
              'SELECT 1 FROM aportes WHERE base_id IS NULL AND palabra = ? '
              'AND glosa = ? LIMIT 1',
              [palabra, glosa]);
          if (dup.isNotEmpty) continue; // ya existe
        }
        await txn.insert(
          'aportes',
          _values(
            baseId: baseId,
            hidden: hidden,
            palabra: palabra,
            categoria: (raw['categoria'] ?? '').toString(),
            glosa: glosa,
            texto: (raw['texto'] ?? '').toString(),
            sinonimos: (raw['sinonimos'] ?? '').toString(),
            pagina: raw['pagina'] is int ? raw['pagina'] as int : 0,
            palabraOriginal: raw['palabra_original']?.toString(),
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        count++;
      }
    });
    await _refreshOverridden();
    return count;
  }
}