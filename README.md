# Neon Pop

Calm neon bubble shooter by Kallistesoft. Play it at https://pop.kallistesoft.ca.

- Drag to aim (the guide shows wall bounces), release to shoot. Three or more of
  a colour pop; anything no longer hanging from the ceiling falls for bonus
  points. Tap the next bubble to swap.
- A level is cleared when no coloured bubbles are left (stones don't count).
  Each level has a limited number of bubbles; every few misses the ceiling
  drops. Running out of bubbles, or letting the board cross the line, ends the
  run.
- Every level is generated from its number: 12 hanging shapes (pyramid, heart,
  columns, diamond, waves, rings, crown, spiral, hourglass, chevrons, lattice,
  wall), drifting boards, and 4 spinning hub boards (bloom, star, pinwheel,
  nebula). Specials: bombs, rainbows, stones, ice (two matches). Colours, drop
  speed and spin speed rise; shots per bubble fall.
- Every 5th level is a boss: an eye inside a bubble shell. Clear the shell and
  hit the eye until its HP bar is empty. Medusa (drifts), The Hive (regrows),
  Gyre (spins behind a shield), Mirage (frozen shell that regrows), The Nucleus
  (all of it); then they come back stronger.
- Game over sends you back to the level after the last boss beaten. One
  rewarded "+5 bubbles" per level when you run out.
- Between levels, a break screen with an `AdSlot` (300×250) placeholder and
  `AdService.showInterstitial()` on Continue. Both are no-ops until an ad network
  is wired in (`lib/services/ad_service.dart`, `lib/ui/ad_slot.dart`).

## Code

- `lib/game/board.dart`: hex lattice, matches, bombs, ice, falls (pure Dart, tested).
- `lib/game/levels.dart`: level specs and boards built from the level number.
- `lib/game/world.dart`: the whole simulation in a fixed 360×640 field. Shots move
  in fixed steps, so `trace()` predicts a shot exactly (aim guide, bot test).
- `lib/ui/`: screens and the canvas renderer. No image assets: everything is drawn.
- `tools/make_sfx.py`: synthesizes the sound effects into `assets/sfx`.
- `test/bot.dart`: a bot that plays with the real physics; `world_test.dart`
  proves levels 1–35 (bosses included) can be cleared within their shots.

## Run

```
flutter test
flutter run -d chrome
```

Desktop controls: mouse to aim and click to shoot (right click swaps), or arrow
keys (Shift for fine aim) + Space, S to swap, Esc to pause.

Every push to `main` builds and deploys the web version to GitHub Pages
(`.github/workflows/web.yml`).
