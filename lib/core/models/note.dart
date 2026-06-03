class ContactMeta {
  final String? contactDate;
  final String? contactTime;
  final int? durationMin;
  final String? team;
  final int? numProvidingService;
  final int? numReceivingService;
  final String? location;
  final String? contactMedium;
  final String? program;
  final List<String> serviceRecipients;

  const ContactMeta({
    this.contactDate,
    this.contactTime,
    this.durationMin,
    this.team,
    this.numProvidingService,
    this.numReceivingService,
    this.location,
    this.contactMedium,
    this.program,
    this.serviceRecipients = const [],
  });

  factory ContactMeta.fromJson(Map<String, dynamic> j) => ContactMeta(
    contactDate: j['contactDate'] as String?,
    contactTime: j['contactTime'] as String?,
    durationMin: j['durationMin'] as int?,
    team: j['team'] as String?,
    numProvidingService: j['numProvidingService'] as int?,
    numReceivingService: j['numReceivingService'] as int?,
    location: j['location'] as String?,
    contactMedium: j['contactMedium'] as String?,
    program: j['program'] as String?,
    serviceRecipients: (j['serviceRecipients'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    if (contactDate != null) 'contactDate': contactDate,
    if (contactTime != null) 'contactTime': contactTime,
    if (durationMin != null) 'durationMin': durationMin,
    if (team != null) 'team': team,
    if (numProvidingService != null) 'numProvidingService': numProvidingService,
    if (numReceivingService != null) 'numReceivingService': numReceivingService,
    if (location != null) 'location': location,
    if (contactMedium != null) 'contactMedium': contactMedium,
    if (program != null) 'program': program,
    'serviceRecipients': serviceRecipients,
  };
}

class Note {
  final String id;
  final String title;
  final String noteType;
  final String content;
  final String status;
  final bool didNotAttend;
  final bool isReportableContact;
  final bool isAiDraft;
  final String? authorName;
  final String? episodeTitle;
  final String? episodeId;
  final DateTime createdAt;
  final ContactMeta? contactMeta;

  const Note({
    required this.id,
    required this.title,
    required this.noteType,
    required this.content,
    required this.status,
    required this.didNotAttend,
    required this.isReportableContact,
    this.isAiDraft = false,
    this.authorName,
    this.episodeTitle,
    this.episodeId,
    required this.createdAt,
    this.contactMeta,
  });

  /// Audit Tier 5.4 — banner condition: AI-drafted + not yet signed.
  /// Signing (status='signed') is the clinician's attestation and
  /// clears the banner while `isAiDraft` stays true for audit.
  bool get showAiDraftBanner => isAiDraft && status != 'signed';

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    noteType: j['noteType'] as String? ?? 'progress',
    content: j['content'] as String? ?? '',
    status: j['status'] as String? ?? 'draft',
    didNotAttend: j['didNotAttend'] as bool? ?? false,
    isReportableContact: j['isReportableContact'] as bool? ?? true,
    // Audit Tier 5.4 — map both camelCase + snake_case because the
    // backend response uses camelCase but cached/sync rows may still
    // carry the raw DB column name.
    isAiDraft: (j['isAiDraft'] as bool?) ?? (j['is_ai_draft'] as bool?) ?? false,
    authorName: j['authorName'] as String?,
    episodeTitle: j['episodeTitle'] as String?,
    episodeId: j['episodeId'] as String?,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    contactMeta: j['contactMeta'] != null
        ? ContactMeta.fromJson(Map<String, dynamic>.from(j['contactMeta'] as Map))
        : null,
  );
}

class Prescription {
  final String id;
  final String medicationName;
  final String dose;
  final String frequency;
  final String? prescriber;
  final String? episodeId;
  final DateTime? startDate;
  final bool isActive;

  const Prescription({
    required this.id,
    required this.medicationName,
    required this.dose,
    required this.frequency,
    this.prescriber,
    this.episodeId,
    this.startDate,
    this.isActive = true,
  });

  factory Prescription.fromJson(Map<String, dynamic> j) => Prescription(
    id: j['id'] as String,
    medicationName: j['medicationName'] as String? ?? j['medication_name'] as String? ?? '',
    dose: j['dose'] as String? ?? '',
    frequency: j['frequency'] as String? ?? '',
    prescriber: j['prescriber'] as String?,
    episodeId: j['episodeId'] as String?,
    startDate: j['startDate'] != null ? DateTime.tryParse(j['startDate'] as String) : null,
    isActive: j['isActive'] as bool? ?? true,
  );
}

class Message {
  final String id;
  final String subject;
  final String body;
  final String? senderName;
  final String? recipientName;
  final bool isRead;
  final DateTime createdAt;
  final String? patientId;
  final String? patientName;

  const Message({
    required this.id,
    required this.subject,
    required this.body,
    this.senderName,
    this.recipientName,
    required this.isRead,
    required this.createdAt,
    this.patientId,
    this.patientName,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'] as String,
    subject: j['subject'] as String? ?? '(no subject)',
    body: j['body'] as String? ?? j['content'] as String? ?? '',
    senderName: j['senderName'] as String? ?? j['sender_name'] as String?,
    recipientName: j['recipientName'] as String?,
    isRead: j['isRead'] as bool? ?? j['read'] as bool? ?? false,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    patientId: j['patientId'] as String?,
    patientName: j['patientName'] as String?,
  );
}
