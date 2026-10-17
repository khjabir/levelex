/// Aggregated statistics for one calendar day.
class DailyStats {
  const DailyStats({
    required this.date,
    this.totalPushUps = 0,
    this.completedSessions = 0,
    this.skippedSessions = 0,
    this.attemptedSessions = 0,
  });

  /// Local midnight of the day.
  final DateTime date;
  final int totalPushUps;
  final int completedSessions;
  final int skippedSessions;

  /// Sessions with at least one rep (completed or incomplete).
  final int attemptedSessions;

  /// A day "counts" for the streak when at least one set was completed.
  bool get isCompletedDay => completedSessions > 0;

  @override
  bool operator ==(Object other) =>
      other is DailyStats &&
      other.date == date &&
      other.totalPushUps == totalPushUps &&
      other.completedSessions == completedSessions &&
      other.skippedSessions == skippedSessions &&
      other.attemptedSessions == attemptedSessions;

  @override
  int get hashCode => Object.hash(
    date,
    totalPushUps,
    completedSessions,
    skippedSessions,
    attemptedSessions,
  );

  @override
  String toString() =>
      'DailyStats($date, reps=$totalPushUps, completed=$completedSessions, '
      'skipped=$skippedSessions)';
}
