import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_pop/main.dart';
import 'package:neon_pop/services/ad_service.dart';
import 'package:neon_pop/services/progress_store.dart';
import 'package:neon_pop/services/sound_service.dart';
import 'package:neon_pop/ui/game_screen.dart';
import 'package:neon_pop/ui/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bot.dart';

void main() {
  testWidgets('start a game from the home screen, shoot, pause and quit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressStore.open();
    final sound = NoSound();
    await tester.binding.setSurfaceSize(const Size(412, 880));
    await tester.pumpWidget(NeonPopApp(progress: progress, ads: const NoAdService(), sound: sound));
    expect(find.text('NEON'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play')));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('LEVEL 1'), findsOneWidget);

    // Drag up from the launcher and release: a shot goes out.
    final gesture = await tester.startGesture(const Offset(206, 600));
    await gesture.moveTo(const Offset(150, 300));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(sound.played, contains(Sfx.shoot));
    expect(find.text('LEVEL 1'), findsNothing); // the intro goes once you play

    await tester.tap(find.byKey(const Key('pause')));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('Quit to menu'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the home backdrop never settles
    expect(find.text('NEON'), findsOneWidget);
  });

  breakScreen();
}

class _CountingAds implements AdService {
  int interstitials = 0;

  @override
  Future<void> showInterstitial() async => interstitials++;

  @override
  Future<bool> showRewarded() async => true;
}

void breakScreen() {
  testWidgets('clearing a level shows the break screen with the ad slot; continue shows an interstitial', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressStore.open();
    final ads = _CountingAds();
    await tester.binding.setSurfaceSize(const Size(412, 880));
    await tester.pumpWidget(Services(
      progress: progress,
      ads: ads,
      sound: NoSound(),
      child: MaterialApp(home: GameScreen(startLevel: 1, random: Random(4), autopilot: (w) => Bot.play(w))),
    ));
    for (var i = 0; i < 3000 && find.byKey(const Key('continue')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(find.text('LEVEL 1 CLEAR'), findsOneWidget);
    expect(find.byKey(const Key('ad-slot')), findsOneWidget);
    expect(progress.bestLevel, 2);
    await tester.ensureVisible(find.byKey(const Key('continue')));
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ads.interstitials, 1);
    expect(find.text('LEVEL 2'), findsOneWidget);
  });
}
