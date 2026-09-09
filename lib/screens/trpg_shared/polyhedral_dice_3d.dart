import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A software-rendered polyhedral die. It uses real 3D vertices/faces,
/// perspective projection, depth sorting and per-face lighting; no bitmap or
/// WebView is involved.
class PolyhedralDice3D extends StatelessWidget {
  const PolyhedralDice3D({
    required this.sides,
    required this.value,
    required this.rotationTurns,
    required this.color,
    this.size = 150,
    this.settled = false,
    this.percentileTens = false,
    this.percentileDigit = false,
    super.key,
  });

  final int sides;
  final int value;
  final double rotationTurns;
  final Color color;
  final double size;
  final bool settled;
  final bool percentileTens;
  final bool percentileDigit;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: settled ? 1 : 0),
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    builder: (context, settleAmount, _) => SizedBox.square(
      dimension: size,
      child: CustomPaint(
        key: ValueKey('dice-3d-d$sides-$value'),
        painter: PolyhedralDicePainter(
          sides: sides,
          value: value,
          rotationTurns: rotationTurns,
          color: color,
          settled: settled,
          settleAmount: settleAmount,
          percentileTens: percentileTens,
          percentileDigit: percentileDigit,
        ),
      ),
    ),
  );
}

class Dice3DStage extends StatelessWidget {
  const Dice3DStage({
    required this.sides,
    required this.values,
    required this.rotationTurns,
    required this.color,
    required this.settled,
    this.reducedMotion = false,
    super.key,
  });

  final int sides;
  final List<int> values;
  final double rotationTurns;
  final Color color;
  final bool settled;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final visible = values.isEmpty ? const [1] : values.take(4).toList();
    final percentile = sides == 100;
    final diceCount = percentile ? 2 : visible.length;
    final size = switch (diceCount) {
      1 => 158.0,
      2 => 108.0,
      _ => 88.0,
    };
    final natural = visible.first;
    final dice = percentile
        ? <Widget>[
            PolyhedralDice3D(
              sides: 10,
              value: natural == 100 ? 0 : (natural ~/ 10) * 10,
              rotationTurns: rotationTurns,
              color: color,
              size: 108,
              settled: settled,
              percentileTens: true,
            ),
            PolyhedralDice3D(
              sides: 10,
              value: natural == 100 ? 0 : natural % 10,
              rotationTurns: rotationTurns + .13,
              color: Color.lerp(color, Colors.white, .2)!,
              size: 108,
              settled: settled,
              percentileDigit: true,
            ),
          ]
        : <Widget>[
            for (var index = 0; index < visible.length; index++)
              PolyhedralDice3D(
                sides: sides,
                value: visible[index],
                rotationTurns: rotationTurns + index * .11,
                color: Color.lerp(color, Colors.white, index * .07)!,
                size: size,
                settled: settled,
              ),
          ];
    return Semantics(
      label: percentile
          ? '旋转的百分骰，当前点数 $natural'
          : '旋转的 $sides 面骰，当前点数 ${visible.join('、')}',
      image: true,
      child: SizedBox(
        key: const ValueKey('polyhedral-dice-3d-stage'),
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              width: settled ? 205 : 170,
              height: settled ? 38 : 26,
              margin: const EdgeInsets.only(top: 135),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: Colors.black.withValues(alpha: settled ? .3 : .18),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: settled ? .24 : .12),
                    blurRadius: settled ? 28 : 16,
                    spreadRadius: settled ? 5 : 1,
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: Offset(
                0,
                settled || reducedMotion
                    ? 0
                    : -10 - math.sin(rotationTurns * math.pi * 2).abs() * 18,
              ),
              child: AnimatedScale(
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                curve: settled ? Curves.easeOutBack : Curves.easeOut,
                scale: settled ? 1 : .94,
                child: percentile
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            dice[0],
                            const SizedBox(width: 4),
                            dice[1],
                          ],
                        ),
                      )
                    : Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: -4,
                        runSpacing: -12,
                        children: dice,
                      ),
              ),
            ),
            if (percentile && natural == 100 && settled)
              Positioned(
                bottom: 4,
                child: Text(
                  '00 + 0 = 100',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (values.length > 4)
              Positioned(
                right: 18,
                bottom: 6,
                child: Text(
                  '+${values.length - 4} 枚',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PolyhedralDicePainter extends CustomPainter {
  const PolyhedralDicePainter({
    required this.sides,
    required this.value,
    required this.rotationTurns,
    required this.color,
    required this.settled,
    this.settleAmount = 0,
    required this.percentileTens,
    this.percentileDigit = false,
  });

  final int sides;
  final int value;
  final double rotationTurns;
  final Color color;
  final bool settled;
  final double settleAmount;
  final bool percentileTens;
  final bool percentileDigit;

  static int faceCountForSides(int sides) => _meshForSides(sides).faces.length;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final mesh = _meshForSides(sides);
    final t = rotationTurns * math.pi * 2;
    final target = _settledAngles(sides);
    final ax = _blendAngle(t * .73 + .42, target.$1, settleAmount);
    final ay = _blendAngle(t * 1.07 + .58, target.$2, settleAmount);
    final az = _blendAngle(t * .31, target.$3, settleAmount);
    final rotated = <_V3>[
      for (final vertex in mesh.vertices) _rotate(vertex, ax, ay, az),
    ];
    final shapeScale = switch (sides) {
      6 => .82,
      12 || 20 => 1.06,
      _ => 1.0,
    };
    final radius = size.shortestSide * .39 * shapeScale;
    final center = size.center(Offset.zero) + const Offset(0, -1);
    final projected = <Offset>[
      for (final vertex in rotated) _project(vertex, center, radius),
    ];
    final faces = <_PaintFace>[];
    for (var index = 0; index < mesh.faces.length; index++) {
      final vertices = mesh.faces[index];
      var normal = _faceNormal(
        rotated[vertices[0]],
        rotated[vertices[1]],
        rotated[vertices[2]],
      );
      final centroid = _centroid(rotated, vertices);
      if (normal.dot(centroid) < 0) normal = -normal;
      if (normal.normalized.z < -.02) continue;
      faces.add(
        _PaintFace(
          index,
          vertices,
          vertices.map((vertex) => rotated[vertex].z).reduce((a, b) => a + b) /
              vertices.length,
          normal.normalized,
        ),
      );
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final front = faces.last.index;
    final labeledFaces = faces.reversed
        .take(3)
        .map((face) => face.index)
        .toSet();

    final shadowPath = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(center.dx + 4, size.height * .86),
          width: size.width * .62,
          height: size.height * .15,
        ),
      );
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: .3)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7),
    );

    for (final face in faces) {
      final points = [for (final vertex in face.vertices) projected[vertex]];
      final path = _roundedPolygon(points, size.shortestSide * .025);
      final normal = face.normal;
      final light = (.46 + normal.dot(const _V3(-.35, -.6, .72)) * .3).clamp(
        .16,
        .78,
      );
      final isFront = face.index == front;
      final faceColor = Color.lerp(
        Color.lerp(color, Colors.black, .44)!,
        Color.lerp(color, Colors.white, .15)!,
        light,
      )!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(faceColor, Colors.white, isFront ? .2 : .06)!,
              Color.lerp(faceColor, Colors.black, .22)!,
            ],
          ).createShader(path.getBounds()),
      );
      final centroid =
          points.reduce((a, b) => a + b) / points.length.toDouble();
      final inset = [
        for (final point in points) Offset.lerp(point, centroid, .08)!,
      ];
      canvas.drawPath(
        _roundedPolygon(inset, size.shortestSide * .018),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.7, size.shortestSide * .006)
          ..color = Colors.white.withValues(alpha: isFront ? .22 : .1),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = math.max(1, size.shortestSide * .012)
          ..color = Color.lerp(
            color,
            Colors.white,
            .58,
          )!.withValues(alpha: isFront ? .95 : .58),
      );
      if (labeledFaces.contains(face.index) &&
          _polygonArea(points) > size.width * 3.5) {
        final display = _faceLabel(face.index, isFront);
        _paintNumber(canvas, points, display, isFront, size.shortestSide);
      }
    }

    if (settled) {
      canvas.drawCircle(
        center,
        size.shortestSide * .43,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: .34)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
      );
    }
  }

  void _paintNumber(
    Canvas canvas,
    List<Offset> points,
    String label,
    bool front,
    double extent,
  ) {
    final center = points.reduce((a, b) => a + b) / points.length.toDouble();
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: front ? 1 : .84),
          fontSize: extent * (front ? .17 : .105),
          fontWeight: front ? FontWeight.w900 : FontWeight.w700,
          fontFamily: 'Microsoft YaHei',
          fontFamilyFallback: const ['Roboto', 'sans-serif'],
          shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static _V3 _rotate(_V3 p, double ax, double ay, double az) {
    final x1 = p.x;
    final y1 = p.y * math.cos(ax) - p.z * math.sin(ax);
    final z1 = p.y * math.sin(ax) + p.z * math.cos(ax);
    final x2 = x1 * math.cos(ay) + z1 * math.sin(ay);
    final z2 = -x1 * math.sin(ay) + z1 * math.cos(ay);
    return _V3(
      x2 * math.cos(az) - y1 * math.sin(az),
      x2 * math.sin(az) + y1 * math.cos(az),
      z2,
    );
  }

  static Offset _project(_V3 p, Offset center, double radius) {
    final perspective = 3.7 / (4.2 - p.z);
    return center + Offset(p.x, p.y) * radius * perspective;
  }

  static _V3 _faceNormal(_V3 a, _V3 b, _V3 c) => (b - a).cross(c - a);

  static double _polygonArea(List<Offset> points) {
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  @override
  bool shouldRepaint(covariant PolyhedralDicePainter old) =>
      sides != old.sides ||
      value != old.value ||
      rotationTurns != old.rotationTurns ||
      color != old.color ||
      settled != old.settled ||
      settleAmount != old.settleAmount ||
      percentileTens != old.percentileTens ||
      percentileDigit != old.percentileDigit;

  static (double, double, double) _settledAngles(int sides) => switch (sides) {
    4 => (-.48, .62, -.08),
    6 => (-.58, .68, .08),
    8 => (1.05, .18, .08),
    10 => (1.12, .22, .04),
    12 => (-.4, .48, .02),
    _ => (-.38, .46, .02),
  };

  String _faceLabel(int faceIndex, bool front) {
    if (front) return percentileTens && value == 0 ? '00' : '$value';
    var candidate = percentileTens
        ? ((faceIndex + 1) % 10) * 10
        : percentileDigit
        ? (faceIndex + 1) % 10
        : (faceIndex % sides) + 1;
    if (candidate == value ||
        (percentileTens && candidate == 0 && value == 0)) {
      candidate = percentileTens
          ? (candidate + 10) % 100
          : percentileDigit
          ? (candidate + 1) % 10
          : candidate % sides + 1;
    }
    return percentileTens && candidate == 0 ? '00' : '$candidate';
  }

  static double _blendAngle(double current, double target, double amount) {
    final wrapped = math.atan2(math.sin(current), math.cos(current));
    final delta = math.atan2(
      math.sin(target - wrapped),
      math.cos(target - wrapped),
    );
    return wrapped + delta * amount;
  }

  static _V3 _centroid(List<_V3> vertices, List<int> indices) => _V3(
    indices.map((i) => vertices[i].x).reduce((a, b) => a + b) / indices.length,
    indices.map((i) => vertices[i].y).reduce((a, b) => a + b) / indices.length,
    indices.map((i) => vertices[i].z).reduce((a, b) => a + b) / indices.length,
  );

  static Path _roundedPolygon(List<Offset> points, double radius) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final previous = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final before = Offset.lerp(
        current,
        previous,
        math.min(.16, radius / (current - previous).distance),
      )!;
      final after = Offset.lerp(
        current,
        next,
        math.min(.16, radius / (current - next).distance),
      )!;
      if (i == 0) {
        path.moveTo(before.dx, before.dy);
      } else {
        path.lineTo(before.dx, before.dy);
      }
      path.quadraticBezierTo(current.dx, current.dy, after.dx, after.dy);
    }
    return path..close();
  }
}

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;
  _V3 operator -(_V3 other) => _V3(x - other.x, y - other.y, z - other.z);
  _V3 operator -() => _V3(-x, -y, -z);
  double dot(_V3 other) => x * other.x + y * other.y + z * other.z;
  _V3 cross(_V3 other) => _V3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );
  double get length => math.sqrt(x * x + y * y + z * z);
  _V3 get normalized {
    final magnitude = length;
    return magnitude == 0
        ? const _V3(0, 0, 0)
        : _V3(x / magnitude, y / magnitude, z / magnitude);
  }
}

class _Mesh {
  const _Mesh(this.vertices, this.faces);
  final List<_V3> vertices;
  final List<List<int>> faces;
}

class _PaintFace {
  const _PaintFace(this.index, this.vertices, this.depth, this.normal);
  final int index;
  final List<int> vertices;
  final double depth;
  final _V3 normal;
}

_Mesh _meshForSides(int sides) => switch (sides) {
  4 => _tetrahedron,
  6 => _cube,
  8 => _bipyramid(4),
  10 => _bipyramid(5),
  12 => _dodecahedron,
  20 => _icosahedron,
  _ => _icosahedron,
};

const _tetrahedron = _Mesh(
  [_V3(1, 1, 1), _V3(-1, -1, 1), _V3(-1, 1, -1), _V3(1, -1, -1)],
  [
    [0, 1, 2],
    [0, 3, 1],
    [0, 2, 3],
    [1, 3, 2],
  ],
);

const _cube = _Mesh(
  [
    _V3(-1, -1, -1),
    _V3(1, -1, -1),
    _V3(1, 1, -1),
    _V3(-1, 1, -1),
    _V3(-1, -1, 1),
    _V3(1, -1, 1),
    _V3(1, 1, 1),
    _V3(-1, 1, 1),
  ],
  [
    [0, 3, 2, 1],
    [4, 5, 6, 7],
    [0, 1, 5, 4],
    [3, 7, 6, 2],
    [0, 4, 7, 3],
    [1, 2, 6, 5],
  ],
);

_Mesh _bipyramid(int ring) {
  final vertices = <_V3>[const _V3(0, 0, 1.35), const _V3(0, 0, -1.35)];
  for (var i = 0; i < ring; i++) {
    final angle = i * math.pi * 2 / ring;
    vertices.add(_V3(math.cos(angle), math.sin(angle), 0));
  }
  return _Mesh(vertices, [
    for (var i = 0; i < ring; i++) [0, 2 + i, 2 + (i + 1) % ring],
    for (var i = 0; i < ring; i++) [1, 2 + (i + 1) % ring, 2 + i],
  ]);
}

final _icosahedron = _convexMesh(() {
  final phi = (1 + math.sqrt(5)) / 2;
  return <_V3>[
    for (final a in [-1.0, 1.0])
      for (final b in [-phi, phi]) _V3(0, a, b),
    for (final a in [-1.0, 1.0])
      for (final b in [-phi, phi]) _V3(a, b, 0),
    for (final a in [-phi, phi])
      for (final b in [-1.0, 1.0]) _V3(a, 0, b),
  ];
}());

final _dodecahedron = _convexMesh(() {
  final phi = (1 + math.sqrt(5)) / 2;
  final inv = 1 / phi;
  return <_V3>[
    for (final x in [-1.0, 1.0])
      for (final y in [-1.0, 1.0])
        for (final z in [-1.0, 1.0]) _V3(x, y, z),
    for (final y in [-inv, inv])
      for (final z in [-phi, phi]) _V3(0, y, z),
    for (final x in [-inv, inv])
      for (final y in [-phi, phi]) _V3(x, y, 0),
    for (final x in [-phi, phi])
      for (final z in [-inv, inv]) _V3(x, 0, z),
  ];
}());

_Mesh _convexMesh(List<_V3> vertices) {
  final faces = <String, List<int>>{};
  const epsilon = .0001;
  for (var i = 0; i < vertices.length - 2; i++) {
    for (var j = i + 1; j < vertices.length - 1; j++) {
      for (var k = j + 1; k < vertices.length; k++) {
        final normal = (vertices[j] - vertices[i]).cross(
          vertices[k] - vertices[i],
        );
        if (normal.length < epsilon) continue;
        var positive = false, negative = false;
        for (final vertex in vertices) {
          final distance = normal.dot(vertex - vertices[i]);
          positive |= distance > epsilon;
          negative |= distance < -epsilon;
        }
        if (positive && negative) continue;
        final plane = <int>[];
        for (var p = 0; p < vertices.length; p++) {
          if (normal.dot(vertices[p] - vertices[i]).abs() <= epsilon) {
            plane.add(p);
          }
        }
        if (plane.length < 3) continue;
        plane.sort();
        final key = plane.join(',');
        if (faces.containsKey(key)) continue;
        final centroid = _V3(
          plane.map((p) => vertices[p].x).reduce((a, b) => a + b) /
              plane.length,
          plane.map((p) => vertices[p].y).reduce((a, b) => a + b) /
              plane.length,
          plane.map((p) => vertices[p].z).reduce((a, b) => a + b) /
              plane.length,
        );
        final outward = centroid.normalized;
        final axis = outward.x.abs() < .8
            ? const _V3(1, 0, 0)
            : const _V3(0, 1, 0);
        final u = outward.cross(axis).normalized;
        final v = outward.cross(u).normalized;
        plane.sort((a, b) {
          final pa = vertices[a] - centroid, pb = vertices[b] - centroid;
          return math
              .atan2(pa.dot(v), pa.dot(u))
              .compareTo(math.atan2(pb.dot(v), pb.dot(u)));
        });
        faces[key] = plane;
      }
    }
  }
  final scale = vertices.map((v) => v.length).reduce(math.max);
  return _Mesh([
    for (final v in vertices) _V3(v.x / scale, v.y / scale, v.z / scale),
  ], faces.values.toList());
}
