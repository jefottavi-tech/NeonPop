import 'dart:math';

/// Bubble radius and the vertical distance between hex rows.
const bubbleR = 17.0;
const rowH = bubbleR * 1.7320508075688772;

/// Hex cells use axial coordinates (q, r) packed into one int, so maps stay fast.
int cell(int q, int r) => (q + 512) * 1024 + (r + 512);
int cellQ(int c) => c ~/ 1024 - 512;
int cellR(int c) => c % 1024 - 512;

/// Cell for a column and row of a ceiling board (odd rows sit half a bubble to the right).
int gridCell(int col, int row) => cell(col - (row >> 1), row);
int cellCol(int c) => cellQ(c) + (cellR(c) >> 1);

const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1)];

Iterable<int> neighbours(int c) sync* {
  final q = cellQ(c), r = cellR(c);
  for (final (dq, dr) in _dirs) {
    yield cell(q + dq, r + dr);
  }
}

/// Hex distance from the origin cell.
int ringOf(int c) {
  final q = cellQ(c), r = cellR(c);
  return (q.abs() + r.abs() + (q + r).abs()) ~/ 2;
}

/// Centre of a cell in the board's own (unrotated) frame; cell (0, 0) is at the origin.
Point<double> cellPos(int c) {
  final q = cellQ(c), r = cellR(c);
  return Point(2 * bubbleR * (q + r / 2), r * rowH);
}

/// The cell whose centre is nearest to a point in the board frame.
int nearestCell(double x, double y) {
  final rf = y / rowH;
  final qf = x / (2 * bubbleR) - rf / 2;
  final sf = -qf - rf;
  var q = qf.round(), r = rf.round();
  final s = sf.round();
  final dq = (q - qf).abs(), dr = (r - rf).abs(), ds = (s - sf).abs();
  if (dq > dr && dq > ds) {
    q = -r - s;
  } else if (dr > ds) {
    r = -q - s;
  }
  return cell(q, r);
}

enum BubbleKind {
  /// Plain coloured bubble.
  color,

  /// Coloured, but the first match only thaws it.
  ice,

  /// Explodes when a bubble lands next to it or a neighbour pops.
  bomb,

  /// Matches any colour.
  rainbow,

  /// Never matches; only falls or gets blown up.
  stone,

  /// Fixed hub of a spinning board.
  pivot,

  /// The boss's heart: hit it directly to hurt the boss.
  core,
}

class Bubble {
  const Bubble(this.kind, [this.color = -1]);

  final BubbleKind kind;

  /// Palette index for colour, ice; -1 otherwise.
  final int color;

  bool get colored => kind == BubbleKind.color || kind == BubbleKind.ice;
  bool get fixed => kind == BubbleKind.pivot || kind == BubbleKind.core;
}

/// What a landed bubble did to the board.
class Outcome {
  final popped = <int, Bubble>{};
  final exploded = <int, Bubble>{};
  final fallen = <int, Bubble>{};
  final thawed = <int>[];
  int bombs = 0;

  /// Anything happened that counts as progress (not a miss).
  bool get scored => popped.isNotEmpty || exploded.isNotEmpty || thawed.isNotEmpty;
  int get removed => popped.length + exploded.length + fallen.length;
}

/// The bubble lattice, either hanging from the ceiling (row 0 holds everything
/// up) or built around a fixed hub at cell (0, 0). Pure logic, no geometry in
/// world space: the World places and moves the board.
class Board {
  Board({required this.hub, this.cols = 10, this.maxRing = 6, Map<int, Bubble>? cells}) : cells = cells ?? {};

  final bool hub;

  /// Ceiling boards: bubbles per row.
  final int cols;

  /// Hub boards: how far from the hub bubbles may stick.
  final int maxRing;
  final Map<int, Bubble> cells;

  Board copy() => Board(hub: hub, cols: cols, maxRing: maxRing, cells: Map.of(cells));

  bool valid(int c) {
    if (hub) return ringOf(c) <= maxRing;
    final r = cellR(c), col = cellCol(c);
    return r >= 0 && col >= 0 && col < cols;
  }

  bool isAnchor(int c) => hub ? c == cell(0, 0) : cellR(c) == 0;

  /// An empty cell a bubble can stick to.
  bool canStick(int c) => valid(c) && !cells.containsKey(c) && (isAnchor(c) || neighbours(c).any(cells.containsKey));

  int get coloredCount => cells.values.where((b) => b.colored).length;

  Set<int> get colorsLeft => {for (final b in cells.values) if (b.colored) b.color};

  /// Same-colour group through [start] (rainbows join any colour).
  Set<int> cluster(int start, int color) {
    final seen = {start};
    final todo = [start];
    while (todo.isNotEmpty) {
      for (final n in neighbours(todo.removeLast())) {
        final b = cells[n];
        if (b == null || seen.contains(n)) continue;
        if ((b.colored && b.color == color) || b.kind == BubbleKind.rainbow) {
          seen.add(n);
          todo.add(n);
        }
      }
    }
    return seen;
  }

  /// Cells no longer held up by the ceiling or the hub.
  Set<int> floating() {
    final held = <int>{};
    final todo = <int>[];
    for (final c in cells.keys) {
      if (isAnchor(c)) {
        held.add(c);
        todo.add(c);
      }
    }
    while (todo.isNotEmpty) {
      for (final n in neighbours(todo.removeLast())) {
        if (cells.containsKey(n) && held.add(n)) todo.add(n);
      }
    }
    return {for (final c in cells.keys) if (!held.contains(c)) c};
  }

  /// Puts a [color] bubble in [at] and resolves matches, bombs and falls.
  Outcome land(int at, int color) {
    final out = Outcome();
    cells[at] = Bubble(BubbleKind.color, color);
    final bombs = <int>[for (final n in neighbours(at)) if (cells[n]?.kind == BubbleKind.bomb) n];
    final group = cluster(at, color);
    if (group.length >= 3) {
      for (final c in group) {
        final b = cells[c]!;
        if (b.kind == BubbleKind.ice) {
          cells[c] = Bubble(BubbleKind.color, b.color);
          out.thawed.add(c);
        } else {
          out.popped[c] = cells.remove(c)!;
          for (final n in neighbours(c)) {
            if (cells[n]?.kind == BubbleKind.bomb) bombs.add(n);
          }
        }
      }
    }
    while (bombs.isNotEmpty) {
      final bomb = bombs.removeLast();
      final b = cells.remove(bomb);
      if (b == null) continue;
      out.bombs++;
      out.exploded[bomb] = b;
      for (final n in neighbours(bomb)) {
        final hit = cells[n];
        if (hit == null || hit.fixed) continue;
        if (hit.kind == BubbleKind.bomb) {
          bombs.add(n);
        } else {
          out.exploded[n] = cells.remove(n)!;
        }
      }
    }
    for (final c in floating()) {
      out.fallen[c] = cells.remove(c)!;
    }
    return out;
  }

  /// Removes floating cells (used once after generating a board).
  void prune() {
    for (final c in floating()) {
      cells.remove(c);
    }
  }

  /// Lowest point of the board in its own frame (rotation-proof for hubs).
  double get reach {
    var m = 0.0;
    for (final c in cells.keys) {
      final p = cellPos(c);
      m = max(m, hub ? p.magnitude : p.y);
    }
    return m + bubbleR;
  }
}
