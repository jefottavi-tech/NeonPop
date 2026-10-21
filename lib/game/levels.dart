import 'dart:math';

import 'board.dart';

/// Board outline. The first twelve hang from the ceiling, the last four spin around a hub.
enum Shape {
  pyramid,
  heart,
  columns,
  diamond,
  waves,
  rings,
  crown,
  spiral,
  hourglass,
  chevron,
  lattice,
  wall,
  bloom,
  star,
  pinwheel,
  nebula,
  boss,
}

/// How the board moves: still, sliding side to side, or spinning on its hub.
enum Motion { still, drift, spin }

enum BossKind { medusa, hive, gyre, mirage, nucleus }

const shapeNames = {
  Shape.pyramid: 'Pyramid',
  Shape.heart: 'Heart',
  Shape.columns: 'Columns',
  Shape.diamond: 'Diamond',
  Shape.waves: 'Waves',
  Shape.rings: 'Rings',
  Shape.crown: 'Crown',
  Shape.spiral: 'Spiral',
  Shape.hourglass: 'Hourglass',
  Shape.chevron: 'Chevrons',
  Shape.lattice: 'Lattice',
  Shape.wall: 'The Wall',
  Shape.bloom: 'Bloom',
  Shape.star: 'Star',
  Shape.pinwheel: 'Pinwheel',
  Shape.nebula: 'Nebula',
  Shape.boss: 'Boss',
};

const bossNames = {
  BossKind.medusa: 'Medusa',
  BossKind.hive: 'The Hive',
  BossKind.gyre: 'Gyre',
  BossKind.mirage: 'Mirage',
  BossKind.nucleus: 'The Nucleus',
};

const bossBlurbs = {
  BossKind.medusa: 'Drifts from side to side',
  BossKind.hive: 'Regrows its shell',
  BossKind.gyre: 'Spins behind a shield',
  BossKind.mirage: 'Frozen shell that grows back',
  BossKind.nucleus: 'Spins, shields, drifts and regrows',
};

/// Everything that makes one level what it is. Built from the level number
/// alone, so a level plays the same every time.
class LevelSpec {
  const LevelSpec({
    required this.number,
    required this.shape,
    required this.motion,
    required this.colors,
    required this.size,
    required this.shotRatio,
    required this.dropEvery,
    required this.patch,
    required this.bombs,
    required this.ice,
    required this.stones,
    required this.rainbows,
    required this.driftSpeed,
    required this.spinSpeed,
    required this.boss,
    required this.hue,
  });

  final int number;
  final Shape shape;
  final Motion motion;

  /// Distinct bubble colours on the board.
  final int colors;

  /// Rows for ceiling boards, rings for hub boards.
  final int size;

  /// Shots per coloured bubble on the board.
  final double shotRatio;

  /// Misses before the ceiling drops (or the hub/boss advances).
  final int dropEvery;

  /// Average bubbles per same-colour patch; smaller patches are harder.
  final double patch;

  final int bombs, ice, stones, rainbows;

  /// Drift cycles (radians per second) and spin speed (radians per second, signed).
  final double driftSpeed, spinSpeed;
  final BossKind? boss;

  /// Background tint, in degrees.
  final double hue;

  bool get isBoss => boss != null;
  bool get hub => motion == Motion.spin || isBoss;

  /// How many times this boss kind has come round (1, 2, ...).
  int get tier => (number ~/ 5 - 1) ~/ BossKind.values.length + 1;

  // Boss behaviour.
  int get bossHp => 4 + number ~/ 10;
  bool get bossDrifts => boss == BossKind.medusa || boss == BossKind.mirage || boss == BossKind.nucleus || (isBoss && tier > 1);
  bool get bossShield => boss == BossKind.gyre || boss == BossKind.nucleus;

  /// Shots between regrowths; 0 when the boss doesn't regrow.
  int get bossRegen => switch (boss) {
        BossKind.hive => max(2, 5 - tier),
        BossKind.mirage || BossKind.nucleus => max(3, 6 - tier),
        null => 0,
        _ => tier > 1 ? 5 : 0,
      };

  /// Shield arc, radians.
  double get shieldArc => min(pi * 0.55 + (tier - 1) * 0.3, pi);

  String get name => isBoss ? bossNames[boss]! : shapeNames[shape]!;

  /// One-line introduction the first time something new shows up.
  String? get tip => switch (number) {
        2 => 'Bombs blast everything around them',
        3 => 'Ice needs two matches to break',
        4 => 'Stones never pop: drop them',
        6 => 'Rainbows match any colour · the board drifts',
        7 => 'Every miss brings the ceiling closer',
        8 => 'The board spins around its hub',
        _ => null,
      };

  String get motionLabel => switch (motion) {
        Motion.still => '',
        Motion.drift => 'Drifting',
        Motion.spin => 'Spinning',
      };

  /// Shots to clear a board with [colored] coloured bubbles.
  int shotsFor(int colored) => isBoss ? 20 + size * 7 + bossHp * 3 : hub ? (colored * (shotRatio + 0.45)).ceil() + 10 : (colored * shotRatio).ceil() + 4;

  /// Level a failure sends you back to: the one after the last boss beaten.
  static int checkpointFor(int level) => ((level - 1) ~/ 5) * 5 + 1;

  static const ceilingShapes = [
    Shape.pyramid,
    Shape.heart,
    Shape.columns,
    Shape.diamond,
    Shape.waves,
    Shape.rings,
    Shape.crown,
    Shape.spiral,
    Shape.hourglass,
    Shape.chevron,
    Shape.lattice,
    Shape.wall,
  ];
  static const hubShapes = [Shape.bloom, Shape.star, Shape.pinwheel, Shape.nebula];

  static Motion _motionFor(int regular) {
    if (regular >= 6 && regular % 4 == 2) return Motion.spin;
    if (regular >= 4 && regular % 4 == 0) return Motion.drift;
    return Motion.still;
  }

  factory LevelSpec.forLevel(int n) {
    final d = n - 1;
    final boss = n % 5 == 0 ? BossKind.values[(n ~/ 5 - 1) % BossKind.values.length] : null;
    // Count regular levels only, so bosses don't skip shapes.
    final regular = n - n ~/ 5 - 1;
    final motion = boss != null ? Motion.still : _motionFor(regular);
    var spins = 0;
    for (var i = 0; i < regular; i++) {
      if (_motionFor(i) == Motion.spin) spins++;
    }
    final shape = boss != null
        ? Shape.boss
        : motion == Motion.spin
            ? hubShapes[spins % hubShapes.length]
            : ceilingShapes[(regular - spins) % ceilingShapes.length];
    final hub = boss != null || motion == Motion.spin;
    return LevelSpec(
      number: n,
      shape: shape,
      motion: motion,
      colors: n <= 3 ? 3 : n <= 9 ? 4 : n <= 19 ? 5 : 6,
      size: boss != null
          ? min(2 + (n ~/ 5 - 1) ~/ 2, 4)
          : hub
              ? (n < 15 ? 3 : 4)
              : min(6 + d ~/ 3, 11),
      shotRatio: max(0.55, 0.85 - d * 0.012),
      dropEvery: max(3, 8 - d ~/ 5),
      patch: max(2.6, 4.5 - d * 0.06),
      bombs: boss != null || n < 2 ? 0 : min(1 + (n % 3 == 2 ? 1 : 0) + n ~/ 12, 4),
      ice: boss != null || n < 3 ? 0 : min((n % 4 == 3 ? 6 : 2) + n ~/ 5, 14),
      stones: boss != null || n < 4 ? 0 : min((n % 4 == 0 ? 5 : 2) + n ~/ 6, 10),
      rainbows: boss != null || n < 6 ? 0 : 1 + (n % 3 == 0 ? 1 : 0),
      driftSpeed: min(0.6 + d * 0.02, 1.4),
      spinSpeed: min(0.18 + d * 0.012, 0.6) * (n.isEven ? 1 : -1),
      boss: boss,
      hue: (n * 53) % 360.0,
    );
  }
}

/// Builds the starting board for a level. Deterministic: same level, same board.
Board buildBoard(LevelSpec s) {
  final rng = Random(s.number * 7919 + 13);
  final board = s.hub
      ? Board(hub: true, maxRing: s.isBoss ? s.size + 2 : 5)
      : Board(hub: false, cols: s.motion == Motion.drift ? 9 : 10);
  final shapeCells = <int>[];
  if (s.hub) {
    for (var q = -s.size; q <= s.size; q++) {
      for (var r = -s.size; r <= s.size; r++) {
        final c = cell(q, r);
        final ring = ringOf(c);
        if (ring == 0 || ring > s.size) continue;
        final p = cellPos(c);
        final a = atan2(p.y, p.x);
        if (_inHubShape(s.shape, ring, a, s.size)) shapeCells.add(c);
      }
    }
  } else {
    final rows = s.size;
    final width = board.cols * 2 * bubbleR + bubbleR;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < board.cols; col++) {
        final x = 2 * bubbleR * col + (row.isOdd ? bubbleR : 0) + bubbleR;
        final u = (x - width / 2) / (width / 2 - bubbleR);
        final v = rows == 1 ? 0.0 : row / (rows - 1);
        if (_inCeilingShape(s.shape, u, v, col, row, board.cols)) shapeCells.add(gridCell(col, row));
      }
    }
  }

  // Colours in patches: each cell takes the colour of its nearest seed.
  final seeds = <(Point<double>, int)>[];
  final seedCount = max(s.colors, (shapeCells.length / s.patch).round());
  final picks = [...shapeCells]..shuffle(rng);
  for (var i = 0; i < seedCount && i < picks.length; i++) {
    final p = cellPos(picks[i]);
    // Avoid the colour of the closest seed so far, so patches stay patches.
    var avoid = -1, nearest = double.infinity;
    for (final sd in seeds) {
      final d = sd.$1.squaredDistanceTo(p);
      if (d < nearest) {
        nearest = d;
        avoid = sd.$2;
      }
    }
    var color = i < s.colors ? i : rng.nextInt(s.colors - 1);
    if (i >= s.colors && color >= avoid) color++;
    seeds.add((p, color));
  }
  for (final c in shapeCells) {
    final p = cellPos(c);
    var best = seeds.first;
    for (final sd in seeds) {
      if (sd.$1.squaredDistanceTo(p) < best.$1.squaredDistanceTo(p)) best = sd;
    }
    board.cells[c] = Bubble(BubbleKind.color, best.$2);
  }

  if (s.hub) board.cells[cell(0, 0)] = Bubble(s.isBoss ? BubbleKind.core : BubbleKind.pivot);
  if (s.motion == Motion.spin) {
    // A stone collar round the hub, so one good shot can't drop the whole wheel.
    for (final n in neighbours(cell(0, 0))) {
      if (board.cells.containsKey(n)) board.cells[n] = const Bubble(BubbleKind.stone);
    }
  }
  if (s.boss == BossKind.mirage) {
    for (final n in neighbours(cell(0, 0))) {
      final b = board.cells[n];
      if (b != null) board.cells[n] = Bubble(BubbleKind.ice, b.color);
    }
  }

  // Specials replace bubbles, never in the anchor row so the board stays up.
  final spots = [for (final c in shapeCells) if (s.hub ? ringOf(c) >= 2 : cellR(c) > 0) c]..shuffle(rng);
  var i = 0;
  void place(int count, Bubble Function(Bubble old) make) {
    for (var k = 0; k < count && i < spots.length; k++, i++) {
      board.cells[spots[i]] = make(board.cells[spots[i]]!);
    }
  }

  place(s.bombs, (_) => const Bubble(BubbleKind.bomb));
  place(s.rainbows, (_) => const Bubble(BubbleKind.rainbow));
  place(s.stones, (_) => const Bubble(BubbleKind.stone));
  place(s.ice, (old) => Bubble(BubbleKind.ice, old.color));
  board.prune();
  return board;
}

bool _inCeilingShape(Shape shape, double u, double v, int col, int row, int cols) {
  final au = u.abs();
  switch (shape) {
    case Shape.pyramid:
      return au <= 1.05 - v * 0.9;
    case Shape.heart:
      final x = u * 1.25, y = 1.1 - v * 2.15;
      final a = x * x + y * y - 1;
      return a * a * a - x * x * y * y * y <= 0;
    case Shape.columns:
      return col % 3 != 1 || row == 0;
    case Shape.diamond:
      return au + (v - 0.5).abs() * 2 <= 1.15 || (row == 0 && au < 0.35);
    case Shape.waves:
      return ((v * 2.6 + 0.22 * sin(u * pi * 2)) % 1) < 0.55 || col == 0 || col == cols - 1;
    case Shape.rings:
      final dd = sqrt(u * u + pow((v - 0.35) * 1.4, 2));
      return (dd * 3.2).floor().isEven || au < 0.12;
    case Shape.crown:
      return v <= 0.4 || v <= 0.4 + 0.6 * (1 - ((u * 2.5 + 0.5) % 1 - 0.5).abs() * 2.6);
    case Shape.spiral:
      final y = (v - 0.45) * 1.5;
      final dd = sqrt(u * u + y * y), a = atan2(y, u);
      return ((dd * 2.4 - a / (2 * pi)) % 1) < 0.55 || au < 0.1;
    case Shape.hourglass:
      return au <= 0.28 + 0.8 * (2 * v - 1).abs();
    case Shape.chevron:
      return ((v * 2.2 + au * 0.9) % 1) < 0.6 || col == 0 || col == cols - 1;
    case Shape.lattice:
      return (col ~/ 2 + row ~/ 2).isEven || row == 0;
    case Shape.wall:
      return true;
    default:
      return false;
  }
}

bool _inHubShape(Shape shape, int ring, double a, int size) {
  if (ring <= 1) return true;
  switch (shape) {
    case Shape.bloom:
      return ring <= 2 || cos(3 * a) > 0.1;
    case Shape.star:
      return ring <= 2 || cos(5 * a) > 0.35 - 0.1 * ring;
    case Shape.pinwheel:
      return ((a / (2 * pi) * 3 + ring * 0.12) % 1) < 0.55;
    case Shape.nebula:
      return ring < size || cos(2 * a) > -0.2;
    case Shape.boss:
      return true;
    default:
      return false;
  }
}
