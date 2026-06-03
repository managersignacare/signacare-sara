import '../models/patient.dart';
import '../models/note.dart';

/// Web stub — no SQLite on web, all reads go direct to API.
class CacheStore {
  Future<void> cachePatients(List<Patient> patients) async {}
  Future<List<Patient>> getCachedPatients({String? search}) async => [];
  Future<Patient?> getCachedPatient(String id) async => null;
  Future<List<Note>> getCachedNotes(String patientId) async => [];
  Future<void> queueWrite(String method, String path, Map<String, dynamic> payload) async {}
  Future<int> flushPendingWrites() async => 0;
  Future<int> pendingWriteCount() async => 0;
}
