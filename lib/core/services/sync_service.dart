import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../api/response_parsers.dart';
import '../models/patient.dart';
import '../models/note.dart';

// Conditional imports — sqflite doesn't work on web
import 'sync_service_native.dart' if (dart.library.html) 'sync_service_web.dart'
    as platform;

/// Local cache + offline write queue.
/// On native (iOS/Android): uses SQLite for offline caching.
/// On web: API-only, no caching (always online).
class SyncService {
  final _cache = platform.CacheStore();

  bool _shouldFallbackToCache(Object error) {
    // Web has no durable cache store; surfacing backend errors is safer
    // than silently returning empty arrays that look like "no data."
    if (kIsWeb) return false;
    if (error is DioException) {
      // Transport-level failures (no HTTP response) can safely use cache.
      return error.response == null;
    }
    return true;
  }

  // ── Online check ────────────────────────────────────────────────────────────

  Future<bool> get isOnline async {
    if (kIsWeb) return true; // Web is always "online" (no SQLite fallback)
    final conn = await Connectivity().checkConnectivity();
    return !conn.contains(ConnectivityResult.none);
  }

  // ── Patients ────────────────────────────────────────────────────────────────

  Future<List<Patient>> fetchPatients({String? search}) async {
    if (await isOnline) {
      try {
        final data = await api.get('/patients', params: {
          if (search != null && search.isNotEmpty) 'search': search,
          // Default to my patients; when searching, show all clinic patients
          if (search == null || search.isEmpty) 'myPatients': 'true',
          'limit': '40',
        });
        final list = readMapListEnvelope(
          data,
          preferredKeys: const ['data', 'patients'],
        );
        final patients = list
            .map((j) => Patient.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
        await _cachePatients(patients);
        return patients;
      } catch (err) {
        if (!_shouldFallbackToCache(err)) rethrow;
        // Fall through to cache only for offline/transport failures.
      }
    }
    return _cachedPatients(search: search);
  }

  Future<Patient?> fetchPatient(String id) async {
    if (await isOnline) {
      try {
        final data = await api.get('/patients/$id');
        final patient = Patient.fromJson(
          readMapEnvelope(data, preferredKeys: const ['data', 'patient']),
        );
        await _cachePatients([patient]);
        return patient;
      } catch (err) {
        if (!_shouldFallbackToCache(err)) rethrow;
      }
    }
    return _cachedPatient(id);
  }

  Future<void> _cachePatients(List<Patient> patients) async {
    await _cache.cachePatients(patients);
  }

  Future<List<Patient>> _cachedPatients({String? search}) async {
    return _cache.getCachedPatients(search: search);
  }

  Future<Patient?> _cachedPatient(String id) async {
    return _cache.getCachedPatient(id);
  }

  // ── Notes ───────────────────────────────────────────────────────────────────

  Future<List<Note>> fetchNotes(String patientId) async {
    if (await isOnline) {
      try {
        final data = await api.get('/patients/$patientId/notes');
        final list = readMapListEnvelope(
          data,
          preferredKeys: const ['notes', 'data'],
        );
        final notes = list
            .map((j) => Note.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
        return notes;
      } catch (err) {
        if (!_shouldFallbackToCache(err)) rethrow;
      }
    }
    return _cache.getCachedNotes(patientId);
  }

  // ── Write (with offline queue) ──────────────────────────────────────────────

  Future<dynamic> writeNote({
    required String patientId,
    String? episodeId,
    required String noteType,
    required String title,
    required String content,
    bool isReportableContact = false,
    bool didNotAttend = false,
    Map<String, dynamic>? contactMeta,
  }) async {
    final payload = <String, dynamic>{
      'noteType': noteType,
      'title': title,
      'content': content,
      'isReportableContact': isReportableContact,
      'didNotAttend': didNotAttend,
      if (episodeId != null) 'episodeId': episodeId,
      if (contactMeta != null) 'contactMeta': contactMeta,
    };
    if (await isOnline) {
      final result =
          await api.post('/patients/$patientId/notes', data: payload);
      return result;
    } else {
      await _cache.queueWrite('POST', '/patients/$patientId/notes', payload);
      throw Exception('Saved offline — will sync when back online');
    }
  }

  /// Flush any queued offline writes. Call on app resume / network reconnect.
  Future<int> flushPendingWrites() async {
    if (!await isOnline) return 0;
    return _cache.flushPendingWrites();
  }

  Future<int> pendingWriteCount() => _cache.pendingWriteCount();
}

final syncServiceProvider = Provider<SyncService>((_) => SyncService());

final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged.map((r) => r.first);
});
