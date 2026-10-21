import 'package:flutter_test/flutter_test.dart';
import 'package:neon_pop/game/board.dart';
import 'package:neon_pop/game/levels.dart';

void main() {
  test('a boss every fifth level, cycling through all five', () {
    for (var n = 1; n <= 50; n++) {
      expect(LevelSpec.forLevel(n).isBoss, n % 5 == 0, reason: 'level $n');
    }
    expect({for (var n = 5; n <= 25; n += 5) LevelSpec.forLevel(n).boss}, BossKind.values.toSet());
    // Second time round, the same boss is tougher.
    expect(LevelSpec.forLevel(30).bossHp, greaterThan(LevelSpec.forLevel(5).bossHp));
    expect(LevelSpec.forLevel(30).size, greaterThan(LevelSpec.forLevel(5).size));
  });

  test('every level has its own board, and neighbours never share a shape', () {
    final seen = <String>{};
    LevelSpec? prev;
    for (var n = 1; n <= 50; n++) {
      final s = LevelSpec.forLevel(n);
      final b = buildBoard(s);
      final key = (b.cells.entries.map((e) => '${e.key}:${e.value.kind.index}:${e.value.color}').toList()..sort()).join(',');
      expect(seen.add(key), isTrue, reason: 'level $n repeats a board');
      if (prev != null && !s.isBoss && !prev.isBoss) expect(s.shape, isNot(prev.shape), reason: 'level $n');
      if (!s.isBoss) prev = s;
    }
  });

  test('all shapes, motions and specials show up within 25 levels', () {
    final specs = [for (var n = 1; n <= 25; n++) LevelSpec.forLevel(n)];
    final shapes = specs.where((s) => !s.isBoss).map((s) => s.shape).toSet();
    expect(shapes, containsAll([...LevelSpec.ceilingShapes.take(10), ...LevelSpec.hubShapes]));
    expect(specs.map((s) => s.motion).toSet(), Motion.values.toSet());
    final kinds = {for (final s in specs) ...buildBoard(s).cells.values.map((b) => b.kind)};
    expect(kinds, BubbleKind.values.toSet());
  });

  test('difficulty never goes down', () {
    for (var n = 2; n <= 60; n++) {
      final a = LevelSpec.forLevel(n - 1), b = LevelSpec.forLevel(n);
      expect(b.colors, greaterThanOrEqualTo(a.colors), reason: 'level $n');
      expect(b.shotRatio, lessThanOrEqualTo(a.shotRatio), reason: 'level $n');
      expect(b.dropEvery, lessThanOrEqualTo(a.dropEvery), reason: 'level $n');
      expect(b.patch, lessThanOrEqualTo(a.patch), reason: 'level $n');
      expect(b.spinSpeed.abs(), greaterThanOrEqualTo(a.spinSpeed.abs()), reason: 'level $n');
      expect(b.driftSpeed, greaterThanOrEqualTo(a.driftSpeed), reason: 'level $n');
      expect(b.bossHp, greaterThanOrEqualTo(a.bossHp), reason: 'level $n');
    }
    // And it really does get harder over a run.
    final first = LevelSpec.forLevel(1), later = LevelSpec.forLevel(30);
    expect(later.colors, greaterThan(first.colors));
    expect(later.shotRatio, lessThan(first.shotRatio));
    expect(later.dropEvery, lessThan(first.dropEvery));
  });

  test('checkpoints are the level after each boss', () {
    expect([1, 4, 5, 6, 10, 11, 14].map(LevelSpec.checkpointFor), [1, 1, 1, 6, 6, 11, 11]);
  });

  test('boards start attached, inside the walls and well above the line', () {
    for (var n = 1; n <= 60; n++) {
      final s = LevelSpec.forLevel(n);
      final b = buildBoard(s);
      expect(b.floating(), isEmpty, reason: 'level $n');
      expect(b.coloredCount, greaterThan(10), reason: 'level $n');
      for (final c in b.cells.keys) {
        expect(b.valid(c), isTrue, reason: 'level $n cell $c');
      }
      if (s.hub) expect(b.cells[cell(0, 0)]?.kind, s.isBoss ? BubbleKind.core : BubbleKind.pivot);
    }
  });
}
