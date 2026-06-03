import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../api/api_client.dart';
import '../models/patient.dart';
import '../models/note.dart';

/// Native (iOS/Android) cache using SQLite.
class CacheStore {
  Database? _db;

  Future<Database> get db async {
    _db ??= await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'signacare_cache.db');
    return openDatabase(path, version: 1, onCreate: _createSchema);
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY, data TEXT NOT NULL, synced_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY, patient_id TEXT NOT NULL, data TEXT NOT NULL, synced_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_writes (
        id INTEGER PRIMARY KEY AUTOINCREMENT, method TEXT NOT NULL,
        path TEXT NOT NULL, payload TEXT NOT NULL, created_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> cachePatients(List<Patient> patients) async {
    final database = await db;
    final batch = database.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in patients) {
      batch.insert('patients', {'id': p.id, 'data': jsonEncode(p.toJson()), 'synced_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Patient>> getCachedPatients({String? search}) async {
    final database = await db;
    final rows = await database.query('patients');
    final patients = rows.map((r) => Patient.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>)).toList();
    if (search == null || search.isEmpty) return patients;
    final q = search.toLowerCase();
    return patients.where((p) =>
      p.givenName.toLowerCase().contains(q) ||
      p.familyName.toLowerCase().contains(q) ||
      (p.emrNumber?.toLowerCase().contains(q) ?? false)).toList();
  }

  Future<Patient?> getCachedPatient(String id) async {
    final database = await db;
    final rows = await database.query('patients', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Patient.fromJson(jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
  }

  Future<List<Note>> getCachedNotes(String patientId) async {
    final database = await db;
    final rows = await database.query('notes', where: 'patient_id = ?', whereArgs: [patientId]);
    return rows.map((r) => Note.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>)).toList();
  }

  Future<void> queueWrite(String method, String path, Map<String, dynamic> payload) async {
    final database = await db;
    await database.insert('pending_writes', {
      'method': method, 'path': path,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> flushPendingWrites() async {
    // Audit Tier 4.2 (HIGH-J2) — the flush loop used to `catch (_) { break; }`,
    // which silently aborted the queue on a single failed write. We
    // now distinguish: (a) DioException with no response (transport /
    // offline) stops the loop so we retry next flush; (b) DioException
    // with a 4xx response is a permanent failure — we log it and skip
    // that row so the rest of the queue can proceed.
    final database = await db;
    final rows = await database.query('pending_writes', orderBy: 'created_at ASC');
    int flushed = 0;
    for (final row in rows) {
      final method = row['method'] as String;
      final path = row['path'] as String;
      try {
        final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        if (method == 'POST') await api.post(path, data: payload);
        if (method == 'PATCH') await api.patch(path, data: payload);
        await database.delete('pending_writes', where: 'id = ?', whereArgs: [row['id']]);
        flushed++;
      } on DioException catch (err) {
        if (err.response == null) {
          developer.log(
            'flushPendingWrites: transport error, stopping flush',
            name: 'sara.sync',
            error: err.message,
          );
          break;
        }
        final status = err.response?.statusCode ?? 0;
        if (status >= 400 && status < 500) {
          developer.log(
            'flushPendingWrites: dropping permanently-failed row ${row['id']} ($method $path, $status)',
            name: 'sara.sync',
            error: err.response?.data,
          );
          await database.delete('pending_writes', where: 'id = ?', whereArgs: [row['id']]);
          continue;
        }
        // 5xx or other — retry on next flush
        developer.log(
          'flushPendingWrites: server error ($status), retrying later',
          name: 'sara.sync',
          error: err.message,
        );
        break;
      } catch (err) {
        developer.log(
          'flushPendingWrites: unexpected error on row ${row['id']}',
          name: 'sara.sync',
          error: err,
        );
        break;
      }
    }
    return flushed;
  }

  Future<int> pendingWriteCount() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as c FROM pending_writes');
    return (result.first['c'] as int?) ?? 0;
  }
}
