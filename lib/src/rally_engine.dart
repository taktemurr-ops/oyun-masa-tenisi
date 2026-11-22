import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Racket sports seen from above (player at the bottom, rival at the top):
/// table tennis and tennis. The ball has a height (z) with gravity; a shot
/// must clear the net and bounce once on the other side. Hitting is
/// automatic when the ball passes inside your racket's reach, so the skill
/// is positioning: where the ball meets the racket decides the direction.
enum RallyKind { tableTennis, tennis }

class RallyLevel {
  final ArcadeMeta meta;
  final RallyKind kind;
  final int difficulty;
  final int theme;
  const RallyLevel(this.meta, this.kind, this.difficulty, this.theme);
}

RallyLevel generateRally(RallyKind kind, LevelSpec spec) =>
    RallyLevel(ArcadeMeta.of(spec), kind, spec.difficulty.clamp(1, 10), spec.theme % 4);

class RallyGeom {
  final double l, r, t, b, net, netH, g, bounce, reach, speed, power, pSpeed, minY, maxY;
  const RallyGeom(this.l, this.r, this.t, this.b, this.net, this.netH, this.g, this.bounce, this.reach, this.speed,
      this.power, this.pSpeed, this.minY, this.maxY);
  double get cx => (l + r) / 2;
  double get halfW => (r - l) / 2;
  bool inside(double x, double y) => x >= l - 4 && x <= r + 4 && y >= t - 4 && y <= b + 4;
}

const kTT = RallyGeom(250, 750, 300, 1300, 800, 34, 0.2, 0.8, 95, 15, 23, 24, 1230, 1520);
const kTennis = RallyGeom(220, 780, 220, 1380, 800, 46, 0.16, 0.72, 115, 17, 26, 20, 1250, 1560);

class RallySim extends ArcadeSim {
  final RallyLevel level;
  final RallyGeom g;
  // ball
  double bx = 500, by = 1300, bz = 60, vx = 0, vy = 0, vz = 0;
  bool live = false;
  int lastHitter = 0; // 0 player, 1 rival
  int bounces = 0;
  bool netChecked = false;
  // players
  double px = 500, py = 1400, cx = 500, cy = 200;
  double ctx = 500, cty = 200; // rival target
  int power = 0; // armed power-shot ticks
  int server = 0;
  int serveWait = 0;
  int pause = 0; // ticks between points
  // match
  int myPts = 0, cpuPts = 0, myGames = 0, cpuGames = 0;
  int ptsToWin = 11, gamesToWin = 1;
  int rally = 0;
  int pointsWon = 0, matchesWon = 0, aces = 0, bestRally = 0, smashes = 0, pointsLost = 0;
  int lastEvent = 0; // 1 hit, 2 point won, 3 point lost, 4 bounce
  String flash = '';
  int flashTicks = 0;
  int cpuErrCount = 0;
  bool cpuWillMiss = false;

  RallySim(this.level)
      : g = level.kind == RallyKind.tennis ? kTennis : kTT,
        super(level.meta, lives: 3) {
    _setupMatch();
  }

  int get d => level.difficulty;
  bool get tennis => level.kind == RallyKind.tennis;
  bool get matchMode => meta.goal;

  void _setupMatch() {
    myPts = cpuPts = myGames = cpuGames = 0;
    ptsToWin = tennis ? 4 : (d <= 3 ? 5 : (d <= 7 ? 7 : 11));
    gamesToWin = tennis ? (d <= 3 ? 1 : (d <= 7 ? 2 : 3)) : 1;
    server = 0;
    _newPoint();
  }

  void _newPoint() {
    live = false;
    rally = 0;
    bounces = 0;
    netChecked = false;
    pause = 0;
    px = 500;
    py = g.maxY - 60;
    cx = 500;
    cy = (tennis ? 140 : 210);
    ctx = cx;
    cty = cy;
    serveWait = 0;
    _placeServe();
  }

  void _placeServe() {
    if (server == 0) {
      bx = px + 20;
      by = py - 30;
    } else {
      bx = cx + 20;
      by = cy + 30;
    }
    bz = 60;
    vx = vy = vz = 0;
  }

  SeededRandom get _r => SeededRandom(mixSeed([meta.seed, ticks, rally, 31]));

  void _say(String s) {
    flash = s;
    flashTicks = 60;
  }

  /// Launch from (bx,by,bz) to land at (tx,ty) after T ticks, clearing the net.
  void _launch(double tx, double ty, double speed) {
    final dx = tx - bx, dy = ty - by;
    final dist = math.sqrt(dx * dx + dy * dy);
    var t = math.max(12.0, dist / speed);
    for (var k = 0; k < 30; k++) {
      final vz0 = (g.g * t * t / 2 - bz) / t;
      // height at the net
      final tn = ((g.net - by) / (dy / t));
      if (tn > 0 && tn < t) {
        final zn = bz + vz0 * tn - g.g * tn * tn / 2;
        if (zn > g.netH + 14) break;
      } else {
        break;
      }
      t += 2;
    }
    vx = dx / t;
    vy = dy / t;
    vz = (g.g * t * t / 2 - bz) / t;
    live = true;
    bounces = 0;
    netChecked = false;
  }

  void _playerHit({bool serve = false}) {
    final off = clampD((bx - px) / g.reach, -1, 1);
    final tx = g.cx + off * g.halfW * 0.92;
    final pow = power > 0 && !serve;
    final depth = pow ? 0.82 : 0.68;
    final ty = g.net - (g.net - g.t) * depth;
    _launch(tx, ty, pow ? g.power : g.speed);
    if (pow) smashes++;
    power = 0;
    lastHitter = 0;
    rally++;
    lastEvent = 1;
  }

  void _cpuHit({bool serve = false}) {
    final r = _r;
    // aim away from the player, better rivals aim closer to the lines
    final away = px < g.cx ? 1.0 : -1.0;
    final aimAway = r.chance(0.35 + d * 0.05);
    var tx = g.cx + (aimAway ? away : (r.nextDouble() * 2 - 1)) * g.halfW * (0.35 + r.nextDouble() * (0.3 + d * 0.025));
    var ty = g.net + (g.b - g.net) * (0.45 + r.nextDouble() * 0.4);
    // unforced errors
    final err = serve ? 0.03 : (0.2 - d * 0.014);
    if (r.chance(err)) {
      cpuErrCount++;
      if (r.chance(0.5)) {
        tx = g.cx + (r.chance(0.5) ? 1 : -1) * (g.halfW + 40 + r.nextDouble() * 60);
      } else {
        ty = g.b + 60 + r.nextDouble() * 80;
      }
    }
    final sp = g.speed * (0.85 + d * 0.035) * (r.chance(0.15 + d * 0.02) ? 1.25 : 1);
    _launch(tx, ty, sp);
    lastHitter = 1;
    rally++;
    lastEvent = 1;
  }

  void _point(bool mine) {
    live = false;
    bestRally = math.max(bestRally, rally);
    if (mine) {
      pointsWon++;
      score += 100 + rally * 10;
      if (rally <= 1 && lastHitter == 0) aces++;
      lastEvent = 2;
    } else {
      pointsLost++;
      lastEvent = 3;
    }
    pause = 50;
    if (!matchMode) {
      _say(mine ? 'POINT!' : 'OUT');
      if (!mine) {
        if (meta.zen) return;
        shield = 0;
        hit();
      }
      server = 1 - server;
      return;
    }
    if (mine) {
      myPts++;
    } else {
      cpuPts++;
    }
    _say(mine ? 'POINT!' : 'POINT ×');
    // game won?
    final cap = ptsToWin + (tennis ? 3 : 4);
    bool gameWon(int a, int b) => a >= ptsToWin && (a - b >= 2 || a >= cap);
    if (gameWon(myPts, cpuPts) || gameWon(cpuPts, myPts)) {
      final me = myPts > cpuPts;
      if (me) {
        myGames++;
      } else {
        cpuGames++;
      }
      myPts = 0;
      cpuPts = 0;
      _say(me ? 'GAME!' : 'GAME ×');
      if (myGames >= gamesToWin) {
        matchesWon++;
        score += 500;
        win();
        return;
      }
      if (cpuGames >= gamesToWin) {
        if (meta.zen) {
          _setupMatch();
          return;
        }
        shield = 0;
        hit();
        return;
      }
      server = 1 - server;
    } else if (!tennis && (myPts + cpuPts) % 2 == 0) {
      server = 1 - server;
    }
  }

  @override
  void onLifeLost() {
    if (matchMode) {
      _setupMatch();
    } else {
      _newPoint();
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flashTicks > 0) flashTicks--;
    if (power > 0) power--;
    if (input.swipe == 0) power = 24;
    _movePlayer(input);
    if (pause > 0) {
      pause--;
      if (pause == 0) _newPoint();
      return;
    }
    if (!live) {
      _serve(input);
      _moveCpu();
      return;
    }
    _moveCpu();
    _stepBall();
  }

  void _serve(ArcadeInput input) {
    serveWait++;
    _placeServe();
    if (server == 0) {
      if ((input.tap || input.swipe == 0 || serveWait > 180) && serveWait > 20) {
        bz = 70;
        _playerHit(serve: true);
      }
    } else if (serveWait > 50) {
      bz = 70;
      _cpuHit(serve: true);
    }
  }

  void _movePlayer(ArcadeInput i) {
    var tx = px, ty = py;
    if (i.down && i.hasPointer) {
      tx = i.x;
      ty = i.y - 40; // racket slightly above the finger so it stays visible
    }
    if (i.dirX != 0) tx = px + i.dirX * 40;
    if (i.dirY != 0) ty = py + i.dirY * 40;
    tx = clampD(tx, g.l - 150, g.r + 150);
    ty = clampD(ty, g.minY, g.maxY);
    px = moveToward(px, tx, g.pSpeed);
    py = moveToward(py, ty, g.pSpeed * 0.7);
  }

  /// Predicted (x, y) where the ball can be hit on the side `side`
  /// (0 bottom / player, 1 top / rival).
  (double, double)? predictHit(int side, double minY, double maxY) {
    var x = bx, y = by, z = bz, ux = vx, uy = vy, uz = vz;
    var b = bounces;
    for (var k = 0; k < 240; k++) {
      x += ux;
      y += uy;
      z += uz;
      uz -= g.g;
      if (z <= 0) {
        z = 0;
        uz = -uz * g.bounce;
        b++;
        if (b >= 2) return null;
      }
      if (b == 1 && z < 110 && y >= minY && y <= maxY && uz < 2) return (x, y);
      if (b == 1 && (side == 0 ? y > maxY : y < minY)) return (x, side == 0 ? maxY : minY);
    }
    return null;
  }

  void _moveCpu() {
    final sp = (tennis ? 6.5 : 6.0) + d * 0.5;
    // the rival reads the shot once it has crossed the net (weaker rivals later)
    final react = g.net - (10 - d) * 22;
    if (live && lastHitter == 0 && by < react) {
      final p = predictHit(1, tennis ? 60 : 120, tennis ? 300 : 280);
      if (p != null) {
        ctx = p.$1;
        cty = p.$2;
      }
    } else if (!live || lastHitter == 1 || by > g.net) {
      ctx = g.cx + (bx - g.cx) * 0.3;
      cty = tennis ? 150 : 210;
    }
    cx = moveToward(cx, ctx, sp);
    cy = moveToward(cy, cty, sp * 0.7);
  }

  void _stepBall() {
    final py0 = by;
    bx += vx;
    by += vy;
    bz += vz;
    vz -= g.g;
    // net
    if (!netChecked && (py0 - g.net) * (by - g.net) <= 0) {
      netChecked = true;
      if (bz < g.netH) {
        _say('NET');
        _point(lastHitter == 1);
        return;
      }
    }
    if (bz <= 0) {
      bz = 0;
      vz = -vz * g.bounce;
      lastEvent = 4;
      final side = by > g.net ? 0 : 1;
      if (bounces == 0) {
        if (side == lastHitter || !g.inside(bx, by)) {
          _say('OUT');
          _point(lastHitter == 1);
          return;
        }
        bounces = 1;
      } else {
        _point(lastHitter == 0);
        return;
      }
    }
    // hits
    if (bounces == 1 && bz < 130) {
      if (lastHitter == 1 && by > g.net) {
        if ((bx - px).abs() < g.reach && (by - py).abs() < 55) _playerHit();
      } else if (lastHitter == 0 && by < g.net) {
        if ((bx - cx).abs() < g.reach * 0.85 && (by - cy).abs() < 55) _cpuHit();
      }
    }
    if (by > kWorldH + 100 || by < -100 || bx < -200 || bx > kWorldW + 200) {
      _point(lastHitter == 0 ? bounces >= 1 : bounces < 1);
    }
  }

  @override
  bool useBooster() {
    // Super shot: the next return is a power shot.
    if (over) return false;
    power = 600;
    return true;
  }

  @override
  double get progress {
    if (!matchMode) return 0;
    final per = 1 / gamesToWin;
    return (myGames * per + per * (myPts / ptsToWin).clamp(0.0, 0.95)).clamp(0.0, 1.0);
  }

  static const _tennisPts = ['0', '15', '30', '40'];

  String _pts(int a, int b) {
    if (!tennis) return '$a-$b';
    if (a >= 3 && b >= 3) {
      if (a == b) return 'DEUCE';
      return a > b ? 'AD-IN' : 'AD-OUT';
    }
    return '${_tennisPts[a.clamp(0, 3)]}-${_tennisPts[b.clamp(0, 3)]}';
  }

  @override
  String get goalText => matchMode
      ? (gamesToWin > 1 ? '$myGames-$cpuGames • ${_pts(myPts, cpuPts)}' : _pts(myPts, cpuPts))
      : '$pointsWon';

  @override
  Map<String, int> get stats => {
        'points_won': pointsWon,
        'matches_won': matchesWon,
        'aces': aces,
        'best_rally': bestRally,
        'power_shots': smashes,
      };

  @override
  int get stars {
    if (!won) return 0;
    final lost = cpuGames;
    final q = lost == 0 ? (pointsLost <= ptsToWin ~/ 2 ? 3 : 2) : 1;
    return math.min(lifeStars(this, 3), q);
  }
}

/// Autopilot: moves to the predicted hit point and angles the racket away
/// from the rival.
ArcadeInput rallyBot(ArcadeSim sim) {
  final s = sim as RallySim;
  final g = s.g;
  if (!s.live) {
    if (s.server == 0 && s.pause == 0 && s.serveWait > 25) return ArcadeInput(down: true, x: s.px.roundToDouble(), y: (s.py + 40).roundToDouble(), tap: true);
    return ArcadeInput(down: true, x: 500, y: (g.maxY - 20).roundToDouble());
  }
  if (s.lastHitter == 1) {
    final p = s.predictHit(0, g.minY + 20, g.maxY - 10);
    if (p != null) {
      // where on the racket: aim to the side away from the rival
      final away = s.cx > g.cx ? -1.0 : 1.0;
      final off = away * 0.55;
      final tx = p.$1 - off * g.reach;
      final near = (s.by - p.$2).abs() < 200 && s.by > g.net;
      return ArcadeInput(
          down: true,
          x: clampD(tx, 0, kWorldW).roundToDouble(),
          y: clampD(p.$2 + 40, 0, kWorldH).roundToDouble(),
          swipe: near && s.power == 0 ? 0 : -1);
    }
  }
  return ArcadeInput(down: true, x: g.cx.roundToDouble(), y: (g.maxY - 40).roundToDouble());
}
