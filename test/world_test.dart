import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neon_pop/game/board.dart';
import 'package:neon_pop/game/levels.dart';
import 'package:neon_pop/game/world.dart';

import 'bot.dart';

void main() {
  test('levels 1–25, bosses included, can all be cleared within their shots', () {
    for (var level = 1; level <= 25; level++) {
      final used = Bot.clear(level);
      expect(used, isNotNull, reason: 'level $level never cleared');
    }
  });

  test('a later stretch (26–35) is clearable too, with different seeds', () {
    for (var level = 26; level <= 35; level++) {
      expect(Bot.clear(level, seed: 7), isNotNull, reason: 'level $level never cleared');
    }
  });

  Board ceiling(Map<(int, int), Bubble> cells) =>
      Board(hub: false, cells: {for (final e in cells.entries) gridCell(e.key.$1, e.key.$2): e.value});
  const red = Bubble(BubbleKind.color, 0), blue = Bubble(BubbleKind.color, 1);

  test('three of a colour pop and whatever hung from them falls', () {
    final b = ceiling({(0, 0): red, (1, 0): red, (1, 1): blue, (1, 2): blue, (5, 0): blue});
    final out = b.land(gridCell(2, 0), 0);
    expect(out.popped, hasLength(3));
    expect(out.fallen, hasLength(2)); // the blue pair below
    expect(b.cells.keys, [gridCell(5, 0)]);
  });

  test('two of a colour just stick', () {
    final b = ceiling({(0, 0): red});
    final out = b.land(gridCell(1, 0), 0);
    expect(out.scored, isFalse);
    expect(b.cells, hasLength(2));
  });

  test('ice thaws on the first match and pops on the second', () {
    final b = ceiling({(0, 0): const Bubble(BubbleKind.ice, 0), (1, 0): red});
    var out = b.land(gridCell(2, 0), 0);
    expect(out.thawed, [gridCell(0, 0)]);
    expect(b.cells[gridCell(0, 0)]!.kind, BubbleKind.color);
    b.cells[gridCell(1, 0)] = red;
    out = b.land(gridCell(1, 1), 0);
    expect(out.popped.keys, contains(gridCell(0, 0)));
  });

  test('rainbows match any colour; stones never match', () {
    final b = ceiling({(0, 0): red, (1, 0): const Bubble(BubbleKind.rainbow), (3, 0): const Bubble(BubbleKind.stone), (4, 0): blue});
    expect(b.land(gridCell(2, 0), 0).popped, hasLength(3));
    expect(b.land(gridCell(5, 0), 1).scored, isFalse); // stone + 2 blue
  });

  test('a bomb goes off when a bubble lands next to it, taking stones with it', () {
    final b = ceiling({(3, 0): const Bubble(BubbleKind.bomb), (4, 0): const Bubble(BubbleKind.stone), (2, 0): blue, (3, 1): red});
    final out = b.land(gridCell(2, 1), 0);
    expect(out.bombs, 1);
    expect(out.exploded.keys, containsAll([gridCell(3, 0), gridCell(4, 0), gridCell(2, 0)]));
  });

  test('misses bring the ceiling down, and crossing the line ends the game', () {
    final world = World(Run(level: 1), rng: Random(1))..time = 1;
    world.board.cells
      ..clear()
      ..addAll({for (var col = 0; col < 10; col++) gridCell(col, 0): const Bubble(BubbleKind.stone)});
    final startY = world.ceilingY;
    var drops = 0, i = 0;
    while (!world.failed && i < 400) {
      if (world.ready) {
        // Colours that never make three in a row: every shot is a miss.
        world.current = i++ % 3;
        world.setAim(pi / 2);
        world.shoot();
      }
      world.update(1 / 30);
      if (world.events.contains(GameEvent.ceilingDrop)) drops++;
      world.events.clear();
    }
    expect(drops, greaterThan(0));
    expect(world.ceilingY, startY + drops * rowH);
    expect(world.failed, isTrue);
    expect(world.combo, 0);
  });

  test('the traced path predicts exactly where a shot lands, on still, drifting and spinning boards', () {
    for (final level in [3, 6, 8, 11, 13]) {
      for (final a in [0.4, 1.2, pi / 2, 2.3, 2.9]) {
        final world = World(Run(level: level), rng: Random(2))..time = 1.3;
        world.board
          ..cells.removeWhere((c, b) => b.kind == BubbleKind.bomb)
          ..prune();
        final predicted = world.trace(a);
        if (predicted.contact != Contact.stick) continue;
        // A colour that can't match, so the bubble stays where it landed.
        world.current = 5;
        world.setAim(a);
        world.shoot();
        while (world.shot != null) {
          world.update(1 / 60);
        }
        expect(world.board.cells[predicted.cell]?.color, 5, reason: 'level $level angle $a');
      }
    }
  });

  test('hitting the uncovered eye hurts the boss; the shield blocks it', () {
    final world = World(Run(level: 15), rng: Random(1));
    world.board.cells.removeWhere((c, b) => b.kind != BubbleKind.core);
    final hp = world.boss!.hp;
    var hits = 0, blocks = 0;
    for (var i = 0; i < 40 && world.boss!.hp > 0; i++) {
      world.time += 0.37;
      final r = world.trace(pi / 2);
      if (r.contact == Contact.core) hits++;
      if (r.contact == Contact.shield) blocks++;
    }
    expect(hits, greaterThan(0));
    expect(blocks, greaterThan(0));
    world.time = 0.5;
    while (world.trace(pi / 2).contact != Contact.core) {
      world.time += 0.05;
    }
    world.setAim(pi / 2);
    world.shoot();
    while (world.shot != null) {
      world.update(1 / 120);
    }
    expect(world.boss!.hp, hp - 1);
    expect(world.events, contains(GameEvent.bossHit));
    expect(LevelSpec.forLevel(15).boss, BossKind.gyre);
  });

  test('running out of bubbles waits for the player; +5 bubbles resumes once', () {
    final world = World(Run(level: 2), rng: Random(1))..time = 1;
    world.shotsLeft = 1;
    world.setAim(0.3);
    world.shoot();
    while (world.shot != null) {
      world.update(1 / 60);
    }
    if (!world.clearing) {
      expect(world.stuck, isTrue);
      expect(world.events, contains(GameEvent.outOfShots));
      world.addShots(5);
      expect(world.stuck, isFalse);
      expect(world.shotsLeft, 5);
      expect(world.bonusUsed, isTrue);
    }
  });

  test('clearing a level adds 40 points per bubble left', () {
    final run = Run(level: 1);
    final world = World(run, rng: Random(1));
    final before = run.score;
    final s = world.finish();
    expect(s.shotsBonus, world.shotsLeft * 40);
    expect(run.score, before + s.shotsBonus);
  });
}
