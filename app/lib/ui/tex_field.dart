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
  });

  final TexEditingController controller;
  final FocusNode? focusNode;
  final bool readOnly;
  final int? minLines;
  final String? hintText;
  final ValueChanged<String>? onChanged;

  /// Lo que se deja alrededor del conjunto de columnas y texto.
  final EdgeInsets padding;

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
          final gutter = controller.indent * indentStep;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GuidePainter(
                    text: value.text,
                    style: style,
                    gutter: gutter,
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
    required this.guidesAt,
    required this.scaler,
  });

  final String text;

  /// El mismo con el que se pinta la caja de texto, o las líneas parten en
  /// sitios distintos en cada capa.
  final TextStyle style;

  final double gutter;
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
    for (final metric in painter.computeLineMetrics()) {
      final at = painter
          .getPositionForOffset(Offset(0, top + metric.height / 2))
          .offset;
      for (final (index, block) in guidesAt(_lineOf(starts, at)).indexed) {
        canvas.drawRect(
          Rect.fromLTWH(index * indentStep, top, guideBar, metric.height),
          Paint()
            ..color = didactaBlockColour(
              block,
            ).withValues(alpha: block.closed ? 0.55 : 1.0),
        );
      }
      top += metric.height;
    }
    painter.dispose();
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
      old.guidesAt != guidesAt ||
      old.style != style;
}
