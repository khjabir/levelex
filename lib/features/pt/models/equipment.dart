/// Gym equipment the user can tell MY PT about. Bodyweight needs nothing.
enum Equipment {
  dumbbells('Dumbbells', 'Dumbbell rack or free-weight area'),
  barbell('Barbell & plates', 'Squat rack or lifting platform'),
  kettlebell('Kettlebell', 'Free-weight area'),
  bench('Flat bench', 'Free-weight area'),
  pullUpBar('Pull-up bar', 'Rig or doorway bar'),
  resistanceBands('Resistance bands', 'Stretch area or your bag'),
  cableMachine('Cable machine', 'Machine section'),
  box('Plyo box / step', 'Functional area'),
  mat('Exercise mat', 'Stretch area'),
  jumpRope('Jump rope', 'Functional area'),
  medicineBall('Medicine ball', 'Functional area'),
  treadmill('Treadmill', 'Cardio section'),
  bike('Stationary bike', 'Cardio section'),
  rower('Rowing machine', 'Cardio section');

  const Equipment(this.label, this.whereHint);

  final String label;

  /// Where this is usually found in a gym; used when the user has not
  /// written their own location.
  final String whereHint;

  static Equipment? fromName(String? name) {
    for (final e in values) {
      if (e.name == name) return e;
    }
    return null;
  }
}

/// One piece of the user's gym: the type plus an optional photo and note
/// ("blue rack by the mirror") so the coach can point to it.
class EquipmentItem {
  const EquipmentItem({required this.type, this.photoPath, this.location});

  final Equipment type;

  /// Local file path of the user's photo (never uploaded).
  final String? photoPath;

  /// Free text written by the user.
  final String? location;

  EquipmentItem copyWith({
    String? photoPath,
    bool clearPhoto = false,
    String? location,
  }) => EquipmentItem(
    type: type,
    photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    location: location ?? this.location,
  );

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'photoPath': photoPath,
    'location': location,
  };

  static EquipmentItem? fromMap(Map<dynamic, dynamic> map) {
    final type = Equipment.fromName(map['type'] as String?);
    if (type == null) return null;
    return EquipmentItem(
      type: type,
      photoPath: map['photoPath'] as String?,
      location: map['location'] as String?,
    );
  }
}

/// Everything MY PT knows about the user's training space.
class GymProfile {
  const GymProfile({this.items = const [], this.gymName});

  final List<EquipmentItem> items;
  final String? gymName;

  bool get bodyweightOnly => items.isEmpty;

  Set<Equipment> get available => {for (final i in items) i.type};

  EquipmentItem? item(Equipment type) {
    for (final i in items) {
      if (i.type == type) return i;
    }
    return null;
  }

  GymProfile toggle(Equipment type) {
    if (available.contains(type)) {
      return GymProfile(
        items: items.where((i) => i.type != type).toList(),
        gymName: gymName,
      );
    }
    return GymProfile(
      items: [
        ...items,
        EquipmentItem(type: type),
      ],
      gymName: gymName,
    );
  }

  GymProfile update(EquipmentItem item) => GymProfile(
    items: [
      for (final i in items)
        if (i.type == item.type) item else i,
      if (!available.contains(item.type)) item,
    ],
    gymName: gymName,
  );

  GymProfile copyWith({List<EquipmentItem>? items, String? gymName}) =>
      GymProfile(items: items ?? this.items, gymName: gymName ?? this.gymName);

  Map<String, dynamic> toMap() => {
    'items': [for (final i in items) i.toMap()],
    'gymName': gymName,
  };

  factory GymProfile.fromMap(Map<dynamic, dynamic> map) => GymProfile(
    items: [
      for (final raw in (map['items'] as List? ?? const []))
        if (raw is Map) ?EquipmentItem.fromMap(raw),
    ],
    gymName: map['gymName'] as String?,
  );
}
