/// Aggregates what the tracker saw during a set so the user can share a
/// plain-text report when counting misbehaves. No frames, only numbers.
class TrackingDiagnostics {
  TrackingDiagnostics(this.exerciseLabel);

  final String exerciseLabel;
  int frames = 0;
  int framesWithBody = 0;
  int framesCountable = 0;
  int framesInPosition = 0;
  int trackBreaks = 0;
  int repsCounted = 0;
  int shallowAttempts = 0;
  double? signalMin;
  double? signalMax;
  double? lastSignal;
  double? lastHigh;
  double? lastLow;
  double? lastTilt;
  bool hadGravity = false;
  String? lastGravity;
  int orientationChanges = 0;
  final Map<String, int> formStatusCounts = {};
  final Map<String, int> rejections = {};
  String? lastState;

  void observeSignal(double value) {
    lastSignal = value;
    final min = signalMin;
    final max = signalMax;
    signalMin = min == null || value < min ? value : min;
    signalMax = max == null || value > max ? value : max;
  }

  void countForm(String status) =>
      formStatusCounts[status] = (formStatusCounts[status] ?? 0) + 1;

  void reject(String reason) =>
      rejections[reason] = (rejections[reason] ?? 0) + 1;

  String fmt(double? v) => v == null ? '–' : v.toStringAsFixed(1);

  /// Human-readable summary.
  String report() {
    final form = formStatusCounts.entries
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    final rej = rejections.isEmpty
        ? 'none'
        : rejections.entries.map((e) => '${e.key}=${e.value}').join(', ');
    return [
      'Tracking report: $exerciseLabel',
      'frames=$frames body=$framesWithBody countable=$framesCountable '
          'inPosition=$framesInPosition',
      'reps=$repsCounted shallow=$shallowAttempts trackBreaks=$trackBreaks '
          'orientationChanges=$orientationChanges',
      'signal min=${fmt(signalMin)} max=${fmt(signalMax)} '
          'last=${fmt(lastSignal)} thresholds high=${fmt(lastHigh)} '
          'low=${fmt(lastLow)} state=${lastState ?? '–'}',
      'tilt=${fmt(lastTilt)} gravity=${hadGravity ? (lastGravity ?? '?') : 'none'}',
      'form: ${form.isEmpty ? '–' : form}',
      'rejected transitions: $rej',
    ].join('\n');
  }
}
