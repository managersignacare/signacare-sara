class Patient {
  final String id;
  final String givenName;
  final String familyName;
  final String? preferredName;
  final String dateOfBirth;
  final String? gender;
  final String? emrNumber;
  final String? medicareNumber;
  final String? dvaNumber;
  final String status;
  final String? phonePrimary;
  final DateTime? updatedAt;

  const Patient({
    required this.id,
    required this.givenName,
    required this.familyName,
    this.preferredName,
    required this.dateOfBirth,
    this.gender,
    this.emrNumber,
    this.medicareNumber,
    this.dvaNumber,
    this.status = 'active',
    this.phonePrimary,
    this.updatedAt,
  });

  String get fullName => '$familyName, $givenName';
  String get displayName => preferredName != null ? '$givenName "$preferredName" $familyName' : '$givenName $familyName';

  int get age {
    final dob = DateTime.tryParse(dateOfBirth);
    if (dob == null) return 0;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  factory Patient.fromJson(Map<String, dynamic> j) => Patient(
    id: j['id'] as String,
    givenName: j['givenName'] as String? ?? '',
    familyName: j['familyName'] as String? ?? '',
    preferredName: j['preferredName'] as String?,
    dateOfBirth: j['dateOfBirth'] as String? ?? '',
    gender: j['gender'] as String?,
    emrNumber: j['emrNumber'] as String?,
    medicareNumber: j['medicareNumber'] as String?,
    dvaNumber: j['dvaNumber'] as String?,
    status: j['status'] as String? ?? 'active',
    phonePrimary: j['phonePrimary'] as String?,
    updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt'] as String) : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'givenName': givenName, 'familyName': familyName,
    'preferredName': preferredName, 'dateOfBirth': dateOfBirth,
    'gender': gender, 'emrNumber': emrNumber, 'status': status,
  };
}

class Episode {
  final String id;
  final String title;
  final String episodeType;
  final String status;
  final String? startDate;
  final String? primaryClinicianName;
  final String? summary;
  final String? primaryDiagnosis;

  const Episode({
    required this.id,
    required this.title,
    required this.episodeType,
    required this.status,
    this.startDate,
    this.primaryClinicianName,
    this.summary,
    this.primaryDiagnosis,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Episode',
    episodeType: j['episodeType'] as String? ?? 'community',
    status: j['status'] as String? ?? 'open',
    startDate: j['startDate'] as String?,
    primaryClinicianName: j['primaryClinicianName'] as String?,
    summary: j['summary'] as String?,
    primaryDiagnosis: j['primaryDiagnosis'] as String?,
  );
}
