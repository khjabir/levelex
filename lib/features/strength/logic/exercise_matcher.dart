import '../../pt/models/movement_library.dart';

/// Maps exercise names written by other apps (Strong, Hevy, FitNotes, a
/// hand-made spreadsheet) onto `MovementLibrary` ids.
///
/// Names are normalised (case, punctuation, a trailing "(Barbell)" style
/// qualifier moved to the front, simple plurals, filler words), looked up
/// in an alias table, and finally compared to the library by token-set
/// similarity with equipment words ignored. Anything still unknown becomes
/// a `custom:<slug>` id through [customId] / [resolve].
abstract final class ExerciseMatcher {
  /// Words that never change what an exercise is.
  static const _filler = {
    'the',
    'with',
    'and',
    'a',
    'an',
    'of',
    'on',
    'for',
    'to',
    'each',
    'per',
    'in',
    'from',
    'at',
  };

  /// Load / implement words ignored by the similarity fallback.
  static const _equipment = {
    'barbell',
    'dumbbell',
    'kettlebell',
    'cable',
    'machine',
    'band',
    'banded',
    'smith',
    'ez',
    'bar',
    'bodyweight',
    'weighted',
    'plate',
    'trap',
    'hex',
    'rope',
  };

  /// Position / grip descriptors stripped before a second alias lookup.
  static const _modifiers = {
    'seated',
    'standing',
    'flat',
    'lying',
    'kneeling',
    'conventional',
    'strict',
    'alternating',
    'single',
    'one',
    'two',
    'arm',
    'close',
    'wide',
    'neutral',
    'grip',
    'straight',
    'v',
    'assisted',
    'unilateral',
    'bilateral',
  };

  /// Abbreviations and run-together spellings expanded token by token.
  static const _expand = {
    'bb': 'barbell',
    'db': 'dumbbell',
    'kb': 'kettlebell',
    'ohp': 'overhead press',
    'pushup': 'push up',
    'pullup': 'pull up',
    'chinup': 'chin up',
    'situp': 'sit up',
    'situps': 'sit up',
    'pushups': 'push up',
    'pullups': 'pull up',
    'chinups': 'chin up',
  };

  /// Exercises the library has no counterpart for; a similarity hit on a
  /// shared word (leg *curl* → dumbbell curl) would be wrong.
  static const _never = [
    'leg curl',
    'leg press',
    'leg extension',
    'wrist curl',
    'nordic curl',
    'hip abduction',
    'hip adduction',
    'pec deck',
  ];

  /// Alias phrases (normalised on first use) → library id.
  static const _aliases = <String, String>{
    // Barbell bench press
    'bench press': 'bb_bench_press',
    'barbell bench press': 'bb_bench_press',
    'flat bench press': 'bb_bench_press',
    'flat barbell bench press': 'bb_bench_press',
    'bench': 'bb_bench_press',
    // Barbell back squat
    'squat': 'bb_back_squat',
    'back squat': 'bb_back_squat',
    'barbell squat': 'bb_back_squat',
    'barbell back squat': 'bb_back_squat',
    'high bar squat': 'bb_back_squat',
    'low bar squat': 'bb_back_squat',
    // Barbell deadlift
    'deadlift': 'bb_deadlift',
    'conventional deadlift': 'bb_deadlift',
    'barbell deadlift': 'bb_deadlift',
    'sumo deadlift': 'bb_deadlift',
    'trap bar deadlift': 'bb_deadlift',
    // Barbell overhead press
    'overhead press': 'bb_overhead_press',
    'military press': 'bb_overhead_press',
    'strict press': 'bb_overhead_press',
    'shoulder press barbell': 'bb_overhead_press',
    'barbell shoulder press': 'bb_overhead_press',
    'barbell overhead press': 'bb_overhead_press',
    'overhead press barbell': 'bb_overhead_press',
    'standing barbell press': 'bb_overhead_press',
    'ohp': 'bb_overhead_press',
    // Dumbbell shoulder press
    'shoulder press': 'db_shoulder_press',
    'shoulder press dumbbell': 'db_shoulder_press',
    'dumbbell shoulder press': 'db_shoulder_press',
    'arnold press': 'db_shoulder_press',
    'seated dumbbell press': 'db_shoulder_press',
    'dumbbell press': 'db_shoulder_press',
    'dumbbell overhead press': 'db_shoulder_press',
    'overhead press dumbbell': 'db_shoulder_press',
    'seated shoulder press': 'db_shoulder_press',
    'machine shoulder press': 'db_shoulder_press',
    // Bent-over row
    'bent over row': 'db_bent_row',
    'barbell row': 'db_bent_row',
    'dumbbell row': 'db_bent_row',
    'one arm row': 'db_bent_row',
    'one arm dumbbell row': 'db_bent_row',
    'pendlay row': 'db_bent_row',
    'bent over barbell row': 'db_bent_row',
    'bent over dumbbell row': 'db_bent_row',
    'row barbell': 'db_bent_row',
    'row dumbbell': 'db_bent_row',
    't bar row': 'db_bent_row',
    'kroc row': 'db_bent_row',
    // Romanian deadlift
    'romanian deadlift': 'db_rdl',
    'rdl': 'db_rdl',
    'stiff leg deadlift': 'db_rdl',
    'stiff legged deadlift': 'db_rdl',
    'straight leg deadlift': 'db_rdl',
    'dumbbell romanian deadlift': 'db_rdl',
    'barbell romanian deadlift': 'db_rdl',
    'romanian deadlift dumbbell': 'db_rdl',
    'romanian deadlift barbell': 'db_rdl',
    // Goblet squat
    'goblet squat': 'goblet_squat',
    'kettlebell goblet squat': 'goblet_squat',
    'dumbbell goblet squat': 'goblet_squat',
    // Lunges: plain is bodyweight, anything loaded or walking is db_lunge
    'lunge': 'lunge',
    'bodyweight lunge': 'lunge',
    'lunge bodyweight': 'lunge',
    'alternating lunge': 'lunge',
    'forward lunge': 'lunge',
    'walking lunge': 'db_lunge',
    'dumbbell lunge': 'db_lunge',
    'lunge dumbbell': 'db_lunge',
    'reverse lunge': 'db_lunge',
    'barbell lunge': 'db_lunge',
    'lunge barbell': 'db_lunge',
    'weighted lunge': 'db_lunge',
    'dumbbell walking lunge': 'db_lunge',
    'walking dumbbell lunge': 'db_lunge',
    // Curls
    'bicep curl': 'db_curl',
    'curl': 'db_curl',
    'dumbbell curl': 'db_curl',
    'hammer curl': 'db_curl',
    'barbell curl': 'db_curl',
    'dumbbell bicep curl': 'db_curl',
    'barbell bicep curl': 'db_curl',
    'ez bar curl': 'db_curl',
    'cable curl': 'db_curl',
    'preacher curl': 'db_curl',
    'concentration curl': 'db_curl',
    'incline curl': 'db_curl',
    'alternating dumbbell curl': 'db_curl',
    // Raises
    'lateral raise': 'db_lateral_raise',
    'side raise': 'db_lateral_raise',
    'side lateral raise': 'db_lateral_raise',
    'dumbbell lateral raise': 'db_lateral_raise',
    'cable lateral raise': 'db_lateral_raise',
    'front raise': 'db_front_raise',
    'dumbbell front raise': 'db_front_raise',
    'plate front raise': 'db_front_raise',
    // Triceps
    'tricep pushdown': 'cable_pushdown',
    'cable pushdown': 'cable_pushdown',
    'rope pushdown': 'cable_pushdown',
    'pushdown': 'cable_pushdown',
    'tricep rope pushdown': 'cable_pushdown',
    'cable tricep pushdown': 'cable_pushdown',
    'tricep pressdown': 'cable_pushdown',
    'pressdown': 'cable_pushdown',
    'tricep extension': 'db_overhead_ext',
    'overhead tricep extension': 'db_overhead_ext',
    'overhead extension': 'db_overhead_ext',
    'skullcrusher': 'db_overhead_ext',
    'skull crusher': 'db_overhead_ext',
    'dumbbell tricep extension': 'db_overhead_ext',
    'lying tricep extension': 'db_overhead_ext',
    'french press': 'db_overhead_ext',
    'kickback': 'db_kickback',
    'tricep kickback': 'db_kickback',
    'dumbbell kickback': 'db_kickback',
    'dumbbell tricep kickback': 'db_kickback',
    // Floor press
    'floor press': 'db_floor_press',
    'dumbbell floor press': 'db_floor_press',
    'barbell floor press': 'db_floor_press',
    // Pull-ups and vertical pulls
    'pull up': 'pull_up',
    'chin up': 'pull_up',
    'lat pulldown': 'pull_up',
    'lat pull down': 'pull_up',
    'pulldown': 'pull_up',
    'cable lat pulldown': 'pull_up',
    'lat pulldown cable': 'pull_up',
    'wide grip pull up': 'pull_up',
    'assisted pull up': 'pull_up',
    'weighted pull up': 'pull_up',
    'neutral grip pull up': 'pull_up',
    // Push-ups
    'push up': 'push_up',
    'press up': 'push_up',
    'incline push up': 'push_up',
    'decline push up': 'push_up',
    'diamond push up': 'push_up',
    'wide push up': 'push_up',
    'knee push up': 'push_up',
    'kneeling push up': 'push_up',
    'pike push up': 'pike_push_up',
    'pike press': 'pike_push_up',
    // Core
    'plank': 'plank',
    'front plank': 'plank',
    'forearm plank': 'plank',
    'elbow plank': 'plank',
    'plank hold': 'plank',
    'side plank': 'side_plank',
    'side plank hold': 'side_plank',
    'sit up': 'sit_up',
    'crunch': 'sit_up',
    'ab crunch': 'sit_up',
    'cable crunch': 'sit_up',
    'decline sit up': 'sit_up',
    'weighted sit up': 'sit_up',
    'hanging knee raise': 'hanging_knee_raise',
    'hanging leg raise': 'hanging_knee_raise',
    'knee raise': 'hanging_knee_raise',
    'toes to bar': 'hanging_knee_raise',
    'captain chair leg raise': 'hanging_knee_raise',
    // Posterior chain
    'kettlebell swing': 'kb_swing',
    'swing': 'kb_swing',
    'russian kettlebell swing': 'kb_swing',
    'american kettlebell swing': 'kb_swing',
    'glute bridge': 'glute_bridge',
    'hip thrust': 'glute_bridge',
    'barbell hip thrust': 'glute_bridge',
    'hip thrust barbell': 'glute_bridge',
    'barbell glute bridge': 'glute_bridge',
    'weighted glute bridge': 'glute_bridge',
    'hip bridge': 'glute_bridge',
    'bridge': 'glute_bridge',
    'calf raise': 'calf_raise',
    'standing calf raise': 'calf_raise',
    'seated calf raise': 'calf_raise',
    'machine calf raise': 'calf_raise',
    'calf raise machine': 'calf_raise',
    'dumbbell calf raise': 'calf_raise',
    'barbell calf raise': 'calf_raise',
    'calf press': 'calf_raise',
    // Dips
    'dip': 'tricep_dip',
    'tricep dip': 'tricep_dip',
    'bench dip': 'tricep_dip',
    'chest dip': 'tricep_dip',
    'parallel bar dip': 'tricep_dip',
    'weighted dip': 'tricep_dip',
    'assisted dip': 'tricep_dip',
    'ring dip': 'tricep_dip',
    // Conditioning
    'burpee': 'burpee',
    'jumping jack': 'jumping_jack',
    'star jump': 'jumping_jack',
    'mountain climber': 'mountain_climbers',
    'high knees': 'high_knees',
    'wall sit': 'wall_sit',
    'superman': 'superman',
    'superman hold': 'superman',
    'bird dog': 'bird_dog',
    // Bands / cables
    'band pull apart': 'band_pull_apart',
    'banded pull apart': 'band_pull_apart',
    'pull apart': 'band_pull_apart',
    'face pull': 'band_pull_apart',
    'cable face pull': 'band_pull_apart',
    'rear delt face pull': 'band_pull_apart',
    'band row': 'band_row',
    'banded row': 'band_row',
    'resistance band row': 'band_row',
    'seated cable row': 'band_row',
    'cable row': 'band_row',
    'seated row': 'band_row',
    'machine row': 'band_row',
    'low row': 'band_row',
    // Bodyweight squats
    'air squat': 'squat',
    'bodyweight squat': 'squat',
    'squat bodyweight': 'squat',
    'body weight squat': 'squat',
    'prisoner squat': 'squat',
    'jump squat': 'squat_jump',
    'squat jump': 'squat_jump',
    'jumping squat': 'squat_jump',
    // Cardio
    'treadmill': 'treadmill',
    'running': 'treadmill',
    'run': 'treadmill',
    'treadmill run': 'treadmill',
    'treadmill walk': 'treadmill',
    'walking': 'treadmill',
    'jog': 'treadmill',
    'jogging': 'treadmill',
    'cycling': 'bike',
    'bike': 'bike',
    'cycle': 'bike',
    'stationary bike': 'bike',
    'spin bike': 'bike',
    'indoor cycling': 'bike',
    'assault bike': 'bike',
    'air bike': 'bike',
    'rowing': 'rower',
    'rowing machine': 'rower',
    'row machine': 'rower',
    'rower': 'rower',
    'erg': 'rower',
    'concept 2': 'rower',
    'jump rope': 'jump_rope',
    'skipping': 'jump_rope',
    'skip rope': 'jump_rope',
    'jumping rope': 'jump_rope',
    'rope jump': 'jump_rope',
  };

  static Map<String, String>? _aliasIndex;
  static List<_LibraryTokens>? _library;

  static Map<String, String> get _index =>
      _aliasIndex ??= {for (final e in _aliases.entries) key(e.key): e.value};

  static List<_LibraryTokens> get _lib => _library ??= [
    for (final m in MovementLibrary.all)
      _LibraryTokens(
        id: m.id,
        name: tokens(m.name).toSet().difference(_equipment),
        idWords: tokens(m.id.replaceAll('_', ' '))
            .toSet()
            .difference(_equipment),
      ),
  ];

  /// A `MovementLibrary` id for [rawName], or null when nothing is close.
  static String? match(String rawName) {
    final words = tokens(rawName);
    if (words.isEmpty) return null;
    final direct = _index[words.join(' ')];
    if (direct != null) return direct;
    final set = words.toSet();
    for (final phrase in _never) {
      if (phrase.split(' ').every(set.contains)) return null;
    }
    final noModifiers = [
      for (final w in words)
        if (!_modifiers.contains(w)) w,
    ];
    final byModifier = _index[noModifiers.join(' ')];
    if (byModifier != null) return byModifier;
    final bare = [
      for (final w in noModifiers)
        if (!_equipment.contains(w)) w,
    ];
    final byEquipment = _index[bare.join(' ')];
    if (byEquipment != null) return byEquipment;
    return _closest(bare.toSet());
  }

  /// `custom:<slug>` for an exercise the library does not know.
  static String customId(String rawName) {
    final slug = rawName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'custom:${slug.isEmpty ? 'exercise' : slug}';
  }

  /// [match] when it finds something, otherwise [customId].
  static String resolve(String rawName) => match(rawName) ?? customId(rawName);

  /// The alias-table key for [rawName]: normalised tokens joined by spaces.
  static String key(String rawName) => tokens(rawName).join(' ');

  /// Normalised words of [rawName]: lower-case, a trailing parenthetical
  /// moved to the front, punctuation dropped, abbreviations expanded,
  /// simple plurals singularised, filler words and repeats removed.
  static List<String> tokens(String rawName) {
    var s = rawName.toLowerCase().trim();
    final trailing = RegExp(r'\(([^()]*)\)\s*$').firstMatch(s);
    if (trailing != null) {
      s = '${trailing.group(1)} ${s.substring(0, trailing.start)}';
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    final raw = s.split(' ').where((w) => w.isNotEmpty);
    final expanded = <String>[];
    for (final w in raw) {
      final e = _expand[w];
      if (e != null) {
        expanded.addAll(e.split(' '));
      } else {
        expanded.add(w);
      }
    }
    final merged = <String>[];
    for (var i = 0; i < expanded.length; i++) {
      final w = expanded[i];
      final next = i + 1 < expanded.length ? expanded[i + 1] : null;
      if (w == 'body' && next == 'weight') {
        merged.add('bodyweight');
        i++;
      } else if (w == 'kettle' && next == 'bell') {
        merged.add('kettlebell');
        i++;
      } else if (w == 'dumb' && next == 'bell') {
        merged.add('dumbbell');
        i++;
      } else {
        merged.add(w);
      }
    }
    final out = <String>[];
    for (final w in merged) {
      final single = _singular(w);
      if (_filler.contains(single) || out.contains(single)) continue;
      out.add(single);
    }
    return out;
  }

  static String _singular(String w) {
    if (w.length <= 2 || int.tryParse(w) != null) return w;
    if (w.endsWith('ss') || w.endsWith('us') || w.endsWith('is')) return w;
    if (w.endsWith('ies') && w.length > 4) {
      return '${w.substring(0, w.length - 3)}y';
    }
    if (w.endsWith('ches') ||
        w.endsWith('shes') ||
        w.endsWith('sses') ||
        w.endsWith('xes')) {
      return w.substring(0, w.length - 2);
    }
    if (w.endsWith('s')) return w.substring(0, w.length - 1);
    return w;
  }

  /// Best token-set Jaccard match (≥ 0.5) against library names and ids.
  static String? _closest(Set<String> words) {
    if (words.isEmpty) return null;
    String? best;
    var bestScore = 0.0;
    for (final m in _lib) {
      final score = _max(_jaccard(words, m.name), _jaccard(words, m.idWords));
      if (score > bestScore) {
        bestScore = score;
        best = m.id;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  static double _max(double a, double b) => a > b ? a : b;

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    if (inter == 0) return 0;
    return inter / a.union(b).length;
  }
}

class _LibraryTokens {
  const _LibraryTokens({
    required this.id,
    required this.name,
    required this.idWords,
  });

  final String id;
  final Set<String> name;
  final Set<String> idWords;
}
