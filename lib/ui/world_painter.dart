import 'dart:math';

import 'package:flutter/material.dart';

import '../game/board.dart';
import '../game/world.dart';
import 'palette.dart';

/// Maps the fixed 360×640 field into the widget, letterboxed.
class FieldTransform {
  FieldTransform(Size size)
      : scale = min(size.width / World.width, size.height / World.height),
        origin = Offset(
          (size.width - World.width * min(size.width / World.width, size.height / World.height)) / 2,
          (size.height - World.height * min(size.width / World.width, size.height / World.height)) / 2,
        );

  final double scale;
  final Offset origin;

  Rect get rect => origin & const Size(World.width, World.height) * scale;

  Offset toField(Offset p) => (p - origin) / scale;
}

/// Soft out-of-focus lights drifting upwards behind the board.
class Bokeh {
  Bokeh([int seed = 7]) {
    final rng = Random(seed);
    for (var i = 0; i < 26; i++) {
      _dots.add((rng.nextDouble(), rng.nextDouble(), 4 + rng.nextDouble() * 18, 4 + rng.nextDouble() * 10, rng.nextInt(6)));
    }
  }

  final _dots = <(double, double, double, double, int)>[];

  void paint(Canvas canvas, Rect area, double time) {
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (final (x, y, r, v, c) in _dots) {
      final py = area.height - (y * area.height + time * v) % (area.height + 40) + 20;
      paint.color = bubbleColors[c].withValues(alpha: 0.07 + (r / 22) * 0.06);
      canvas.drawCircle(Offset(area.left + x * area.width + sin(time * 0.3 + y * 9) * 8, area.top + py), r, paint);
    }
  }
}

/// Draws one bubble of any kind centred at the origin of the current canvas.
class BubbleArt {
  static final _glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;

  static void draw(Canvas canvas, Offset c, Bubble b, double time, {double scale = 1, double alpha = 1}) {
    const r = bubbleR - 0.6;
    final rr = r * scale;
    switch (b.kind) {
      case BubbleKind.color:
      case BubbleKind.ice:
        _glossy(canvas, c, rr, bubbleColor(b.color), alpha);
        _glyph(canvas, c, rr, b.color, alpha);
        if (b.kind == BubbleKind.ice) _frost(canvas, c, rr, alpha);
      case BubbleKind.rainbow:
        _glow.color = Colors.white.withValues(alpha: 0.35 * alpha);
        canvas.drawCircle(c, rr + 2, _glow);
        final shader = SweepGradient(
          colors: [...bubbleColors, bubbleColors.first].map((x) => x.withValues(alpha: alpha)).toList(),
          transform: GradientRotation(time * 1.5),
        ).createShader(Rect.fromCircle(center: c, radius: rr));
        canvas.drawCircle(c, rr, Paint()..shader = shader);
        canvas.drawCircle(c + Offset(-rr * 0.3, -rr * 0.35), rr * 0.25, Paint()..color = Colors.white.withValues(alpha: 0.7 * alpha));
      case BubbleKind.stone:
        canvas.drawCircle(
          c,
          rr,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.4),
              colors: [const Color(0xFF7A7890).withValues(alpha: alpha), const Color(0xFF2B2A38).withValues(alpha: alpha)],
            ).createShader(Rect.fromCircle(center: c, radius: rr)),
        );
        final crack = Paint()
          ..color = Colors.black.withValues(alpha: 0.45 * alpha)
          ..strokeWidth = 1.3
          ..style = PaintingStyle.stroke;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - rr * 0.5, c.dy - rr * 0.2)
            ..lineTo(c.dx - rr * 0.05, c.dy + rr * 0.05)
            ..lineTo(c.dx + rr * 0.1, c.dy + rr * 0.5)
            ..moveTo(c.dx - rr * 0.05, c.dy + rr * 0.05)
            ..lineTo(c.dx + rr * 0.45, c.dy - rr * 0.25),
          crack,
        );
        _stroke.color = Colors.white.withValues(alpha: 0.18 * alpha);
        canvas.drawCircle(c, rr, _stroke);
      case BubbleKind.bomb:
        final pulse = 0.5 + 0.5 * sin(time * 6);
        _glow.color = danger.withValues(alpha: (0.3 + 0.3 * pulse) * alpha);
        canvas.drawCircle(c, rr + 3, _glow);
        canvas.drawCircle(c, rr, Paint()..color = const Color(0xFF1B1622).withValues(alpha: alpha));
        _stroke.color = danger.withValues(alpha: alpha);
        canvas.drawCircle(c, rr - 1, _stroke);
        // Fuse and spark.
        final top = c + Offset(rr * 0.35, -rr * 0.85);
        canvas.drawLine(c + Offset(rr * 0.1, -rr * 0.6), top, Paint()
          ..color = const Color(0xFFB8A99A).withValues(alpha: alpha)
          ..strokeWidth = 2);
        canvas.drawCircle(top, 2.5 + pulse * 1.5, Paint()..color = gold.withValues(alpha: alpha));
        _glyphBomb(canvas, c, rr, alpha);
      case BubbleKind.pivot:
        _glow.color = accent.withValues(alpha: 0.5 * alpha);
        canvas.drawCircle(c, rr + 4, _glow);
        canvas.drawCircle(c, rr + 1, Paint()..color = const Color(0xFF14142A).withValues(alpha: alpha));
        _stroke.color = accent.withValues(alpha: alpha);
        canvas.drawCircle(c, rr - 1, _stroke);
        final spoke = Paint()
          ..color = accent.withValues(alpha: 0.7 * alpha)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final a = time * 2 + i * 2 * pi / 3;
          canvas.drawLine(c, c + Offset(cos(a), sin(a)) * (rr - 5), spoke);
        }
      case BubbleKind.core:
        break; // drawn by the boss painter
    }
  }

  static void _glossy(Canvas canvas, Offset c, double r, Color color, double alpha) {
    _glow.color = color.withValues(alpha: 0.45 * alpha);
    canvas.drawCircle(c, r + 2.5, _glow);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [
            Color.lerp(color, Colors.white, 0.45)!.withValues(alpha: alpha),
            color.withValues(alpha: alpha),
            Color.lerp(color, Colors.black, 0.45)!.withValues(alpha: alpha),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c + Offset(-r * 0.32, -r * 0.38), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.75 * alpha));
  }

  /// Small dark symbol per colour, so colours are never the only cue.
  static void _glyph(Canvas canvas, Offset c, double r, int color, double alpha) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.32 * alpha)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final s = r * 0.32;
    final o = c + Offset(r * 0.08, r * 0.12);
    switch (color % 6) {
      case 0:
        canvas.drawCircle(o, s * 0.55, p..style = PaintingStyle.fill);
      case 1:
        canvas.drawPath(Path()..addPolygon([o + Offset(0, -s), o + Offset(s, 0), o + Offset(0, s), o + Offset(-s, 0)], true), p);
      case 2:
        canvas.drawPath(Path()..addPolygon([o + Offset(0, -s), o + Offset(s, s * 0.8), o + Offset(-s, s * 0.8)], true), p);
      case 3:
        canvas.drawRect(Rect.fromCenter(center: o, width: s * 1.5, height: s * 1.5), p);
      case 4:
        canvas.drawLine(o + Offset(-s, 0), o + Offset(s, 0), p);
        canvas.drawLine(o + Offset(0, -s), o + Offset(0, s), p);
      default:
        canvas.drawCircle(o, s * 0.8, p);
    }
  }

  static void _glyphBomb(Canvas canvas, Offset c, double r, double alpha) {
    final p = Paint()..color = danger.withValues(alpha: 0.9 * alpha);
    canvas.drawRect(Rect.fromCenter(center: c + Offset(0, -r * 0.12), width: 3, height: r * 0.6), p);
    canvas.drawCircle(c + Offset(0, r * 0.38), 1.8, p);
  }

  static void _frost(Canvas canvas, Offset c, double r, double alpha) {
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE8F8FF).withValues(alpha: 0.42 * alpha));
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * alpha)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      final a = i * pi / 3 + pi / 6;
      final d = Offset(cos(a), sin(a)) * r * 0.62;
      canvas.drawLine(c - d, c + d, line);
    }
    _stroke.color = Colors.white.withValues(alpha: 0.9 * alpha);
    canvas.drawCircle(c, r, _stroke);
  }
}

class WorldPainter extends CustomPainter {
  WorldPainter(this.world, this.bokeh, {required this.guide, required Listenable repaint}) : super(repaint: repaint);

  final World world;
  final Bokeh bokeh;

  /// Whether to draw the aim guide this frame.
  final bool Function() guide;

  static final _glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  @override
  void paint(Canvas canvas, Size size) {
    final w = world;
    final tint = levelTint(w.spec.hue);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, background, background],
          stops: const [0, 0.65, 1],
        ).createShader(Offset.zero & size),
    );
    bokeh.paint(canvas, Offset.zero & size, w.time);

    final t = FieldTransform(size);
    canvas.save();
    canvas.translate(t.origin.dx, t.origin.dy);
    canvas.scale(t.scale);
    if (w.shake > 0) {
      final r = Random(w.time.hashCode);
      canvas.translate((r.nextDouble() - 0.5) * w.shake, (r.nextDouble() - 0.5) * w.shake);
    }
    _frame(canvas);
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, World.width, World.height));
    if (w.boss != null) _boss(canvas, behind: true);
    _board(canvas);
    if (w.boss != null) _boss(canvas, behind: false);
    if (guide() && w.ready) _guide(canvas);
    _fx(canvas);
    final s = w.shot;
    if (s != null) {
      BubbleArt.draw(canvas, Offset(s.x, s.y), Bubble(BubbleKind.color, s.color), w.time);
    }
    canvas.restore();
    _shooter(canvas);
    _popups(canvas);
    canvas.restore();
  }

  /// Walls, ceiling and the line the bubbles must not cross.
  void _frame(Canvas canvas) {
    final w = world;
    final wall = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, World.ceilingTop), const Offset(0, World.deadline + 30), wall);
    canvas.drawLine(const Offset(World.width, World.ceilingTop), const Offset(World.width, World.deadline + 30), wall);

    if (!w.board.hub) {
      final y = w.ceilingY;
      canvas.drawRect(Rect.fromLTRB(0, World.ceilingTop - 6, World.width, y), Paint()..color = const Color(0xFF15122A));
      // Bolts along the ceiling as it comes down.
      for (var yy = y - rowH; yy > World.ceilingTop; yy -= rowH) {
        canvas.drawLine(Offset(0, yy), Offset(World.width, yy), Paint()..color = Colors.white.withValues(alpha: 0.06));
      }
      _glow.color = hot.withValues(alpha: 0.6);
      canvas.drawRect(Rect.fromLTWH(0, y - 2, World.width, 4), _glow);
      canvas.drawRect(Rect.fromLTWH(0, y - 1, World.width, 2), Paint()..color = hot);
    }

    // Deadline: dashed, brighter as the board gets close.
    final reach = w.origin().y + w.board.reach;
    final danger0 = ((reach - (World.deadline - 120)) / 120).clamp(0.0, 1.0);
    final dash = Paint()
      ..color = Color.lerp(Colors.white24, danger, danger0)!.withValues(alpha: 0.35 + 0.5 * danger0)
      ..strokeWidth = 1.5;
    for (var x = 4.0; x < World.width; x += 14) {
      canvas.drawLine(Offset(x, World.deadline), Offset(x + 7, World.deadline), dash);
    }
  }

  void _board(Canvas canvas) {
    final w = world;
    for (final e in w.board.cells.entries) {
      if (e.value.kind == BubbleKind.core) continue;
      final p = w.cellWorld(e.key);
      BubbleArt.draw(canvas, Offset(p.x, p.y), e.value, w.time);
    }
  }

  void _boss(Canvas canvas, {required bool behind}) {
    final w = world, b = w.boss!;
    final o = w.origin();
    final c = Offset(o.x, o.y);
    final color = bossColors[b.kind.index];
    final alive = b.hp > 0;
    if (behind) {
      // Aura and tendrils behind the shell.
      final pulse = 0.5 + 0.5 * sin(w.time * 2.2);
      _glow.color = color.withValues(alpha: alive ? 0.18 + 0.1 * pulse : 0.05);
      canvas.drawCircle(c, (w.spec.size + 1) * 2 * bubbleR, _glow);
      final tendril = Paint()
        ..color = color.withValues(alpha: alive ? 0.35 : 0.1)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final n = 6 + b.kind.index;
      final len = (w.spec.size + 1.4) * 2 * bubbleR;
      for (var i = 0; i < n; i++) {
        final a = w.angle() + i * 2 * pi / n;
        final path = Path()..moveTo(c.dx, c.dy);
        for (var k = 1; k <= 8; k++) {
          final d = len * k / 8;
          final wob = sin(w.time * 2 + k * 0.9 + i) * 6 * k / 8;
          path.lineTo(c.dx + cos(a) * d - sin(a) * wob, c.dy + sin(a) * d + cos(a) * wob);
        }
        canvas.drawPath(path, tendril);
      }
      return;
    }
    if (!alive) return;
    const r = World.coreR;
    final flash = b.flash > 0;
    _glow.color = color.withValues(alpha: 0.7);
    canvas.drawCircle(c, r + 5, _glow);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: flash ? [Colors.white, Colors.white] : [Color.lerp(color, Colors.white, 0.4)!, color, Color.lerp(color, Colors.black, 0.55)!],
          stops: flash ? null : const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // One big eye that follows the aim.
    final look = Offset(cos(w.aim), -sin(w.aim)) * -1;
    final blink = (w.time % 4.3) < 0.12;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, blink ? 0.12 : 1);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 1.25, height: r * 1.0), Paint()..color = const Color(0xFFF6F2FF));
    canvas.drawCircle(look * r * 0.18, r * 0.3, Paint()..color = const Color(0xFF120A1E));
    canvas.drawCircle(look * r * 0.18 + Offset(-r * 0.08, -r * 0.1), r * 0.08, Paint()..color = Colors.white);
    canvas.restore();

    if (w.spec.bossShield) {
      final a = w.shieldAngle();
      final arc = w.spec.shieldArc;
      final rect = Rect.fromCircle(center: c, radius: r + 6);
      final glow = Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      final line = Paint()
        ..color = const Color(0xFFDFFBFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, a - arc / 2, arc, false, glow);
      canvas.drawArc(rect, a - arc / 2, arc, false, line);
    }
  }

  void _guide(Canvas canvas) {
    final w = world;
    final path = <Point<double>>[];
    final r = w.trace(w.aim, path: path);
    final color = bubbleColor(w.current);
    final dot = Paint()..color = color.withValues(alpha: 0.75);
    var travelled = 0.0;
    const gap = 13.0;
    var next = gap;
    for (var i = 0; i + 1 < path.length; i++) {
      final a = path[i], b = path[i + 1];
      final len = a.distanceTo(b);
      while (next <= travelled + len) {
        final f = (next - travelled) / len;
        final fade = (1 - next / 900).clamp(0.25, 1.0);
        dot.color = color.withValues(alpha: 0.75 * fade);
        canvas.drawCircle(Offset(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f), 2.4, dot);
        next += gap;
      }
      travelled += len;
    }
    if (r.contact == Contact.stick && r.cell != null) {
      final p = w.cellWorld(r.cell!);
      final ring = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(p.x, p.y), bubbleR - 2, ring);
    }
  }

  void _fx(Canvas canvas) {
    final w = world;
    for (final f in w.fx) {
      final k = (f.life / f.maxLife).clamp(0.0, 1.0);
      if (f.falling) {
        BubbleArt.draw(canvas, Offset(f.x, f.y), f.bubble, w.time, alpha: 0.85);
      } else {
        // Pop: the bubble swells and fades, with a ring flying out.
        final color = f.bubble.kind == BubbleKind.bomb ? danger : bubbleColor(f.bubble.color);
        BubbleArt.draw(canvas, Offset(f.x, f.y), f.bubble, w.time, scale: 1 + (1 - k) * 0.5, alpha: k * k);
        canvas.drawCircle(
          Offset(f.x, f.y),
          bubbleR * (1 + (1 - k) * 1.2),
          Paint()
            ..color = color.withValues(alpha: k * 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    final paint = Paint();
    for (final p in w.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      paint.color = bubbleColor(p.color).withValues(alpha: a);
      canvas.drawCircle(Offset(p.x, p.y), 1.2 + a * 1.8, paint);
    }
  }

  /// Launcher, current and next bubble, shots left.
  void _shooter(Canvas canvas) {
    final w = world;
    const c = Offset(World.shooterX, World.shooterY);
    // Base arc.
    final base = Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawArc(Rect.fromCircle(center: c, radius: 30), pi * 0.05, pi * 0.9, false, base);
    // Barrel pointing along the aim.
    final dir = Offset(cos(w.aim), -sin(w.aim));
    _glow.color = accent.withValues(alpha: 0.5);
    canvas.drawLine(c + dir * 22, c + dir * 36, _glow..strokeWidth = 7);
    canvas.drawLine(
      c + dir * 22,
      c + dir * 36,
      Paint()
        ..color = accent
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 22, Paint()..color = const Color(0xFF14122A));
    canvas.drawCircle(c, 22, base..color = accent.withValues(alpha: 0.6));
    if (!w.stuck && w.shotsLeft > 0 && w.shot == null) {
      BubbleArt.draw(canvas, c, Bubble(BubbleKind.color, w.current), w.time);
    }

    // Next bubble with a swap hint.
    const n = Offset(nextX, World.shooterY + 8);
    canvas.drawCircle(n, 18, Paint()..color = const Color(0xFF14122A));
    canvas.drawCircle(
      n,
      18,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    if (w.shotsLeft > 1) BubbleArt.draw(canvas, n, Bubble(BubbleKind.color, w.next), w.time, scale: 0.72);
    _text(canvas, 'SWAP', n + const Offset(0, 28), 8, Colors.white38);

    // Shots left.
    final low = w.shotsLeft <= 5;
    _text(canvas, '${w.shotsLeft}', const Offset(shotsX, World.shooterY + 2), 22, low ? danger : Colors.white, glow: true);
    _text(canvas, 'BUBBLES', const Offset(shotsX, World.shooterY + 24), 8, Colors.white38);
  }

  static const nextX = 104.0, shotsX = 262.0;

  void _popups(Canvas canvas) {
    for (final p in world.popups) {
      final a = (p.life / 0.4).clamp(0.0, 1.0);
      _text(canvas, p.text, Offset(p.x, p.y), p.big ? 20 : 14, (p.big ? gold : Colors.white).withValues(alpha: a), glow: true);
    }
  }

  static void _text(Canvas canvas, String s, Offset c, double size, Color color, {bool glow = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: size < 10 ? 1.5 : 0.5,
          shadows: glow ? [Shadow(color: color.withValues(alpha: 0.7), blurRadius: size * 0.5)] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(WorldPainter old) => old.world != world;
}

