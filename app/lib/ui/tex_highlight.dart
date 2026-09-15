/// Cómo se pinta el LaTeX, dentro de la caja de texto.
///
/// Un `.tex` de Didacta se lee como código y se editaba como un bloc de notas.
/// Aquí se le pone color: las órdenes, los comentarios, las matemáticas, los
/// delimitadores, y el nombre de cada entorno **del color que ese entorno
/// tiene en el PDF** --`didacta-colours.sty`-- para que una solución sea azul
/// en la pantalla y en el papel.
///
/// Va dentro del texto editable y no pintado por encima porque no hay dos
/// vistas: sin modo edición, lo que se lee es lo mismo que se escribe. Un
/// `TextEditingController` puede decir cómo se pinta lo que contiene, y eso es
/// lo que hace [TexEditingController].
///
/// El orden en que se pinta importa, y es este:
///
/// 1. la sintaxis, que sale de trocear el texto;
/// 2. los delimitadores de cada entorno, del color del entorno, y **en rojo**
///    si se quedó sin cerrar: el aviso, en la línea que lo causó;
/// 3. lo que no se proyecta, en gris, por encima de todo: una línea que no
///    sale en el aula no tiene por qué destacar dentro de ella.
library;

import 'package:flutter/material.dart';

import '../model/tex_outline.dart';
import '../model/tex_syntax.dart';
import 'theme.dart';

/// El color de cada clase de trozo.
///
/// Sobrios a propósito: lo que tiene que destacar en un fichero de Didacta es
/// dónde empieza y acaba cada entorno, no cada llave.
Color? colourForToken(TexTokenKind kind) => switch (kind) {
  TexTokenKind.text => null,
  TexTokenKind.comment => didactaMuted.withValues(alpha: 0.75),
  TexTokenKind.command => didactaAlgo,
  TexTokenKind.environment => didactaInk,
  TexTokenKind.delimiter => didactaMuted.withValues(alpha: 0.8),
  TexTokenKind.math => didactaProp,
  TexTokenKind.special => didactaCor,
};

/// Cómo se pinta cada trozo del texto de un fichero.
///
/// [text] es el texto que hay ahora en la caja, que puede no ser el del árbol
/// —se está escribiendo—, así que todo lo que sale del árbol se recorta a lo
/// que el texto tiene ahora mismo.
TextSpan highlightFragment({
  required String text,
  required TextStyle base,
  required TexOutline outline,
  required TexSlice slice,
  required bool dim,
  required Color Function(TexBlock block) colourOf,
}) {
  if (text.isEmpty) return TextSpan(text: text, style: base);

  final styles = List<TextStyle>.filled(text.length, base);

  void paint(int from, int to, TextStyle style) {
    final start = from.clamp(0, text.length);
    final end = to.clamp(0, text.length);
    for (var i = start; i < end; i += 1) {
      styles[i] = style;
    }
  }

  // 1. La sintaxis.
  for (final token in scanLatex(text)) {
    final colour = colourForToken(token.kind);
    if (colour == null) continue;
    paint(
      token.start,
      token.end,
      base.copyWith(
        color: colour,
        fontStyle: token.kind == TexTokenKind.comment ? FontStyle.italic : null,
      ),
    );
  }

  // 2. Los delimitadores, del color de su entorno.
  for (final block in outline.blocks) {
    if (block.start < slice.start || block.start >= slice.end) continue;
    final colour = block.closed ? colourOf(block) : didactaTeacher;
    final style = base.copyWith(color: colour, fontWeight: FontWeight.w700);
    final open = block.start - slice.start;
    paint(open, open + '\\begin{${block.name}}'.length, style);
    if (block.closed) {
      final close = block.end - slice.start;
      paint(close - '\\end{${block.name}}'.length, close, style);
    }
  }

  // 3. Lo que no se proyecta, en gris, por encima de lo demás.
  if (dim) {
    final faded = base.copyWith(color: didactaMuted.withValues(alpha: 0.55));
    for (var line = slice.startLine; line <= slice.endLine; line += 1) {
      if (outline.projectedAt(line)) continue;
      final from = outline.lineStarts[line] - slice.start;
      final to = line + 1 < outline.lineStarts.length
          ? outline.lineStarts[line + 1] - slice.start
          : text.length;
      paint(from, to, faded);
    }
  }

  // Juntar los caracteres seguidos que se pintan igual: un span por carácter
  // sería correcto y haría inútil la pantalla.
  final spans = <TextSpan>[];
  var from = 0;
  for (var i = 1; i <= text.length; i += 1) {
    if (i < text.length && styles[i] == styles[from]) continue;
    spans.add(TextSpan(text: text.substring(from, i), style: styles[from]));
    from = i;
  }
  return TextSpan(children: spans);
}

/// Un controlador de texto que pinta LaTeX.
///
/// Sirve para los dos sitios donde se escribe un `.tex`: la caja de una unidad
/// y cada fragmento de la vista del tema. La diferencia es de dónde sale el
/// árbol --lo pone la vista cuando el fichero es un trozo de un documento, y
/// se calcula aquí cuando es un fichero suelto--, y esa diferencia es real:
/// dentro de un tema, una unidad puede colgar de una diapositiva que abrió la
/// anterior.
class TexEditingController extends TextEditingController {
  TexEditingController({super.text});

  TexOutline? _outline;
  TexSlice? _slice;
  bool _dim = false;

  /// Un fichero suelto: el árbol es el suyo y se rehace cuando cambia.
  TexOutline? _own;
  String? _ownOf;

  /// Le dice a la caja que su texto es un trozo de un documento.
  void inDocument({
    required TexOutline outline,
    required TexSlice? slice,
    required bool dim,
  }) {
    _outline = outline;
    _slice = slice;
    _dim = dim;
  }

  TexOutline get _tree {
    final given = _outline;
    if (given != null) return given;
    if (_own == null || _ownOf != text) {
      _own = TexOutline.ofText(text);
      _ownOf = text;
    }
    return _own!;
  }

  /// El trozo del árbol que le toca a este texto.
  TexSlice? get slice {
    final tree = _tree;
    if (_outline == null) {
      return tree.slices.isEmpty ? null : tree.slices.single;
    }
    return _slice;
  }

  /// Los entornos que sangran una línea de este texto, contando desde 0.
  ///
  /// Lo pregunta la caja para pintar sus columnas de color. Que salga de aquí
  /// es lo que hace que una unidad suelta las tenga sin que nadie le pase un
  /// árbol: se lo calcula ella.
  List<TexBlock> guidesAt(int line) {
    final piece = slice;
    if (piece == null) return const [];
    return _tree.guidesAt(piece.startLine + line);
  }

  /// La sangría más honda del texto: lo que se le aparta a la caja.
  int get indent {
    final piece = slice;
    return piece == null ? 0 : _tree.maxIndentIn(piece);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Mientras se compone con el teclado --acentos, IME-- manda el subrayado
    // del sistema: pintar por encima se lleva por delante la marca de lo que
    // se está escribiendo.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final piece = slice;
    if (piece == null) return TextSpan(text: text, style: style);
    return highlightFragment(
      text: text,
      base: style ?? const TextStyle(),
      outline: _tree,
      slice: piece,
      dim: _dim,
      colourOf: didactaBlockColour,
    );
  }
}

/// De qué color va un entorno.
///
/// Por nombre antes que por clase en lo que se revela: una respuesta, una
/// solución y una corrección tienen tres colores distintos en el PDF, y
/// juntarlos aquí en uno perdería justo la distinción que se mira.
Color didactaBlockColour(TexBlock block) => switch (block.name) {
  'answer' => didactaProp,
  'solution' => didactaThm,
  'marking' => didactaTeacher,
  'hint' => didactaEx,
  _ => switch (block.kind) {
    TexBlockKind.slide => didactaAccentDark,
    TexBlockKind.channel => didactaQues,
    TexBlockKind.exercise => didactaEx,
    TexBlockKind.reveal => didactaThm,
    TexBlockKind.theorem => didactaThm,
    TexBlockKind.teaching => didactaTeacher,
    TexBlockKind.list => didactaMuted,
    TexBlockKind.math => didactaDefn,
    TexBlockKind.figure => didactaDefn,
    TexBlockKind.document => didactaMuted,
    TexBlockKind.other => didactaMuted,
  },
};
