enum Magazine {
  lt('大家說英語'),
  sc('空中英語教室'),
  ad('Advanced');

  const Magazine(this.label);
  final String label;
  String get code => name;
  Uri get homeUri => Uri.https('$name.studioclassroom.com', '/');
}

class DailyLesson {
  const DailyLesson({
    required this.magazine,
    required this.date,
    this.title,
    this.englishTitle,
    this.summary,
    this.articleUri,
    this.videoUri,
    this.videoLabel,
    this.sourceFailed = false,
  });

  final Magazine magazine;

  /// A date-only UTC value representing a Taipei calendar day.
  final DateTime date;
  final String? title;
  final String? englishTitle;
  final String? summary;
  final Uri? articleUri;
  final Uri? videoUri;
  final String? videoLabel;

  /// The index succeeded, but the video source could not be verified.
  final bool sourceFailed;
}
