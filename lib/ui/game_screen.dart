import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/levels.dart';
import '../game/world.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import 'ad_slot.dart';
import 'palette.dart';
import 'services.dart';
import 'world_painter.dart';

enum _Phase { playing, paused, cleared, outOfShots, over }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.startLevel, this.random, this.autopilot});

  final int startLevel;

  /// Takes the shots instead of the player (tests and previews).
  final void Function(World world)? autopilot;

  /// Seeded in tests.
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Run _run = Run(level: widget.startLevel);
  late World _world = World(_run, rng: widget.random);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _frame = ValueNotifier(0);
  final _bokeh = Bokeh();
  _Phase _phase = _Phase.playing;
  LevelSummary? _summary;
  bool _newBest = false;

  // Pointer aiming: drag to aim, release to shoot; hover shows the guide on desktop.
  bool _aiming = false, _hovering = false, _swapPress = false;

  late ProgressStore _progress;
  late AdService _ads;
  late SoundService _sound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = Services.of(context);
    _progress = services.progress;
    _ads = services.ads;
    _sound = services.sound;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) setState(() => _phase = _Phase.paused);
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;
    if (_phase != _Phase.playing) return;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final left = keys.contains(LogicalKeyboardKey.arrowLeft) || keys.contains(LogicalKeyboardKey.keyA);
    final right = keys.contains(LogicalKeyboardKey.arrowRight) || keys.contains(LogicalKeyboardKey.keyD);
    if (left != right) {
      final fine = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
      _world.setAim(_world.aim + (left ? 1 : -1) * dt * (fine ? 0.35 : 1.4));
      _hovering = true;
    }
    if (widget.autopilot != null && _world.ready) widget.autopilot!(_world);
    _world.update(dt);
    _handleEvents();
    _frame.value++;
  }

  void _handleEvents() {
    for (final e in _world.events) {
      switch (e) {
        case GameEvent.shoot:
          _sound.play(Sfx.shoot);
        case GameEvent.bounce:
          _sound.play(Sfx.bounce);
        case GameEvent.stick:
          _sound.play(Sfx.stick);
        case GameEvent.pop:
          _sound.play(Sfx.pop);
        case GameEvent.fall:
          _sound.play(Sfx.fall);
        case GameEvent.bomb:
          _sound.play(Sfx.bomb);
          HapticFeedback.mediumImpact();
        case GameEvent.thaw:
          _sound.play(Sfx.thaw);
        case GameEvent.ceilingDrop:
          _sound.play(Sfx.drop);
          HapticFeedback.mediumImpact();
        case GameEvent.bossHit:
          _sound.play(Sfx.bossHit);
          HapticFeedback.mediumImpact();
        case GameEvent.shieldBlock:
          _sound.play(Sfx.shield);
        case GameEvent.regrow:
          _sound.play(Sfx.regrow);
        case GameEvent.bossDown:
          _sound.play(Sfx.bossDown);
          HapticFeedback.heavyImpact();
        case GameEvent.levelClear:
          _onCleared();
        case GameEvent.outOfShots:
          _onOver(outOfShots: true);
        case GameEvent.gameOver:
          _onOver(outOfShots: false);
      }
    }
    _world.events.clear();
  }

  void _onCleared() {
    _sound.play(Sfx.levelClear);
    final next = _run.level + 1;
    _progress.reachLevel(next, LevelSpec.checkpointFor(next));
    if (_world.spec.isBoss) _progress.bossBeaten();
    setState(() {
      _summary = _world.finish();
      _phase = _Phase.cleared;
    });
  }

  Future<void> _onOver({required bool outOfShots}) async {
    _sound.play(Sfx.gameOver);
    setState(() => _phase = outOfShots ? _Phase.outOfShots : _Phase.over);
    await _progress.reachLevel(_run.level, LevelSpec.checkpointFor(_run.level));
    final best = await _progress.recordScore(_run.score);
    if (mounted) setState(() => _newBest = best);
  }

  bool _advancing = false;

  Future<void> _nextLevel() async {
    if (_phase != _Phase.cleared || _advancing) return;
    _advancing = true;
    await _ads.showInterstitial();
    _advancing = false;
    if (!mounted) return;
    setState(() {
      _run.level++;
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
    });
  }

  /// Rewarded "+5 bubbles", once per level.
  Future<void> _moreBubbles() async {
    if (_world.bonusUsed || !await _ads.showRewarded() || !mounted) return;
    setState(() {
      _world.addShots(5);
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _retry() {
    setState(() {
      _run = Run(level: LevelSpec.checkpointFor(_run.level));
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _togglePause() {
    if (_phase == _Phase.playing) {
      setState(() => _phase = _Phase.paused);
    } else if (_phase == _Phase.paused) {
      setState(() => _phase = _Phase.playing);
    }
  }

  void _shoot() {
    if (_phase == _Phase.playing) _world.shoot();
  }

  void _swap() {
    if (_phase != _Phase.playing || _world.finished || _world.stuck) return;
    _world.swap();
    _sound.play(Sfx.swap);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
      _togglePause();
      return KeyEventResult.handled;
    }
    if (_phase == _Phase.cleared && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space)) {
      _nextLevel();
      return KeyEventResult.handled;
    }
    if (_phase != _Phase.playing) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.keyW) {
      _shoot();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.tab) {
      _swap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- pointer ----

  bool _onNext(Offset f) => (f - const Offset(WorldPainter.nextX, World.shooterY + 8)).distance < 30;

  void _pointerDown(PointerDownEvent e, FieldTransform t) {
    if (_phase != _Phase.playing) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons == kSecondaryMouseButton) {
      _swap();
      return;
    }
    final f = t.toField(e.localPosition);
    if (_onNext(f)) {
      _swapPress = true;
      return;
    }
    _aiming = true;
    _aimAt(f);
  }

  void _pointerMove(PointerMoveEvent e, FieldTransform t) {
    if (_aiming) _aimAt(t.toField(e.localPosition));
  }

  void _pointerUp(PointerUpEvent e, FieldTransform t) {
    final f = t.toField(e.localPosition);
    if (_swapPress) {
      _swapPress = false;
      if (_onNext(f)) _swap();
      return;
    }
    if (!_aiming) return;
    _aiming = false;
    // Releasing low (back near the launcher) cancels the shot.
    if (f.dy < World.shooterY - 24) _shoot();
  }

  void _aimAt(Offset f) {
    if (f.dy < World.shooterY - 4) _world.aimAt(f.dx, f.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, constraints) {
          final t = FieldTransform(constraints.biggest);
          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (e) {
              _hovering = true;
              _aimAt(t.toField(e.localPosition));
            },
            onExit: (_) => _hovering = false,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _pointerDown(e, t),
              onPointerMove: (e) => _pointerMove(e, t),
              onPointerUp: (e) => _pointerUp(e, t),
              onPointerCancel: (_) => _aiming = _swapPress = false,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: WorldPainter(_world, _bokeh, guide: () => _aiming || _hovering, repaint: _frame),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: t.rect,
                    child: SafeArea(
                      child: ListenableBuilder(listenable: _frame, builder: (context, _) => _hud(t.scale)),
                    ),
                  ),
                  if (_phase != _Phase.playing) Positioned.fill(child: _overlay()),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---- HUD ----

  Widget _hud(double scale) {
    final w = _world;
    final boss = w.boss;
    final textScale = scale.clamp(0.8, 1.6);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 14 * textScale, color: Colors.white, fontWeight: FontWeight.w800),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const Key('pause'),
                        onPressed: _togglePause,
                        icon: const Icon(Icons.pause_rounded),
                        color: Colors.white70,
                        tooltip: 'Pause',
                      ),
                      Text('${_run.score}', key: const Key('score'), style: neon(20 * textScale, color: Colors.white, spacing: 1)),
                      if (w.combo > 1) ...[
                        const SizedBox(width: 6),
                        Text('COMBO ×${w.combo}', style: neon(11 * textScale, color: gold, spacing: 1)),
                      ],
                      const Spacer(),
                      Text('LV ${_run.level}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                      const SizedBox(width: 10),
                      _dropMeter(textScale),
                    ],
                  ),
                  if (boss != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
                      child: _bossBar(boss, textScale),
                    ),
                ],
              ),
            ),
            if (_phase == _Phase.playing) _banner(textScale),
          ],
        ),
      ),
    );
  }

  /// Dots counting down the misses before the ceiling drops.
  Widget _dropMeter(double textScale) {
    final w = _world;
    final left = w.spec.dropEvery - w.misses;
    return Tooltip(
      message: 'Misses before the ceiling drops',
      child: Row(
        children: [
          for (var i = 0; i < w.spec.dropEvery; i++)
            Container(
              width: 6 * textScale,
              height: 6 * textScale,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < left ? (left <= 1 ? danger : hot) : Colors.white12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _bossBar(Boss boss, double textScale) {
    final color = bossColors[boss.kind.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bossNames[boss.kind]!.toUpperCase(), style: neon(11 * textScale, color: color)),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: boss.hp / boss.maxHp,
            minHeight: 6,
            color: color,
            backgroundColor: Colors.white12,
          ),
        ),
      ],
    );
  }

  /// Level intro, or the boss intro.
  Widget _banner(double textScale) {
    final w = _world;
    final spec = w.spec;
    if (w.time > 2.6 || w.shots > 0) return const SizedBox.shrink();
    final fade = (w.time < 2.0 ? 1.0 : (2.6 - w.time) / 0.6).clamp(0.0, 1.0);
    final color = spec.isBoss ? bossColors[spec.boss!.index] : accent;
    return Align(
      alignment: const Alignment(0, 0.42),
      child: IgnorePointer(
        child: Opacity(
          opacity: fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spec.isBoss) Text('BOSS', style: neon(14 * textScale, color: hot, spacing: 8)),
              Text(spec.isBoss ? spec.name.toUpperCase() : 'LEVEL ${spec.number}', style: neon(30 * textScale, color: color, spacing: 5)),
              const SizedBox(height: 6),
              Text(
                spec.isBoss
                    ? bossBlurbs[spec.boss]!.toUpperCase()
                    : [spec.name.toUpperCase(), if (spec.motionLabel.isNotEmpty) spec.motionLabel.toUpperCase()].join(' · '),
                style: neon(12 * textScale, color: Colors.white70, spacing: 3),
              ),
              if (spec.isBoss || spec.tip != null) ...[
                const SizedBox(height: 8),
                Text(
                  spec.isBoss ? 'Uncover the eye and hit it' : spec.tip!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12 * textScale, color: gold, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---- overlays ----

  Widget _overlay() {
    final panel = switch (_phase) {
      _Phase.paused => _pausePanel(),
      _Phase.cleared => _clearedPanel(),
      _Phase.outOfShots => _overPanel(outOfShots: true),
      _Phase.over => _overPanel(outOfShots: false),
      _Phase.playing => const SizedBox.shrink(),
    };
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: panel),
          ),
        ),
      ),
    );
  }

  Widget _pausePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PAUSED', textAlign: TextAlign.center, style: neon(32, spacing: 6)),
        const SizedBox(height: 28),
        _button('Resume', _togglePause, primary: true),
        const SizedBox(height: 12),
        _button(_sound.muted ? 'Sound: off' : 'Sound: on', () async {
          await _sound.setMuted(!_sound.muted);
          setState(() {});
        }),
        const SizedBox(height: 12),
        _button('Quit to menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _clearedPanel() {
    final s = _summary!;
    final spec = _world.spec;
    final next = LevelSpec.forLevel(_run.level + 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(spec.isBoss ? 'BOSS DEFEATED' : 'LEVEL ${spec.number} CLEAR',
            textAlign: TextAlign.center, style: neon(26, color: spec.isBoss ? gold : accent, spacing: 4)),
        if (spec.isBoss)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Checkpoint saved · level ${_run.level + 1}',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
          ),
        const SizedBox(height: 16),
        _stat('Popped', '${s.popped}'),
        _stat('Dropped', '${s.dropped}'),
        _stat('Best combo', '×${s.bestCombo}'),
        _stat('Accuracy', '${(s.accuracy * 100).round()}%'),
        if (s.shotsBonus > 0) _stat('Bubbles left · ${s.shotsLeft}', '+${s.shotsBonus}', color: gold),
        const Divider(color: Colors.white24, height: 20),
        _stat('Score', '${_run.score}', big: true),
        const SizedBox(height: 18),
        const Center(child: AdSlot()),
        const SizedBox(height: 18),
        Text(
          next.isBoss ? 'BOSS AHEAD: ${next.name.toUpperCase()}' : 'NEXT · LEVEL ${next.number} · ${next.name.toUpperCase()}',
          textAlign: TextAlign.center,
          style: neon(12, color: next.isBoss ? hot : Colors.white70, spacing: 2),
        ),
        const SizedBox(height: 12),
        _button('Continue', _nextLevel, primary: true, key: const Key('continue')),
      ],
    );
  }

  Widget _overPanel({required bool outOfShots}) {
    final checkpoint = LevelSpec.checkpointFor(_run.level);
    final canRescue = outOfShots && !_world.bonusUsed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(outOfShots ? 'OUT OF BUBBLES' : 'GAME OVER', textAlign: TextAlign.center, style: neon(30, color: hot, spacing: 5)),
        if (!outOfShots)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('The bubbles crossed the line',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          ),
        const SizedBox(height: 16),
        _stat('Level reached', '${_run.level}'),
        _stat('Score', '${_run.score}', big: true),
        if (_newBest) Text('NEW BEST', textAlign: TextAlign.center, style: neon(16, color: gold)),
        const SizedBox(height: 24),
        if (canRescue) ...[
          _button('+5 bubbles · watch an ad', _moreBubbles, primary: true, icon: Icons.play_circle_fill_rounded, key: const Key('rescue')),
          const SizedBox(height: 12),
        ],
        _button('Retry from level $checkpoint', _retry, primary: !canRescue, key: const Key('retry')),
        const SizedBox(height: 12),
        _button('Menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _stat(String label, String value, {bool big = false, Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.white60, fontSize: big ? 16 : 14)),
          const Spacer(),
          Text(value, style: big ? neon(22, color: color, spacing: 1) : TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, {bool primary = false, IconData? icon, Key? key}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const padding = EdgeInsets.symmetric(vertical: 16);
    return primary
        ? FilledButton(
            key: key,
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, shape: shape, padding: padding),
            child: child,
          )
        : OutlinedButton(
            key: key,
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
              shape: shape,
              padding: padding,
            ),
            child: child,
          );
  }
}
