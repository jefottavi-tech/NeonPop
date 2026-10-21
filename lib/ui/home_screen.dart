import 'dart:math';

import 'package:flutter/material.dart';

import '../game/board.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import 'game_screen.dart';
import 'palette.dart';
import 'services.dart';
import 'world_painter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  final _bokeh = Bokeh(3);

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _play(int level) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameScreen(startLevel: level)));
    if (mounted) setState(() {}); // refresh best score and checkpoint
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final ProgressStore progress = services.progress;
    final SoundService sound = services.sound;
    final checkpoint = progress.checkpoint;
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BackdropPainter(_bokeh, _spin)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 70, child: CustomPaint(painter: _ClusterPainter(_spin))),
                      const SizedBox(height: 8),
                      Text('NEON', textAlign: TextAlign.center, style: neon(64, spacing: 14)),
                      Text('POP', textAlign: TextAlign.center, style: neon(64, color: hot, spacing: 14)),
                      const SizedBox(height: 8),
                      Text('Aim. Bounce. Let it all fall.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), letterSpacing: 1)),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          _Stat(label: 'BEST SCORE', value: '${progress.bestScore}'),
                          _Stat(label: 'BEST LEVEL', value: '${progress.bestLevel}'),
                          _Stat(label: 'BOSSES', value: '${progress.bossesBeaten}'),
                        ],
                      ),
                      const SizedBox(height: 28),
                      if (checkpoint > 1) ...[
                        FilledButton(
                          key: const Key('continue-run'),
                          onPressed: () => _play(checkpoint),
                          style: _primary,
                          child: Text('CONTINUE · LEVEL $checkpoint', style: _label),
                        ),
                        const SizedBox(height: 12),
                      ],
                      (checkpoint > 1 ? OutlinedButton.new : FilledButton.new)(
                        key: const Key('play'),
                        onPressed: () => _play(1),
                        style: checkpoint > 1 ? _secondary : _primary,
                        child: Text(checkpoint > 1 ? 'NEW GAME' : 'PLAY', style: _label),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Drag to aim, release to shoot · tap the next bubble to swap\n'
                        'Match 3 to pop · cut a group loose to drop it\n'
                        'Desktop: mouse, or arrows + Space · S swap · Esc pause\n'
                        'A boss waits every 5 levels',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), height: 1.6, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: IconButton(
                          tooltip: sound.muted ? 'Sound off' : 'Sound on',
                          onPressed: () async {
                            await sound.setMuted(!sound.muted);
                            setState(() {});
                          },
                          icon: Icon(sound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white54),
                        ),
                      ),
                      Text('Kallistesoft', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _label = TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2);
  static final _shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  static final _primary = FilledButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(vertical: 18),
    shape: _shape,
  );
  static final _secondary = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: const BorderSide(color: Colors.white30),
    padding: const EdgeInsets.symmetric(vertical: 18),
    shape: _shape,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: neon(22, color: Colors.white, spacing: 1)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: Colors.white.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.bokeh, this.anim) : super(repaint: anim);

  final Bokeh bokeh;
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [levelTint(290), background],
        ).createShader(Offset.zero & size),
    );
    bokeh.paint(canvas, Offset.zero & size, anim.value * 60);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => false;
}

/// A little bubble cluster bobbing above the title.
class _ClusterPainter extends CustomPainter {
  _ClusterPainter(this.anim) : super(repaint: anim);

  final Animation<double> anim;

  static const _cells = [(-2, 0, 0), (-1, 0, 1), (0, 0, 0), (1, 0, 2), (2, 0, 1), (-2, 1, 3), (-1, 1, 1), (0, 1, 5), (1, 1, 2)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 60;
    final c = Offset(size.width / 2, size.height / 2 - 10);
    for (final (col, row, color) in _cells) {
      final x = col * 2 * bubbleR + (row.isOdd ? bubbleR : 0);
      final bob = sin(t * 1.4 + col + row * 2) * 2.5;
      final p = c + Offset(x, row * rowH + bob);
      BubbleArt.draw(canvas, p, Bubble(BubbleKind.color, color), t);
    }
  }

  @override
  bool shouldRepaint(_ClusterPainter old) => false;
}
