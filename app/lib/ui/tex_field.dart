/// Una caja de texto que escribe LaTeX de Didacta.
///
/// Lo mismo en las tres pantallas donde se escribe --una lección, los tres
/// campos de un problema y cada fragmento de un tema--: el texto coloreado por
/// [TexEditingController] y, en el margen, una columna por cada entorno que lo
/// envuelve, del color de ese entorno.
///
/// Las columnas se pintan **detrás** de la caja y midiendo el texto aparte,
/// porque una caja de texto no deja pintar entre sus líneas. Eso obliga a que
/// las dos medidas coincidan, y lo que lo garantiza es el strut forzado: sin
/// él, una línea con una fórmula alta mide más en una capa que en la otra y
/// todo lo de abajo queda corrido. Hay un test que lo comprueba con una línea
/// partida en dos.
///
/// El texto va como está en el fichero, sin sangrar: la sangría es de la vista
/// y no se guarda (D54), y una caja tiene un solo margen izquierdo. A la caja
/// entera se le aparta la sangría más honda de su texto, y las columnas caen
/// en ese hueco.
library;

import 'package:flutter/material.dart';

import '../model/tex_outline.dart';
import 'tex_highlight.dart';
import 'theme.dart';

/// Lo que ocupa un nivel de sangría, y el grosor de su columna.
const double indentStep = 14;
const double guideBar = 2;

class TexField extends StatelessWidget {
  const TexField({
    super.key,
    required this.controller,
    this.focusNode,
    this.readOnly = false,
    this.minLines,
    this.hintText,
    this.onChanged,
    this.padding = EdgeInsets.zero,
    this.lineNumbers = false,
  });

  final TexEditingController controller;
  final FocusNode? focusNode;
  final bool readOnly;
  final int? minLines;
  final String? hintText;
  final ValueChanged<String>? onChanged;

  /// Lo que se deja alrededor del conjunto de columnas y texto.
  final EdgeInsets padding;

  /// Si lleva la regleta de números a la izquierda.
  ///
  /// Solo en el fichero entero. En los tres campos de un problema y en un
  /// fragmento de un tema no: ahí lo que se edita son cuatro líneas sueltas
  /// que no son «la línea 37» de nada, y una columna de números al lado de un
  /// campo de dos renglones es ruido con aspecto de herramienta.
  ///
  /// El número va en la **primera fila visual** de cada línea del fichero. Una
  /// línea larga ocupa cuatro renglones en pantalla y sigue siendo una línea:
  /// numerar los renglones sería numerar el ancho de la ventana.
  final bool lineNumbers;

  @override
  Widget build(BuildContext context) {
    // El estilo **efectivo** de la caja, no `monoStyle` a secas: un `TextField`
    // mezcla el suyo sobre el `bodyLarge` del tema, así que el espaciado de
    // letra puede no ser el mismo y las líneas largas partirían en otro sitio
    // en cada capa. Se calcula una vez y lo usan las dos.
    final style = Theme.of(context).textTheme.bodyLarge!.merge(monoStyle);

    return Padding(
      padding: padding,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final numbers = lineNumbers
              ? _numbersWidth(
                  value.text,
                  style,
                  MediaQuery.textScalerOf(context),
                )
              : 0.0;
          final gutter = numbers + controller.indent * indentStep;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GuidePainter(
                    text: value.text,
                    style: style,
                    gutter: gutter,
                    numbers: numbers,
                    guidesAt: controller.guidesAt,
                    scaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: gutter),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: readOnly,
                  minLines: minLines,
                  maxLines: null,
                  // LaTeX es código: monoespaciada, sin autocorrección y sin
                  // mayúscula automática, que sobre un `\begin` es un error de
                  // compilación.
                  style: style,
                  strutStyle: monoStrut,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: didactaAccentDark,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: hintText,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Lo que ocupa la regleta de números, medido con el tipo de la caja.
///
/// Se mide en lugar de estimarse porque de eso depende dónde empieza el
/// texto, y el texto tiene que empezar en el mismo sitio en las dos capas: la
/// que pinta y la que se escribe. Un fichero de 1000 líneas necesita una
/// columna más que uno de 999, y el día que cruza esa frontera todo lo demás
/// se mueve con él.
double _numbersWidth(String text, TextStyle style, TextScaler scaler) {
  var lines = 1;
  for (var i = 0; i < text.length; i += 1) {
    if (text[i] == '\n') lines += 1;
  }
  final painter = TextPainter(
    text: TextSpan(text: '0' * '$lines'.length, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width + numbersPad * 2;
}

/// El aire a cada lado de la regleta.
const double numbersPad = 8;

/// Las columnas de colores del fragmento que se está editando.
///
/// Mide el texto por su cuenta con los mismos parámetros que la caja —tipo,
/// strut, ancho y escala— y pinta una barra por línea visual. Lo que hace que
/// las dos medidas coincidan es el strut forzado: sin él, una línea con una
/// fórmula alta mide más en una capa que en la otra y todo lo de abajo queda
/// corrido.
class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.text,
    required this.style,
    required this.gutter,
    required this.numbers,
    required this.guidesAt,
    required this.scaler,
  });

  final String text;

  /// El mismo con el que se pinta la caja de texto, o las líneas parten en
  /// sitios distintos en cada capa.
  final TextStyle style;

  final double gutter;

  /// Lo que ocupa la regleta de números; cero cuando no la lleva. Las
  /// columnas de colores empiezan después.
  final double numbers;

  final List<TexBlock> Function(int line) guidesAt;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - gutter;
    if (width <= 0 || text.isEmpty) return;

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      strutStyle: monoStrut,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: width);

    // Dónde empieza cada línea del fichero, para ir de un desplazamiento a
    // una línea.
    final starts = <int>[0];
    for (var i = 0; i < text.length; i += 1) {
      if (text[i] == '\n') starts.add(i + 1);
    }

    var top = 0.0;
    var previous = -1;
    for (final metric in painter.computeLineMetrics()) {
      final at = painter
          .getPositionForOffset(Offset(0, top + metric.height / 2))
          .offset;
      final line = _lineOf(starts, at);
      for (final (index, block) in guidesAt(line).indexed) {
        canvas.drawRect(
          Rect.fromLTWH(
            numbers + index * indentStep,
            top,
            guideBar,
            metric.height,
          ),
          Paint()
            ..color = didactaBlockColour(
              block,
            ).withValues(alpha: block.closed ? 0.55 : 1.0),
        );
      }
      // Solo en el primer renglón de cada línea del fichero: los demás son
      // la misma línea partida por el ancho de la ventana.
      if (numbers > 0 && line != previous) {
        _number(canvas, line + 1, top, metric.height);
        previous = line;
      }
      top += metric.height;
    }
    painter.dispose();
  }

  /// Pinta un número, alineado a la derecha contra el texto.
  ///
  /// A la derecha porque así las unidades quedan en columna y el salto de 9 a
  /// 10 no mueve nada de sitio, que es lo que hace que una regleta se pueda
  /// leer de un vistazo en lugar de tener que buscar el número.
  void _number(Canvas canvas, int line, double top, double height) {
    final label = TextPainter(
      text: TextSpan(
        text: '$line',
        style: style.copyWith(
          color: didactaMuted.withValues(alpha: 0.55),
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    label.paint(
      canvas,
      Offset(
        numbers - numbersPad - label.width,
        top + (height - label.height) / 2,
      ),
    );
    label.dispose();
  }

  static int _lineOf(List<int> starts, int offset) {
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.text != text ||
      old.gutter != gutter ||
      old.numbers != numbers ||
      old.guidesAt != guidesAt ||
      old.style != style;
}
