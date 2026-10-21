import 'dart:math';

import 'board.dart';
import 'levels.dart';

enum GameEvent { shoot, bounce, stick, pop, fall, bomb, thaw, ceilingDrop, bossHit, shieldBlock, regrow, bossDown, levelClear, outOfShots, gameOver }

/// What carries over from one level to the next.
class Run {
  Run({this.level = 1, this.score = 0});

  int level;
  int score;
}

class Shot {
  Shot(this.x, this.y, this.vx, this.vy, this.color, this.t);

  double x, y, vx, vy;
  final int color;

  /// The shot's own clock: it moves in fixed steps, so a traced shot lands exactly where a real one does.
  double t;
}

/// How a shot ended.
enum Contact { stick, core, shield, lost }

class ShotResult {
  const ShotResult(this.contact, this.cell, this.x, this.y, this.t);

  final Contact contact;

  /// Cell the bubble sticks in, for [Contact.stick].
  final int? cell;
  final double x, y, t;
}

class Boss {
  Boss(this.kind, this.maxHp) : hp = maxHp;

  final BossKind kind;
  final int maxHp;
  int hp;
  double flash = 0;
}

/// A bubble that popped (ring that grows and fades) or is falling off the board.
class Fx {
  Fx(this.x, this.y, this.bubble, {this.vx = 0, this.vy = 0, this.falling = false, this.life = 0.35}) : maxLife = life;

  double x, y, vx, vy, life;
  final double maxLife;
  final Bubble bubble;
  final bool falling;
}

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.color) : maxLife = life;

  double x, y, vx, vy, life;
  final double maxLife;

  /// Palette index; -1 for white-hot sparks.
  final int color;
}

/// Floating "+120" score text.
class Popup {
  Popup(this.x, this.y, this.text, {this.big = false});

  final double x;
  double y;
  final String text;
  final bool big;
  double life = 1.1;
}

/// End-of-level numbers for the break screen.
class LevelSummary {
  const LevelSummary({
    required this.popped,
    required this.dropped,
    required this.bestCombo,
    required this.accuracy,
    required this.shotsLeft,
    required this.shotsBonus,
  });

  final int popped, dropped, bestCombo, shotsLeft, shotsBonus;
  final double accuracy;
}

/// One level in play. Pure simulation in a fixed 360×640 field; the UI just
/// feeds input, calls [update] every frame, and draws the state.
class World {
  World(this.run, {Random? rng})
      : spec = LevelSpec.forLevel(run.level),
        rng = rng ?? Random() {
    board = buildBoard(spec);
    shotsLeft = spec.shotsFor(board.coloredCount);
    if (spec.isBoss) boss = Boss(spec.boss!, spec.bossHp);
    if (spec.hub) {
      final extra = spec.isBoss ? 1.0 : 0.5;
      hubY = ceilingTop + 8 + (spec.size + extra) * 2 * bubbleR;
    }
    current = _pick();
    next = _pick();
  }

  static const width = 360.0, height = 640.0;
  static const ceilingTop = 54.0;
  static const deadline = 522.0;
  static const shooterX = 180.0, shooterY = 586.0;
  static const shotSpeed = 900.0;
  static const step = 1 / 240;
  static const minAim = 0.14;
  static const coreR = bubbleR * 1.35;
  static const _contact = bubbleR * 2 * 0.82;

  final Run run;
  final LevelSpec spec;
  final Random rng;
  late final Board board;
  Boss? boss;

  double time = 0;
  late int shotsLeft;
  late int current, next;
  Shot? shot;

  /// Aim angle in radians: 0 is right, pi/2 straight up.
  double aim = pi / 2;

  double ceilingY = ceilingTop;
  double hubY = 0;

  /// Shots that scored nothing since the last drop.
  int misses = 0;
  int combo = 0, bestCombo = 0;
  int shots = 0, scoringShots = 0, popped = 0, dropped = 0;

  /// The "+5 bubbles" reward was used on this level.
  bool bonusUsed = false;

  /// Waiting on the player: out of shots, rewarded ad or retry.
  bool stuck = false;
  bool failed = false;
  double? _clearTime;
  bool cleared = false;
  bool get clearing => _clearTime != null;
  bool get finished => failed || clearing || cleared;
  bool get ready => shot == null && !finished && !stuck && time > 0.4;

  final events = <GameEvent>[];
  final fx = <Fx>[];
  final particles = <Particle>[];
  final popups = <Popup>[];
  double shake = 0;

  // ---- board placement ----

  double get _driftAmp {
    if (spec.isBoss) return spec.bossDrifts ? min(50.0, width / 2 - (spec.size + 0.5) * 2 * bubbleR - bubbleR - 4) : 0;
    if (spec.motion == Motion.drift) return (width - _boardWidth) / 2 - 2;
    return 0;
  }

  double get _boardWidth => board.cols * 2 * bubbleR + bubbleR;

  /// Board origin (centre of cell (0, 0)) at time [t].
  Point<double> origin([double? t]) {
    t ??= time;
    final speed = spec.isBoss ? 0.7 + spec.tier * 0.1 : spec.driftSpeed;
    final drift = _driftAmp * sin(t * speed);
    if (board.hub) return Point(width / 2 + drift, hubY);
    return Point((width - _boardWidth) / 2 + bubbleR + drift, ceilingY + bubbleR);
  }

  /// Board rotation at time [t].
  double angle([double? t]) {
    t ??= time;
    if (spec.motion == Motion.spin) return spec.spinSpeed * t;
    if (spec.boss == BossKind.gyre || spec.boss == BossKind.nucleus) return (0.25 + spec.tier * 0.08) * t;
    return 0;
  }

  /// Centre of the shield arc at time [t] (world frame).
  double shieldAngle([double? t]) => -(t ?? time) * (1.0 + spec.tier * 0.15);

  Point<double> cellWorld(int c, [double? t]) {
    final p = cellPos(c), o = origin(t), a = angle(t);
    if (a == 0) return Point(o.x + p.x, o.y + p.y);
    final ca = cos(a), sa = sin(a);
    return Point(o.x + p.x * ca - p.y * sa, o.y + p.x * sa + p.y * ca);
  }

  Point<double> _toLocal(double x, double y, double t) {
    final o = origin(t), a = angle(t);
    final dx = x - o.x, dy = y - o.y;
    if (a == 0) return Point(dx, dy);
    final ca = cos(a), sa = sin(a);
    return Point(dx * ca + dy * sa, -dx * sa + dy * ca);
  }

  bool get _coreAlive => boss != null && boss!.hp > 0;

  // ---- shooting ----

  void swap() {
    if (finished || stuck) return;
    final c = current;
    current = next;
    next = c;
  }

  void setAim(double a) => aim = a.clamp(minAim, pi - minAim);

  /// Aims at a point in the field.
  void aimAt(double x, double y) => setAim(atan2(shooterY - y, x - shooterX));

  bool shoot() {
    if (!ready || shotsLeft <= 0) return false;
    shotsLeft--;
    shots++;
    shot = Shot(shooterX, shooterY, cos(aim) * shotSpeed, -sin(aim) * shotSpeed, current, time);
    current = next;
    next = _pick();
    events.add(GameEvent.shoot);
    return true;
  }

  /// One fixed step of a shot; returns how it ended, or null while it flies.
  ShotResult? _advance(Shot s, {void Function()? onBounce}) {
    s.t += step;
    s.x += s.vx * step;
    s.y += s.vy * step;
    if (s.x < bubbleR) {
      s.x = 2 * bubbleR - s.x;
      s.vx = -s.vx;
      onBounce?.call();
    } else if (s.x > width - bubbleR) {
      s.x = 2 * (width - bubbleR) - s.x;
      s.vx = -s.vx;
      onBounce?.call();
    }
    final o = origin(s.t);
    if (_coreAlive) {
      final dx = s.x - o.x, dy = s.y - o.y;
      if (dx * dx + dy * dy < (coreR + bubbleR) * (coreR + bubbleR)) {
        if (spec.bossShield) {
          var diff = (atan2(dy, dx) - shieldAngle(s.t)) % (2 * pi);
          if (diff > pi) diff -= 2 * pi;
          if (diff.abs() < spec.shieldArc / 2) return ShotResult(Contact.shield, null, s.x, s.y, s.t);
        }
        return ShotResult(Contact.core, null, s.x, s.y, s.t);
      }
    }
    final local = _toLocal(s.x, s.y, s.t);
    final near = nearestCell(local.x, local.y);
    var touching = !board.hub && s.y <= o.y;
    if (!touching) {
      for (final c in [near, ...neighbours(near)]) {
        final b = board.cells[c];
        if (b == null || b.kind == BubbleKind.core) continue;
        if (cellPos(c).distanceTo(local) < _contact) {
          touching = true;
          break;
        }
      }
    }
    if (touching) {
      final c = _snap(local, near);
      return ShotResult(c == null ? Contact.lost : Contact.stick, c, s.x, s.y, s.t);
    }
    if (s.y < -bubbleR) return ShotResult(Contact.lost, null, s.x, s.y, s.t);
    return null;
  }

  /// Free cell nearest to where the shot touched.
  int? _snap(Point<double> local, int near) {
    int? best;
    var bestD = double.infinity;
    final seen = <int>{};
    for (final a in [near, ...neighbours(near)]) {
      for (final c in [a, ...neighbours(a)]) {
        if (!seen.add(c) || !board.canStick(c)) continue;
        final d = cellPos(c).squaredDistanceTo(local);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
    }
    return best;
  }

  /// Where a shot fired now at [angle] ends up, without changing anything.
  /// [path] collects the bounce points and the end, for the aim guide.
  ShotResult trace(double angle, {List<Point<double>>? path}) {
    final s = Shot(shooterX, shooterY, cos(angle) * shotSpeed, -sin(angle) * shotSpeed, current, time);
    path?.add(const Point(shooterX, shooterY));
    for (var i = 0; i < 2000; i++) {
      final r = _advance(s, onBounce: path == null ? null : () => path.add(Point(s.x, s.y)));
      if (r != null) {
        path?.add(Point(r.x, r.y));
        return r;
      }
    }
    return ShotResult(Contact.lost, null, s.x, s.y, s.t);
  }

  // ---- simulation ----

  void update(double dt) {
    time += dt;
    shake = max(0, shake - dt * 30);
    if (boss != null) boss!.flash = max(0, boss!.flash - dt);
    _updateFx(dt);

    final s = shot;
    if (s != null) {
      while (s.t + step <= time) {
        final r = _advance(s, onBounce: () => events.add(GameEvent.bounce));
        if (r != null) {
          shot = null;
          _resolve(r, s.color);
          break;
        }
      }
    }

    if (_clearTime != null && !cleared && time - _clearTime! > 1.0) {
      cleared = true;
      events.add(GameEvent.levelClear);
    }
  }

  void _resolve(ShotResult r, int color) {
    var scored = false;
    switch (r.contact) {
      case Contact.stick:
        final out = board.land(r.cell!, color);
        scored = out.scored;
        _score(out, color);
        if (!scored) events.add(GameEvent.stick);
      case Contact.core:
        scored = true;
        _hitBoss(r.x, r.y);
      case Contact.shield:
        events.add(GameEvent.shieldBlock);
        _burst(r.x, r.y, -1, 10);
      case Contact.lost:
        break;
    }
    if (scored) {
      scoringShots++;
      combo++;
      bestCombo = max(bestCombo, combo);
    } else {
      combo = 0;
      misses++;
      if (misses >= spec.dropEvery) {
        misses = 0;
        if (board.hub) {
          hubY += rowH * 0.7;
        } else {
          ceilingY += rowH;
        }
        shake = 6;
        events.add(GameEvent.ceilingDrop);
      }
    }
    if (_coreAlive && spec.bossRegen > 0 && shots % spec.bossRegen == 0) _regrow();

    if (!clearing && (spec.isBoss ? boss!.hp <= 0 : board.coloredCount == 0)) {
      _clearTime = time;
      _burstLeftovers();
      return;
    }
    if (origin().y + board.reach > deadline) {
      failed = true;
      events.add(GameEvent.gameOver);
      return;
    }
    if (shotsLeft <= 0) {
      stuck = true;
      events.add(GameEvent.outOfShots);
    }
    final left = board.colorsLeft;
    if (left.isNotEmpty) {
      if (!left.contains(current)) current = _pick();
      if (!left.contains(next)) next = _pick();
    }
  }

  void _score(Outcome out, int color) {
    final mult = 1 + min(combo ~/ 2, 4).toInt();
    int pts = out.popped.length * 10 * mult + out.exploded.length * 15 + out.thawed.length * 5;
    final falls = out.fallen.length * 20 * (out.fallen.length >= 8 ? 2 : 1);
    pts += falls;
    run.score += pts;
    popped += out.popped.length + out.exploded.length;
    dropped += out.fallen.length;
    Point<double>? centre;
    out.popped.forEach((c, b) {
      final p = cellWorld(c);
      centre ??= p;
      fx.add(Fx(p.x, p.y, b));
      _burst(p.x, p.y, b.color, 5);
    });
    out.exploded.forEach((c, b) {
      final p = cellWorld(c);
      centre ??= p;
      fx.add(Fx(p.x, p.y, b, life: 0.45));
      _burst(p.x, p.y, b.kind == BubbleKind.bomb ? -1 : b.color, 8);
    });
    out.fallen.forEach((c, b) {
      final p = cellWorld(c);
      fx.add(Fx(p.x, p.y, b, vx: (rng.nextDouble() - 0.5) * 80, vy: -40 - rng.nextDouble() * 60, falling: true, life: 2));
    });
    for (final c in out.thawed) {
      final p = cellWorld(c);
      _burst(p.x, p.y, -1, 6);
    }
    if (out.popped.isNotEmpty) events.add(GameEvent.pop);
    if (out.thawed.isNotEmpty) events.add(GameEvent.thaw);
    if (out.bombs > 0) {
      events.add(GameEvent.bomb);
      shake = 8;
    }
    if (out.fallen.isNotEmpty) events.add(GameEvent.fall);
    if (pts > 0 && centre != null) popups.add(Popup(centre!.x, centre!.y, '+$pts', big: pts >= 200));
  }

  void _hitBoss(double x, double y) {
    final b = boss!;
    b.hp--;
    b.flash = 0.3;
    shake = 7;
    run.score += 150;
    popups.add(Popup(x, y, '+150'));
    _burst(x, y, -1, 14);
    events.add(GameEvent.bossHit);
    if (b.hp <= 0) {
      final bonus = 500 * spec.tier;
      run.score += bonus;
      final o = origin();
      popups.add(Popup(o.x, o.y - 30, '+$bonus', big: true));
      events.add(GameEvent.bossDown);
      shake = 14;
      for (var i = 0; i < 4; i++) {
        _burst(o.x, o.y, i, 14);
      }
    }
  }

  /// The boss grows shell bubbles back next to what is left of it.
  void _regrow() {
    final free = <int>{};
    for (final c in board.cells.keys) {
      for (final n in neighbours(c)) {
        if (board.canStick(n) && ringOf(n) <= spec.size) free.add(n);
      }
    }
    if (free.isEmpty) return;
    final list = free.toList()..sort((a, b) => ringOf(a).compareTo(ringOf(b)) != 0 ? ringOf(a).compareTo(ringOf(b)) : a.compareTo(b));
    final count = min(spec.tier, list.length);
    final colors = board.colorsLeft.isEmpty ? List.generate(spec.colors, (i) => i) : board.colorsLeft.toList();
    for (var i = 0; i < count; i++) {
      final kind = spec.boss == BossKind.mirage && ringOf(list[i]) == 1 ? BubbleKind.ice : BubbleKind.color;
      board.cells[list[i]] = Bubble(kind, colors[rng.nextInt(colors.length)]);
    }
    events.add(GameEvent.regrow);
  }

  /// On a clear, every leftover bubble (stones, bombs, the boss shell) bursts for a few points.
  void _burstLeftovers() {
    for (final e in board.cells.entries.toList()) {
      if (e.value.kind == BubbleKind.pivot) continue;
      final p = cellWorld(e.key);
      fx.add(Fx(p.x, p.y, e.value, life: 0.5));
      _burst(p.x, p.y, e.value.color, 4);
      board.cells.remove(e.key);
      run.score += 10;
    }
  }

  int get _shotsBonus => shotsLeft * 40;

  /// Adds the end-of-level bonus to the score and returns the break-screen numbers.
  LevelSummary finish() {
    run.score += _shotsBonus;
    return LevelSummary(
      popped: popped,
      dropped: dropped,
      bestCombo: bestCombo,
      accuracy: shots == 0 ? 1 : scoringShots / shots,
      shotsLeft: shotsLeft,
      shotsBonus: _shotsBonus,
    );
  }

  /// Rewarded "+5 bubbles", once per level.
  void addShots(int n) {
    shotsLeft += n;
    bonusUsed = true;
    stuck = false;
  }

  int _pick() {
    final left = board.colorsLeft.toList()..sort();
    if (left.isEmpty) return rng.nextInt(spec.colors);
    return left[rng.nextInt(left.length)];
  }

  void _burst(double x, double y, int color, int n) {
    for (var i = 0; i < n; i++) {
      final a = rng.nextDouble() * 2 * pi, v = 40 + rng.nextDouble() * 140;
      particles.add(Particle(x, y, cos(a) * v, sin(a) * v, 0.35 + rng.nextDouble() * 0.4, color));
    }
  }

  void _updateFx(double dt) {
    for (final f in fx) {
      f.life -= dt;
      if (f.falling) {
        f.vy += 900 * dt;
        f.x += f.vx * dt;
        f.y += f.vy * dt;
      }
    }
    fx.removeWhere((f) => f.life <= 0 || f.y > height + 40);
    for (final p in particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 1 - 3 * dt;
      p.vy *= 1 - 3 * dt;
    }
    particles.removeWhere((p) => p.life <= 0);
    for (final p in popups) {
      p.life -= dt;
      p.y -= 30 * dt;
    }
    popups.removeWhere((p) => p.life <= 0);
  }
}
