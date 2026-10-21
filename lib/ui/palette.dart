import 'package:flutter/material.dart';

const background = Color(0xFF080714);
const accent = Color(0xFF38E1FF); // cyan
const hot = Color(0xFFFF4FD8); // neon pink
const gold = Color(0xFFFFD447);
const danger = Color(0xFFFF4D6D);

/// Bubble colours by palette index.
const bubbleColors = <Color>[
  Color(0xFFFF4FD8), // pink
  Color(0xFF38E1FF), // cyan
  Color(0xFF7CFF6B), // lime
  Color(0xFFFFE14D), // yellow
  Color(0xFFFF8A3D), // orange
  Color(0xFFA77BFF), // violet
];

/// Colour for a palette index, white for -1 (sparks, stones, bombs).
Color bubbleColor(int i) => i < 0 ? const Color(0xFFFFF4D6) : bubbleColors[i % bubbleColors.length];

/// Boss colours by [BossKind] index.
const bossColors = <Color>[
  Color(0xFFFF5D9E), // medusa
  Color(0xFFFFB020), // hive
  Color(0xFF5DF2FF), // gyre
  Color(0xFFB8F3FF), // mirage
  Color(0xFFC77BFF), // nucleus
];

/// Night-sky tint for a level.
Color levelTint(double hue) => HSVColor.fromAHSV(1, hue, 0.65, 0.2).toColor();

TextStyle neon(double size, {Color color = accent, FontWeight weight = FontWeight.w900, double spacing = 2}) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: size * 0.5)],
    );
