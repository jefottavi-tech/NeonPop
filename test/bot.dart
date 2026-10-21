import 'dart:math';

import 'package:neon_pop/game/board.dart';
import 'package:neon_pop/game/world.dart';

/// A decent player: traces every aim angle with the real shot physics, tries
/// both the current and the swapped bubble, and keeps the best outcome.
class Bot {
  static const _angles = 240;

  /// Picks and fires one shot. Returns false if it couldn't shoot.
  static bool play(World w) {
    double bestScore = -double.infinity, bestAngle = pi / 2;
    var bestSwap = false;
    for (var i = 0; i <= _angles; i++) {
      final a = World.minAim + (pi - 2 * World.minAim) * i / _angles;
      final r = w.trace(a);
      for (final swap in [false, true]) {
        final color = swap ? w.next : w.current;
        final s = _value(w, r, color);
        if (s > bestScore) {
          bestScore = s;
          bestAngle = a;
          bestSwap = swap;
        }
      }
    }
    if (bestSwap) w.swap();
    w.setAim(bestAngle);
    return w.shoot();
  }

  static double _value(World w, ShotResult r, int color) {
    switch (r.contact) {
      case Contact.core:
        return 1000;
      case Contact.shield:
        return -50;
      case Contact.lost:
        return -40;
      case Contact.stick:
        break;
    }
    final board = w.board.copy();
    final out = board.land(r.cell!, color);
    var v = out.popped.length * 3.0 + out.exploded.length * 3 + out.fallen.length * 4 + out.thawed.length * 2;
    if (w.boss != null) {
      // Uncovering the core is worth a lot.
      final core = cell(0, 0);
      final open = neighbours(core).where((n) => !board.cells.containsKey(n)).length;
      final before = neighbours(core).where((n) => !w.board.cells.containsKey(n)).length;
      v += (open - before) * 6;
    }
    if (!out.scored) {
      // Build towards a match: touching the same colour, landing high.
      final same = neighbours(r.cell!).where((n) {
        final b = board.cells[n];
        return b != null && b.colored && b.color == color;
      }).length;
      v += same * 1.5 - 4;
      final y = w.cellWorld(r.cell!).y;
      v -= y / 200;
      if (y + bubbleR + rowH * 1.5 > World.deadline) v -= 30;
    }
    return v;
  }

  /// Plays a level to the end. Returns shots used, or null if it failed.
  static int? clear(int level, {int seed = 1, double limit = 900}) {
    final w = World(Run(level: level), rng: Random(level * 31 + seed));
    const dt = 1 / 60;
    while (w.time < limit) {
      if (w.ready) play(w);
      w.update(dt);
      if (w.cleared) return w.shots;
      if (w.failed || w.stuck) return null;
    }
    return null;
  }
}
