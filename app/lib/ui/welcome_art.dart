/// Los dibujos de la pantalla de bienvenida, y el fondo sobre el que van.
///
/// Dibujados y no fotos ni capturas, por tres razones. Una captura de la
/// aplicación envejece con la aplicación y hay que rehacerla cada vez que se
/// mueve un botón. Una ilustración de archivo decora y no explica. Y un
/// fichero de imagen habría que empaquetarlo, escalarlo para cada pantalla y
/// volver a dibujarlo el día que cambie el color de la marca.
///
/// Lo que se dibuja es el **mecanismo**, que es lo que el texto de al lado
/// está contando: una lección que entra en varios cursos, un fichero del que
/// salen muchos PDF, un historial con nombres y el recorrido por la ventana.
/// Si el dibujo no dijera nada que no diga el título, sobraría.
///
/// **Y se mueven**, porque el mecanismo es un movimiento: la lección *viaja*
/// a los cursos sin copiarse, las salidas *salen* del fichero. Quieto, el
/// dibujo del reúso era tres cajas unidas por rayas, y eso lo mismo podía ser
/// un organigrama. Con el sistema pidiendo menos movimiento se quedan en el
/// fotograma en que todo ha llegado, que es el que cuenta la historia entera.
library;

import 'dart:async';

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'theme.dart';
import '../l10n/tr.dart';

/// Con qué tipografía se pinta el texto de los dibujos.
///
/// Nula en la aplicación: los pinta un `CustomPainter`, que no hereda el
/// estilo de texto de nadie, y sin familia el sistema pone la suya -- que es
/// lo que se quiere.
///
/// Se rellena en un solo sitio: la herramienta que genera las capturas de la
/// documentación, que corre dentro del arnés de tests. Allí no hay ninguna
/// tipografía por defecto, así que este texto saldría como rectángulos negros
/// en mitad de la primera pantalla que ve alguien.
String? welcomeArtFontFamily;

/// Un dibujo en un instante: [t] va de 0 a 1 y vuelve a empezar. Con la
/// paleta del tema, que un pintor no tiene de dónde leer.
typedef ArtBuilder = CustomPainter Function(double t, DidactaPalette palette);

/// El lienzo de un dibujo, animado.
///
/// [rest] es el instante que se enseña quieto --sin animaciones, o en una
/// captura-- y tiene que ser uno en el que todo esté ya en su sitio.
class WelcomeArt extends StatefulWidget {
  const WelcomeArt({
    super.key,
    required this.builder,
    this.height = 190,
    this.period = const Duration(seconds: 6),
    this.rest = 0.8,
    this.framed = true,
  });

  final ArtBuilder builder;
  final double height;
  final Duration period;
  final double rest;

  /// Con el fondo y el borde de una tarjeta, o suelto.
  final bool framed;

  @override
  State<WelcomeArt> createState() => _WelcomeArtState();
}

class _WelcomeArtState extends State<WelcomeArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      unawaited(_clock.repeat());
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final art = AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => CustomPaint(
        painter: widget.builder(
          still ? widget.rest : _clock.value,
          context.palette,
        ),
        size: Size.infinite,
      ),
    );
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: widget.framed
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.palette.tint(context.palette.accent, 0.02),
                    context.palette.tint(context.palette.accent, 0.06),
                  ],
                ),
                border: Border.all(color: context.palette.rule),
                borderRadius: BorderRadius.circular(Radii.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.card),
                child: art,
              ),
            )
          : art,
    );
  }
}

// ------------------------------------------------------------ el tiempo ---

/// Cuánto ha avanzado un tramo que va de [start] a [end], de 0 a 1.
double _phase(double t, double start, double end) =>
    ((t - start) / (end - start)).clamp(0.0, 1.0);

/// El final de cada vuelta: todo se desvanece a la vez y vuelve a empezar.
double _fadeOut(double t, {double from = 0.9}) =>
    1 - Curves.easeIn.transform(_phase(t, from, 1));

// --------------------------------------------------------- las piezas ---

/// Lo compartido: un lienzo virtual de 440×170 que se escala al que haya, y
/// cómo se pinta una caja, unas rayas, una etiqueta y una flecha.
///
/// El lienzo fijo es lo que permite dibujar con números que se leen --«la
/// lección a la izquierda, a 24 del borde»-- y que el dibujo quede igual de
/// proporcionado en una ventana ancha y en una estrecha.
abstract class _ArtPainter extends CustomPainter {
  const _ArtPainter(this.t, this.palette);

  final double t;

  /// Los colores con que se pinta: los del tema de quien lo pone.
  final DidactaPalette palette;

  /// El gris de las rayas que dicen «aquí hay texto».
  Color get _lineGrey => palette.sketch;

  static const Size canvasSize = Size(440, 170);

  void draw(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / canvasSize.width,
      size.height / canvasSize.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - canvasSize.width * scale) / 2,
      (size.height - canvasSize.height * scale) / 2,
    );
    canvas.scale(scale);
    draw(canvas);
    canvas.restore();
  }

  void box(
    Canvas canvas,
    Rect rect, {
    Color? accent,
    double radius = 6,
    double opacity = 1,
    bool shadow = true,
  }) {
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    if (shadow && opacity > 0) {
      canvas.drawRRect(
        rounded.shift(const Offset(0, 2)),
        Paint()
          ..color = palette.shadow.withValues(alpha: 0.06 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawRRect(
      rounded,
      Paint()..color = palette.card.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = (accent ?? palette.rule).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = accent == null ? 1 : 1.6,
    );
  }

  /// Unas rayas dentro de una caja, que es cómo se lee «esto tiene texto».
  void lines(
    Canvas canvas,
    Rect rect,
    int count, {
    Color? colour,
    double opacity = 1,
    double stroke = 2,
  }) {
    final paint = Paint()
      ..color = (colour ?? _lineGrey).withValues(alpha: opacity)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final step = rect.height / (count + 1);
    for (var i = 1; i <= count; i += 1) {
      final y = rect.top + step * i;
      final width = i.isOdd ? rect.width * 0.82 : rect.width * 0.58;
      canvas.drawLine(
        Offset(rect.left + 2, y),
        Offset(rect.left + 2 + width, y),
        paint,
      );
    }
  }

  void label(
    Canvas canvas,
    Offset at,
    String text, {
    Color? colour,
    double size = 9,
    FontWeight weight = FontWeight.w600,
    double opacity = 1,
    bool centred = true,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          height: 1,
          color: (colour ?? palette.muted).withValues(alpha: opacity),
          fontWeight: weight,
          fontFamily: welcomeArtFontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, centred ? at - Offset(painter.width / 2, 0) : at);
  }

  /// La curva de una caja a otra. Curva y no recta: tres rectas saliendo del
  /// mismo punto se pisan y parecen una mancha.
  Path curve(Offset from, Offset to) {
    final middle = from.dx + (to.dx - from.dx) * 0.5;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(middle, from.dy, middle, to.dy, to.dx, to.dy);
  }

  /// La curva entera en gris, y la parte recorrida --[progress]-- en color.
  void trail(
    Canvas canvas,
    Path path,
    double progress, {
    Color? colour,
    double opacity = 1,
  }) {
    final tint = colour ?? palette.accent;
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.rule.withValues(alpha: opacity)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
    if (progress <= 0) return;
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = tint.withValues(alpha: opacity)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  /// Dónde está, a [progress] del camino, lo que viaja por [path].
  Offset along(Path path, double progress) {
    final PathMetric metric = path.computeMetrics().first;
    return metric
            .getTangentForOffset(metric.length * progress.clamp(0, 1))
            ?.position ??
        Offset.zero;
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) =>
      old.t != t || !identical(old.palette, palette);
}

// ------------------------------------------------------------ los dibujos ---

/// Una lección que entra en varios cursos.
///
/// El dibujo del reúso: la pieza de la izquierda es **una**, y la verde que
/// llega a cada curso es la misma, no una copia. Viaja y la de la izquierda
/// no se gasta: es lo que distingue esto de duplicar un fichero en tres
/// carpetas.
class ReusePainter extends _ArtPainter {
  const ReusePainter(super.t, super.palette);

  static List<String> get _courses => [
    'Cálculo I',
    tr('Análisis I'),
    tr('Métodos numéricos'),
  ];

  @override
  void draw(Canvas canvas) {
    final fade = _fadeOut(t);

    // La lección: una hoja con su cabecera verde.
    final unit = const Rect.fromLTWH(44, 42, 110, 82);
    box(canvas, unit, accent: palette.accentDark, radius: 8);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(unit.left, unit.top, unit.width, 20),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      ),
      Paint()..color = palette.accent.withValues(alpha: 0.22),
    );
    label(
      canvas,
      Offset(unit.left + 10, unit.top + 6),
      tr('Definición'),
      colour: palette.accentDark,
      size: 8.5,
      centred: false,
    );
    lines(
      canvas,
      Rect.fromLTWH(unit.left + 10, unit.top + 22, unit.width - 22, 56),
      4,
    );
    label(
      canvas,
      Offset(unit.center.dx, unit.bottom + 9),
      tr('una lección'),
      colour: palette.accentDark,
    );

    for (var i = 0; i < _courses.length; i += 1) {
      final course = Rect.fromLTWH(270, 20 + i * 48.0, 142, 34);
      box(canvas, course, radius: 7);
      final slot = Rect.fromLTWH(course.left + 9, course.top + 10, 16, 14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(slot, const Radius.circular(3)),
        Paint()
          ..color = palette.rule
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      label(
        canvas,
        Offset(course.left + 33, course.top + 8),
        _courses[i],
        colour: palette.ink,
        size: 9.5,
        weight: FontWeight.w600,
        centred: false,
      );
      lines(
        canvas,
        Rect.fromLTWH(course.left + 33, course.top + 16, 70, 14),
        1,
        stroke: 1.6,
      );

      final path = curve(
        Offset(unit.right, unit.center.dy),
        Offset(slot.left - 2, slot.center.dy),
      );
      // Cada curso, un poco después que el anterior.
      final start = 0.06 + i * 0.16;
      final travel = Curves.easeInOutCubic.transform(
        _phase(t, start, start + 0.3),
      );
      trail(canvas, path, travel, opacity: fade);

      if (travel > 0 && travel < 1) {
        final at = along(path, travel);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at, width: 14, height: 11),
            const Radius.circular(3),
          ),
          Paint()..color = palette.accent,
        );
      }
      if (travel >= 1) {
        // Llegada: el hueco se rellena con la misma pieza verde.
        final settle = Curves.easeOutBack.transform(
          _phase(t, start + 0.3, start + 0.38),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: slot.center,
              width: slot.width * settle,
              height: slot.height * settle,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = palette.accent.withValues(alpha: fade),
        );
      }
    }
  }
}

/// Un fichero del que salen muchos PDF.
///
/// Las salidas con proporciones distintas --las diapositivas apaisadas, el
/// libro estrecho-- porque es lo que las hace reconocibles de un vistazo sin
/// tener que leer la etiqueta. Y los idiomas debajo del fichero, encendiéndose
/// por turnos: el mismo fichero sale en cada uno.
class OutputsPainter extends _ArtPainter {
  const OutputsPainter(super.t, super.palette);

  static List<(String, double, double, bool)> get _outputs => [
    (tr('diapositivas'), 50, 32, false),
    (tr('apuntes'), 32, 42, false),
    (tr('libro'), 27, 44, false),
    (tr('problemas'), 32, 42, false),
    (tr('examen'), 32, 42, false),
    (tr('del profesor'), 32, 42, true),
  ];

  @override
  void draw(Canvas canvas) {
    final fade = _fadeOut(t);

    final source = const Rect.fromLTWH(44, 34, 88, 92);
    box(canvas, source, accent: palette.accentDark, radius: 8);
    // Unas líneas de código: las órdenes en verde, el texto en gris.
    final code = Paint()
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 7; i += 1) {
      final y = source.top + 14 + i * 10.5;
      final command = i == 0 || i == 3 || i == 6;
      code.color = command ? palette.accent : _lineGrey;
      final indent = command ? 0.0 : 8.0;
      final width = command ? 26.0 : (i.isOdd ? 50.0 : 38.0);
      canvas.drawLine(
        Offset(source.left + 10 + indent, y),
        Offset(source.left + 10 + indent + width, y),
        code,
      );
    }
    label(
      canvas,
      Offset(source.center.dx, source.bottom + 8),
      'tema-1.tex',
      colour: palette.accentDark,
    );

    // Los idiomas, uno detrás de otro.
    const languages = ['es', 'va', 'en'];
    final lit = (t * languages.length * 2).floor() % languages.length;
    for (var i = 0; i < languages.length; i += 1) {
      final chip = Rect.fromLTWH(source.left + 8 + i * 24.0, 150, 20, 12);
      final on = i == lit;
      canvas.drawRRect(
        RRect.fromRectAndRadius(chip, const Radius.circular(6)),
        Paint()
          ..color = on
              ? palette.accentDark
              : palette.accent.withValues(alpha: 0.14),
      );
      label(
        canvas,
        Offset(chip.center.dx, chip.top + 2),
        languages[i],
        colour: on ? palette.onAccent : palette.accentDark,
        size: 8,
      );
    }

    // Las flechas primero y las salidas encima: así una curva que va a la
    // tercera columna pasa por detrás de la primera en lugar de tacharla.
    Offset centreOf(int i) =>
        Offset(226 + (i % 3) * 84.0, 50 + (i ~/ 3) * 70.0);
    double startOf(int i) => 0.04 + i * 0.09;

    for (var i = 0; i < _outputs.length; i += 1) {
      final (_, width, _, _) = _outputs[i];
      final centre = centreOf(i);
      final path = curve(
        Offset(source.right, source.center.dy),
        Offset(centre.dx - width / 2 - 3, centre.dy),
      );
      trail(
        canvas,
        path,
        Curves.easeOut.transform(_phase(t, startOf(i), startOf(i) + 0.18)),
        colour: palette.accent.withValues(alpha: 0.7),
        opacity: fade,
      );
    }

    for (var i = 0; i < _outputs.length; i += 1) {
      final (name, width, height, teacher) = _outputs[i];
      final centre = centreOf(i);
      final start = startOf(i);
      final pop = Curves.easeOutBack.transform(
        _phase(t, start + 0.12, start + 0.26),
      );
      if (pop <= 0) continue;
      final rect = Rect.fromCenter(
        center: centre,
        width: width * pop,
        height: height * pop,
      );
      box(
        canvas,
        rect,
        radius: 3,
        opacity: fade,
        accent: teacher ? palette.teacher : null,
      );
      lines(canvas, rect.deflate(5), 3, opacity: fade, stroke: 1.6);
      if (teacher) {
        // La copia del profesor: una esquina en su color.
        canvas.drawPath(
          Path()
            ..moveTo(rect.right - 9, rect.top)
            ..lineTo(rect.right, rect.top)
            ..lineTo(rect.right, rect.top + 9)
            ..close(),
          Paint()..color = palette.teacher.withValues(alpha: fade),
        );
      }
      label(
        canvas,
        Offset(centre.dx, centre.dy + height / 2 + 6),
        name,
        opacity: fade * pop.clamp(0, 1),
      );
    }
  }
}

/// El historial: quién tocó qué y cuándo.
///
/// Con nombres y mensajes, no puntos sueltos: lo que se está contando es que
/// cada cambio lleva un autor y se puede volver a él, y una línea de puntos
/// anónimos no dice ninguna de las dos cosas.
class HistoryPainter extends _ArtPainter {
  const HistoryPainter(super.t, super.palette);

  List<(String, String, Color)> get _commits => [
    (tr('Tema 1'), tr('Javier'), palette.thm),
    (tr('Corregir errata'), tr('Marta'), palette.ex),
    (tr('Traducir a va'), tr('Javier'), palette.thm),
    (tr('Añadir ejemplo'), tr('Marta'), palette.ex),
  ];

  @override
  void draw(Canvas canvas) {
    final fade = _fadeOut(t);
    const y = 84.0;
    const left = 60.0;
    const right = 380.0;
    final head = Curves.easeInOut.transform(_phase(t, 0.02, 0.7));

    canvas.drawLine(
      const Offset(left, y),
      const Offset(right, y),
      Paint()
        ..color = palette.rule
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      const Offset(left, y),
      Offset(left + (right - left) * head, y),
      Paint()
        ..color = palette.accent.withValues(alpha: fade)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    final step = (right - left) / (_commits.length - 1);
    for (var i = 0; i < _commits.length; i += 1) {
      final x = left + step * i;
      final reached = (head * (right - left)) >= step * i - 0.5;
      if (!reached) {
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = palette.rule);
        continue;
      }
      final arrival = i / (_commits.length - 1) * 0.68 + 0.02;
      final pop = Curves.easeOutBack.transform(
        _phase(t, arrival, arrival + 0.08),
      );
      final last = i == _commits.length - 1;
      final (message, who, colour) = _commits[i];

      if (last) {
        // El último, con un anillo que late: es donde estás.
        final pulse = (t * 3) % 1;
        canvas.drawCircle(
          Offset(x, y),
          7 + pulse * 10,
          Paint()
            ..color = palette.accent.withValues(
              alpha: (1 - pulse) * 0.35 * fade,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(
        Offset(x, y),
        (last ? 7 : 5.5) * pop,
        Paint()..color = palette.card.withValues(alpha: fade),
      );
      canvas.drawCircle(
        Offset(x, y),
        (last ? 7 : 5.5) * pop,
        Paint()
          ..color = (last ? palette.accentDark : palette.muted).withValues(
            alpha: fade,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = last ? 2.4 : 1.6,
      );

      // El mensaje arriba, en una etiqueta.
      final bubble = Rect.fromCenter(
        center: Offset(x, y - 34),
        width: message.length * 5.0 + 16,
        height: 18,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubble, const Radius.circular(9)),
        Paint()
          ..color =
              (last ? palette.accent.withValues(alpha: 0.18) : palette.card)
                  .withValues(
                    alpha: (last ? 0.18 : 1) * fade * pop.clamp(0, 1),
                  ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubble, const Radius.circular(9)),
        Paint()
          ..color = (last ? palette.accentDark : palette.rule).withValues(
            alpha: fade * pop.clamp(0, 1),
          )
          ..style = PaintingStyle.stroke,
      );
      label(
        canvas,
        Offset(x, bubble.top + 5),
        message,
        colour: last ? palette.accentDark : palette.ink,
        size: 8.5,
        opacity: fade * pop.clamp(0, 1),
      );

      // Y quién, abajo: su inicial en un círculo de su color.
      final avatar = Offset(x, y + 28);
      canvas.drawCircle(
        avatar,
        10 * pop,
        Paint()..color = colour.withValues(alpha: 0.85 * fade),
      );
      label(
        canvas,
        Offset(avatar.dx, avatar.dy - 4.5),
        who[0],
        colour: palette.onAccent,
        size: 9,
        weight: FontWeight.w700,
        opacity: fade * pop.clamp(0, 1),
      );
      label(
        canvas,
        Offset(avatar.dx, avatar.dy + 15),
        who,
        size: 8.5,
        opacity: fade * pop.clamp(0, 1),
      );
    }
  }
}

/// El recorrido guiado, en miniatura: una ventana y un foco que se mueve.
///
/// Es la promesa del último paso --«un recorrido corto te enseñará dónde está
/// cada cosa»-- dibujada: sin él, esa frase se lee como una amenaza de
/// tutorial más.
class TourPainter extends _ArtPainter {
  const TourPainter(super.t, super.palette);

  @override
  void draw(Canvas canvas) {
    const window = Rect.fromLTWH(60, 12, 320, 146);
    box(canvas, window, radius: 10);

    // La barra de título y la de arriba.
    for (var i = 0; i < 3; i += 1) {
      canvas.drawCircle(
        Offset(window.left + 12 + i * 9.0, window.top + 9),
        2.6,
        Paint()..color = _lineGrey,
      );
    }
    final bar = Rect.fromLTWH(window.left + 38, window.top + 20, 270, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(4)),
      Paint()..color = palette.accent.withValues(alpha: 0.12),
    );

    // El carril.
    final rail = Rect.fromLTWH(window.left, window.top + 18, 30, 128);
    canvas.drawRect(rail, Paint()..color = palette.surface);
    final icons = [
      for (var i = 0; i < 4; i += 1)
        Rect.fromLTWH(rail.left + 8, rail.top + 12 + i * 24.0, 14, 14),
    ];
    for (final (index, icon) in icons.indexed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(icon, const Radius.circular(4)),
        Paint()..color = index == 0 ? palette.accentDark : _lineGrey,
      );
    }

    // El contenido: unas tarjetas.
    final cards = [
      for (var i = 0; i < 3; i += 1)
        Rect.fromLTWH(window.left + 40 + i * 92.0, window.top + 42, 84, 48),
      for (var i = 0; i < 2; i += 1)
        Rect.fromLTWH(window.left + 40 + i * 138.0, window.top + 98, 130, 40),
    ];
    for (final card in cards) {
      box(canvas, card, radius: 5, shadow: false);
      lines(canvas, card.deflate(7), 2, stroke: 1.6);
    }

    // El foco va del carril a una tarjeta y de ahí a la barra.
    final stops = [
      icons.first.inflate(4),
      cards.first.inflate(3),
      bar.inflate(3),
      icons[1].inflate(4),
    ];
    final leg = t * stops.length;
    final from = stops[leg.floor() % stops.length];
    final to = stops[(leg.floor() + 1) % stops.length];
    final move = Curves.easeInOutCubic.transform(_phase(leg % 1, 0.55, 1));
    final spot = Rect.lerp(from, to, move)!;

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(window, const Radius.circular(10)),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(window),
        Path()
          ..addRRect(RRect.fromRectAndRadius(spot, const Radius.circular(5))),
      ),
      Paint()..color = didactaVeil.withValues(alpha: 0.36),
    );
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(spot, const Radius.circular(5)),
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Y su globo, al lado.
    final bubble = Rect.fromLTWH(
      math.min(spot.right + 8, window.right - 70),
      math.min(spot.top, window.bottom - 30),
      62,
      24,
    );
    box(canvas, bubble, radius: 4, shadow: false);
    lines(canvas, bubble.deflate(4), 2, stroke: 1.6);
  }
}

// ------------------------------------------------------------- el fondo ---

/// El fondo de la bienvenida: dos manchas de luz verde que derivan despacio.
///
/// Casi no se ven, y es a propósito. Un fondo plano hacía que la pantalla
/// pareciera un formulario; uno que llama la atención compite con el texto,
/// que es lo que hay que leer.
class WelcomeBackdrop extends StatefulWidget {
  const WelcomeBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<WelcomeBackdrop> createState() => _WelcomeBackdropState();
}

class _WelcomeBackdropState extends State<WelcomeBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      unawaited(_drift.repeat());
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          context.palette.surface,
          Color.alphaBlend(
            context.palette.accent.withValues(alpha: 0.05),
            context.palette.surface,
          ),
        ],
      ),
    ),
    child: CustomPaint(
      painter: _Glow(_drift, context.palette),
      child: widget.child,
    ),
  );
}

class _Glow extends CustomPainter {
  _Glow(this.drift, this.palette) : super(repaint: drift);

  final Animation<double> drift;
  final DidactaPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final a = drift.value * 2 * math.pi;
    void glow(Offset centre, double radius, Color colour) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [colour, colour.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    glow(
      Offset(
        size.width * (0.18 + 0.06 * math.sin(a)),
        size.height * (0.22 + 0.05 * math.cos(a)),
      ),
      size.shortestSide * 0.55,
      palette.accent.withValues(alpha: 0.10),
    );
    glow(
      Offset(
        size.width * (0.84 + 0.05 * math.cos(a)),
        size.height * (0.78 + 0.06 * math.sin(a)),
      ),
      size.shortestSide * 0.6,
      palette.thm.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(_Glow old) => !identical(old.palette, palette);
}
