/// La marca de Didacta, dibujada una sola vez.
///
/// El icono de la aplicación y el logo del carril son el **mismo código**, y
/// eso es la razón de que esto exista en lugar de un PNG suelto: un icono que
/// se dibuja aparte se separa de la interfaz en el primer retoque, y acabas
/// con dos marcas parecidas que no son la misma. Aquí hay una.
///
/// Lo que dibuja es lo que hace la plataforma: **el mismo contenido en varias
/// versiones**. Tres hojas desplazadas en diagonal y, en la de delante, un
/// titular y dos líneas. Una unidad de Didacta sale en diapositivas, en
/// apuntes y en libro del mismo `.tex`, y eso es lo que se ve.
///
/// La primera versión era un diagrama --una fuente a la izquierda abriéndose
/// en tres bloques-- y estaba mal: se leía como el icono de un organigrama, y
/// a 16 px las líneas se convertían en barro. Tres siluetas grandes aguantan
/// el tamaño pequeño; un diagrama no.
///
/// La geometría va en una caja unidad de 0 a 1 y se escala al pintar, así que
/// el mismo trazado sirve para 16 px y para 1024 sin números mágicos por
/// tamaño.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Las proporciones de la marca, en una caja unidad.
///
/// Constantes con nombre y no números dentro del `paint`: son decisiones de
/// diseño --cuánto asoma cada hoja, cuánto pesa el titular-- y se ajustan
/// leyéndolas, no contándolas.
class _Sheets {
  const _Sheets._();

  /// Tres hojas iguales, desplazadas en diagonal.
  ///
  /// La de delante abajo-izquierda y las otras dos asomando arriba-derecha:
  /// es el gesto de «lo mismo, en tres versiones», que es lo que hace la
  /// plataforma. Y es lo único que se sigue leyendo a 16 px, donde cualquier
  /// diagrama con líneas se convierte en barro.
  static const double width = 0.52;
  static const double height = 0.64;
  static const double offset = 0.075;
  static const double radius = 0.045;

  /// Lo que se ve de las hojas de detrás. Bajando la opacidad en lugar de
  /// pintarlas grises: sobre un degradado, un gris fijo se despega del fondo
  /// en la mitad del icono.
  static const List<double> opacities = [0.42, 0.70, 1.0];

  /// El margen de la hoja de delante, donde va el contenido.
  static const double margin = 0.058;

  /// El titular: grueso y corto, para que a tamaño pequeño quede una mancha
  /// donde el ojo espera un título.
  static const double titleHeight = 0.062;
  static const double titleWidth = 0.62;

  /// Las dos líneas de texto. Dos y no cuatro: a 32 px, cuatro se juntan en
  /// una y el dibujo pierde el aire.
  static const double lineHeight = 0.036;
  static const List<double> lineWidths = [1.0, 0.74];
}

/// Pinta la marca en el rectángulo que se le dé.
///
/// Sin fondo: quién la usa decide si va sobre una baldosa verde --el icono--
/// o sobre un cuadrado que ya está pintado --el carril--. [ink] es el color
/// del contenido de la hoja de delante, y va en el verde de la casa para que
/// la marca no necesite un tercer color.
void paintDidactaMark(
  Canvas canvas,
  Rect box, {
  Color sheet = Colors.white,
  Color ink = didactaAccentDark,
  bool detail = true,
}) {
  final unit = box.shortestSide;
  final paint = Paint()..isAntiAlias = true;

  void rounded(Rect rect, double radius, Color colour) {
    paint.color = colour;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  // Las tres hojas. La última del bucle es la de delante, y sobre ella va el
  // contenido: así el orden de pintado y el orden de lectura coinciden.
  const spread = _Sheets.offset * 2;
  final left = (1 - _Sheets.width - spread) / 2;
  final top = (1 - _Sheets.height - spread) / 2;

  for (var i = 0; i < _Sheets.opacities.length; i += 1) {
    // i = 0 es la de más atrás: arriba y a la derecha.
    final shift = (_Sheets.opacities.length - 1 - i) * _Sheets.offset;
    final rect = Rect.fromLTWH(
      box.left + (left + shift) * box.width,
      box.top + (top + spread - shift) * box.height,
      _Sheets.width * box.width,
      _Sheets.height * box.height,
    );
    rounded(
      rect,
      _Sheets.radius * unit,
      sheet.withValues(alpha: sheet.a * _Sheets.opacities[i]),
    );

    // Por debajo de unos 40 px el titular y las líneas no son detalle: son
    // ruido. Tres píxeles de verde sobre blanco se ven como suciedad, no como
    // un documento. A tamaño pequeño se quedan las siluetas, que es lo que
    // Apple pide --arte por tamaño-- y lo que `Contents.json` permite dar.
    if (!detail || i != _Sheets.opacities.length - 1) continue;

    // El contenido de la hoja de delante: un titular y dos líneas, con el
    // aire de una página de verdad --el titular separado del cuerpo-- porque
    // es lo que hace que se lea como un documento y no como un rectángulo.
    final inner = rect.deflate(_Sheets.margin * unit);
    final title = _Sheets.titleHeight * unit;
    final line = _Sheets.lineHeight * unit;
    var y = inner.top + inner.height * 0.12;

    rounded(
      Rect.fromLTWH(inner.left, y, inner.width * _Sheets.titleWidth, title),
      line / 2,
      ink,
    );
    y += title + inner.height * 0.15;

    for (final width in _Sheets.lineWidths) {
      rounded(
        Rect.fromLTWH(inner.left, y, inner.width * width, line),
        line / 2,
        ink.withValues(alpha: 0.55),
      );
      y += line + inner.height * 0.09;
    }
  }
}

/// El icono completo: la baldosa y la marca encima.
///
/// [padding] es el hueco alrededor de la baldosa, en fracción del lienzo, y
/// [markInset] el hueco de la marca dentro de la baldosa. Los dos los dice
/// quien pinta porque cada destino quiere otra cosa:
///
/// * **macOS** pide que el cuadrado redondeado no llegue al borde --824 de
///   1024, o sea un 9,8% por lado--, porque el sistema pone ahí la sombra;
/// * un **«maskable»** de la web va a sangre y con la marca dentro del 80%
///   central: el sistema lo recorta con la forma que quiera, así que un
///   margen transparente se vería como un mordisco en el círculo, y una
///   marca hasta el borde se vería cortada.
void paintDidactaIcon(
  Canvas canvas,
  Size size, {
  double padding = 0.0977,
  bool rounded = true,
  bool? detail,
  double markInset = 0.055,
}) {
  final inset = size.shortestSide * padding;
  final tile = Rect.fromLTWH(
    inset,
    inset,
    size.width - inset * 2,
    size.height - inset * 2,
  );

  // Un degradado muy corto entre los dos verdes de la casa. El tema de la
  // interfaz es plano a propósito --miles de filas y un degradado en
  // cualquiera de ellas es ruido-- pero un icono enseña una sola cosa, y en
  // un Dock un plano absoluto parece un icono sin terminar.
  final tilePaint = Paint()
    ..isAntiAlias = true
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF5FB35F), didactaAccentDark],
    ).createShader(tile);

  if (rounded) {
    // El radio de Apple: 185,4 sobre una baldosa de 824, o sea 22,5%.
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, Radius.circular(tile.shortestSide * 0.225)),
      tilePaint,
    );
  } else {
    canvas.drawRect(tile, tilePaint);
  }

  // La marca, centrada y con su propio margen dentro de la baldosa. El
  // detalle se decide por el tamaño si nadie lo dice: es la regla, no una
  // opción que haya que recordar en cada llamada.
  paintDidactaMark(
    canvas,
    tile.deflate(tile.shortestSide * markInset),
    detail: detail ?? size.shortestSide >= 40,
  );
}

/// La marca, como widget. Es el logo del carril.
class DidactaMark extends StatelessWidget {
  const DidactaMark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkPainter(size: size)),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.size});

  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // A este tamaño no hay degradado que se aprecie, así que el carril lleva
    // el verde oscuro plano: es lo que el resto de la interfaz usa para el
    // acento, y el logo no tiene por qué ser la excepción.
    final tile = Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        tile,
        Radius.circular(math.max(3, tile.shortestSide * 0.18)),
      ),
      Paint()
        ..color = didactaAccentDark
        ..isAntiAlias = true,
    );
    paintDidactaMark(
      canvas,
      tile.deflate(tile.shortestSide * 0.08),
      // En pantalla el carril se dibuja a la densidad del dispositivo, así
      // que 30 px lógicos son 60 físicos y el detalle se ve.
      detail: size >= 24,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.size != size;
}
