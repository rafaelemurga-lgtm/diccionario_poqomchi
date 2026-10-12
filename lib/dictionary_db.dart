import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Si actualizas assets/diccionario.db, sube este número para que la app
/// vuelva a copiar la base de datos al teléfono.
const int kDbVersion = 1;

enum Direction { pqmToEs, esToPqm }

class Entry {
  final int id;
  final String palabra;
  final String categoria;
  final String glosa;
  final String texto;
  final String sinonimos;
  final int pagina;

  Entry({
    required this.id,
    required this.palabra,
    required this.categoria,
    required this.glosa,
    required this.texto,
    required this.sinonimos,
    required this.pagina,
  });

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int,
        palabra: (m['palabra'] ?? '') as String,
        categoria: (m['categoria'] ?? '') as String,
        glosa: (m['glosa'] ?? '') as String,
        texto: (m['texto'] ?? '') as String,
        sinonimos: (m['sinonimos'] ?? '') as String,
        pagina: (m['pagina'] ?? 0) as int,
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
String fuzzy(String s) => normalize(s)
    .replaceAllMapped(RegExp(r'([aeiou])\1+'), (m) => m.group(1)!);

class DictionaryDb {
  DictionaryDb._(this._db);
  final Database _db;

  static Future<DictionaryDb> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'diccionario_v$kDbVersion.db');
    if (!await File(path).exists()) {
      final data = await rootBundle.load('assets/diccionario.db');
      await File(path).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return DictionaryDb._(await openDatabase(path, readOnly: true));
  }

  Future<int> count() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM entradas');
    return (r.first['n'] as int?) ?? 0;
  }

  Future<List<Entry>> search(String query, Direction dir,
      {int limit = 80}) async {
    final n = normalize(query);
    if (n.isEmpty) return [];
    return dir == Direction.pqmToEs
        ? _searchPqm(query, limit)
        : _searchEs(query, limit);
  }

  Future<List<Entry>> _searchPqm(String query, int limit) async {
    final n = normalize(query);
    final f = fuzzy(query);
    var rows = await _db.rawQuery('''
      SELECT * FROM entradas
      WHERE palabra_norm LIKE ? OR palabra_fuzzy LIKE ?
      ORDER BY CASE WHEN palabra_norm = ? THEN 0
                    WHEN palabra_fuzzy = ? THEN 1
                    WHEN palabra_norm LIKE ? THEN 2 ELSE 3 END,
               length(palabra_norm), palabra_norm
      LIMIT ?''', ['$n%', '$f%', n, f, '$n%', limit]);
    // Pocas coincidencias por prefijo: ampliar a "contiene".
    if (rows.length < 10) {
      final more = await _db.rawQuery('''
        SELECT * FROM entradas
        WHERE palabra_norm LIKE ? OR palabra_fuzzy LIKE ?
        ORDER BY length(palabra_norm) LIMIT ?''', ['%$n%', '%$f%', limit]);
      final seen = rows.map((r) => r['id']).toSet();
      rows = [...rows, ...more.where((r) => !seen.contains(r['id']))]
          .take(limit)
          .toList();
    }
    return rows.map(Entry.fromMap).toList();
  }

  Future<List<Entry>> _searchEs(String query, int limit) async {
    final tokens = normalize(query).split(' ')..sort((a, b) => b.length - a.length);
    final main = tokens.first;
    final rows = await _db.rawQuery('''
      SELECT e.*, MIN(CASE WHEN i.termino = ? THEN 0 ELSE 1 END) AS rango
      FROM indice_es i JOIN entradas e ON e.id = i.entrada_id
      WHERE i.termino LIKE ?
      GROUP BY e.id
      ORDER BY rango, length(e.glosa)
      LIMIT ?''', [main, '$main%', limit * 3]);
    final rest = tokens.skip(1).toList();
    final out = rows
        .map(Entry.fromMap)
        .where((e) => rest.every((t) => normalize(e.glosa).contains(t)))
        .take(limit)
        .toList();
    return out;
  }
}
