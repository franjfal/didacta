/// Los tres dibujos de la pantalla de bienvenida.
///
/// Dibujados y no fotos ni capturas, por tres razones. Una captura de la
/// aplicación envejece con la aplicación y hay que rehacerla cada vez que se
/// mueve un botón. Una ilustración de archivo decora y no explica. Y un
/// fichero de imagen habría que empaquetarlo, escalarlo para cada pantalla y
/// volver a dibujarlo el día que cambie el color de la marca.
///
/// Lo que se dibuja es el **mecanismo**, que es lo que el texto de al lado
/// está contando: una lección que entra en varios cursos, un fichero del que
/// salen muchos PDF, y un historial con nombres. Si el dibujo no dijera nada
/// que no diga el título, sobraría.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

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

/// El lienzo de un dibujo: proporción fija y el fondo de las tarjetas.
class WelcomeArt extends StatelessWidget {
  const WelcomeArt({super.key, required this.painter, this.height = 104});

  final CustomPainter painter;
  final double height;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: didactaSurface,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: painter, size: Size.infinite),
    ),
  );
}

/// Lo compartido por los tres: cómo se pinta una caja y una etiqueta.
abstract class _ArtPainter extends CustomPainter {
  const _ArtPainter();

  static final Paint _fill = Paint()..color = didactaCard;
  static final Paint _line = Paint()
    ..color = didactaRule
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  void box(Canvas canvas, Rect rect, {Color? accent, double radius = 3}) {
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rounded, _fill);
    canvas.drawRRect(
      rounded,
      accent == null
          ? _line
          : (Paint()
              ..color = accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4),
    );
  }

  /// Unas rayas dentro de una caja, que es cómo se lee «esto tiene texto».
  void lines(Canvas canvas, Rect rect, int count, {Color? colour}) {
    final paint = Paint()
      ..color = (colour ?? didactaRule)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final step = rect.height / (count + 1);
    for (var i = 1; i <= count; i += 1) {
      final y = rect.top + step * i;
      final width = i.isOdd ? rect.width * 0.78 : rect.width * 0.55;
      canvas.drawLine(
        Offset(rect.left + 4, y),
        Offset(rect.left + 4 + width, y),
        paint,
      );
    }
  }

  void label(Canvas canvas, Offset at, String text, {Color? colour}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 8.5,
          height: 1,
          color: colour ?? didactaMuted,
          fontWeight: FontWeight.w600,
          fontFamily: welcomeArtFontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, 0));
  }

  /// Una flecha de una caja a otra, con la punta.
  void arrow(Canvas canvas, Offset from, Offset to, {Color? colour}) {
    final paint = Paint()
      ..color = (colour ?? didactaRule)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    // Curva y no recta: tres rectas saliendo del mismo punto se pisan y
    // parecen una mancha.
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx + (to.dx - from.dx) * 0.5,
        from.dy,
        from.dx + (to.dx - from.dx) * 0.5,
        to.dy,
        to.dx,
        to.dy,
      );
    canvas.drawPath(path, paint);
    canvas.drawCircle(to, 2, Paint()..color = colour ?? didactaRule);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Una lección que entra en varios cursos.
///
/// El dibujo del reúso: la pieza de la izquierda es **una**, y las tres cajas
/// de la derecha la contienen sin copiarla. Es lo que distingue esto de
/// duplicar un fichero en tres carpetas.
class ReusePainter extends _ArtPainter {
  const ReusePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = Rect.fromLTWH(18, size.height / 2 - 17, 74, 34);
    box(canvas, unit, accent: didactaAccentDark);
    lines(canvas, unit.deflate(5), 2, colour: didactaAccent);
    label(
      canvas,
      Offset(unit.center.dx, unit.bottom + 5),
      'una lección',
      colour: didactaAccentDark,
    );

    const names = ['Análisis I', 'Análisis FM', 'Cálculo'];
    final left = size.width * 0.55;
    final width = (size.width - left - 18).clamp(60.0, 130.0);
    for (var i = 0; i < 3; i += 1) {
      final top = 12.0 + i * 27;
      final course = Rect.fromLTWH(left, top, width, 21);
      box(canvas, course);
      arrow(
        canvas,
        Offset(unit.right, unit.center.dy),
        Offset(course.left, course.center.dy),
        colour: didactaAccent,
      );
      // Un trocito verde dentro: la misma lección, dentro de cada curso.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(course.left + 5, course.top + 6, 12, 9),
          const Radius.circular(2),
        ),
        Paint()..color = didactaAccent,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: names[i],
          style: TextStyle(
            fontSize: 9,
            color: didactaInk,
            fontFamily: welcomeArtFontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 24);
      painter.paint(canvas, Offset(course.left + 21, course.top + 6));
    }
  }
}

/// Un fichero del que salen muchos PDF.
///
/// Las salidas con proporciones distintas --las diapositivas apaisadas, el
/// libro estrecho-- porque es lo que las hace reconocibles de un vistazo sin
/// tener que leer la etiqueta.
class OutputsPainter extends _ArtPainter {
  const OutputsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTWH(18, size.height / 2 - 22, 58, 44);
    box(canvas, source, accent: didactaAccentDark);
    lines(canvas, source.deflate(6), 4, colour: didactaAccent);
    label(
      canvas,
      Offset(source.center.dx, source.bottom + 5),
      'un fichero',
      colour: didactaAccentDark,
    );

    // Apaisada la de diapositivas, altas las de papel: la forma dice cuál es
    // antes que la etiqueta.
    final shapes = <(String, double, double)>[
      ('diapositivas', 40, 24),
      ('apuntes', 26, 34),
      ('libro', 22, 38),
      ('examen', 26, 34),
    ];
    final left = size.width * 0.42;
    final gap = (size.width - left - 16) / shapes.length;

    for (var i = 0; i < shapes.length; i += 1) {
      final (name, width, height) = shapes[i];
      final centre = left + gap * i + gap / 2;
      final rect = Rect.fromCenter(
        center: Offset(centre, size.height / 2 - 6),
        width: width,
        height: height,
      );
      box(canvas, rect);
      lines(canvas, rect.deflate(4), 3);
      arrow(
        canvas,
        Offset(source.right, source.center.dy),
        Offset(rect.left, rect.center.dy),
      );
      label(canvas, Offset(centre, rect.bottom + 6), name);
    }
  }
}

/// El historial: quién tocó qué y cuándo.
///
/// Con nombres y mensajes, no puntos sueltos: lo que se está contando es que
/// cada cambio lleva un autor y se puede volver a él, y una línea de puntos
/// anónimos no dice ninguna de las dos cosas.
class HistoryPainter extends _ArtPainter {
  const HistoryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2 - 6;
    final left = 26.0;
    final right = size.width - 26;
    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      Paint()
        ..color = didactaRule
        ..strokeWidth = 1.5,
    );

    const commits = [
      ('Tema 1', 'Javier'),
      ('Corregir errata', 'Marta'),
      ('Traducir a va', 'Javier'),
      ('Añadir ejemplo', 'Marta'),
    ];
    final step = (right - left) / (commits.length - 1);

    for (var i = 0; i < commits.length; i += 1) {
      final at = Offset(left + step * i, y);
      final last = i == commits.length - 1;
      canvas.drawCircle(at, last ? 5 : 4, Paint()..color = didactaCard);
      canvas.drawCircle(
        at,
        last ? 5 : 4,
        Paint()
          ..color = last ? didactaAccentDark : didactaMuted
          ..style = PaintingStyle.stroke
          ..strokeWidth = last ? 2 : 1.4,
      );
      final (message, who) = commits[i];
      label(
        canvas,
        Offset(at.dx, y - 22),
        message,
        colour: last ? didactaAccentDark : didactaInk,
      );
      label(canvas, Offset(at.dx, y + 12), who);
    }
  }
}
