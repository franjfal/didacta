/// ⌘+clic (Ctrl+clic) en el PDF: a la lección y a la línea de donde salió.
///
/// LaTeX apunta en el `.synctex.gz` de cada compilación de qué fichero y qué
/// línea sale cada trozo del PDF. Se generaba y nadie lo leía. Con esto, lo
/// que se ve mal en una diapositiva se arregla pulsándolo: se abre la lección
/// con el cursor en su línea, sin buscarla.
///
/// Lo que va al motor es la página y el punto, y además la palabra pulsada y
/// su línea en el PDF: en una diapositiva SyncTeX apunta todo al
/// `\end{frame}`, y la palabra es lo que dice en qué línea de dentro estaba.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/compiler.dart';
import '../router.dart';
import '../state/session.dart';
import '../data/diagnostics.dart';
import '../l10n/tr.dart';

/// Un punto del PDF pulsado para ir a su fuente.
class SourceRequest {
  const SourceRequest({
    required this.pdf,
    required this.page,
    required this.x,
    required this.y,
    this.word,
    this.text,
  });

  final String pdf;
  final int page;

  /// En puntos, desde la esquina de arriba a la izquierda, como SyncTeX.
  final double x;
  final double y;

  /// Lo que había escrito ahí: la palabra y su línea.
  final String? word;
  final String? text;
}

/// Si la pulsación es la de ir a la fuente: con ⌘ en macOS, con Ctrl en los
/// demás.
bool get sourceModifierPressed => defaultTargetPlatform == TargetPlatform.macOS
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

/// Las pulsaciones con ⌘ de un visor.
///
/// La tecla se mira **al bajar el botón** y no cuando el visor da la
/// pulsación por buena: espera a ver si es un doble clic, y para entonces
/// quien pulsó con ⌘ puede haberla soltado ya. [down] va en el
/// `onPointerDown` de un `Listener` que envuelva al visor.
class SourceClick {
  bool _armed = false;

  void down(PointerDownEvent event) => _armed = sourceModifierPressed;

  /// Para `PdfViewerParams.onGeneralTap`: una pulsación con ⌘ es de esto;
  /// las demás, del visor.
  PdfViewerGeneralTapHandler handler(
    String pdf,
    ValueChanged<SourceRequest> onSource,
  ) => (context, controller, details) {
    if (details.type != PdfViewerGeneralTapType.tap) return false;
    final armed = _armed || sourceModifierPressed;
    _armed = false;
    if (!armed) return false;
    final hit = controller.getPdfPageHitTestResult(
      details.documentPosition,
      useDocumentLayoutCoordinates: true,
    );
    if (hit == null) return false;
    unawaited(requestAt(pdf, hit.page, hit.offset).then(onSource));
    return true;
  };
}

/// Lo que se pregunta por el punto [point] de [page], en coordenadas de PDF
/// (desde abajo a la izquierda).
Future<SourceRequest> requestAt(
  String pdf,
  PdfPage page,
  PdfPoint point,
) async {
  ({String? word, String? line}) text = (word: null, line: null);
  try {
    final found = await page.loadStructuredText();
    text = wordAndLineAt(found.fullText, found.charRects, point);
  } catch (caught, trace) {
    Diagnostics.instance.note('pdf_synctex.requestAt', caught, trace);
    // Sin texto se pregunta igual: SyncTeX sabe el fichero, y la línea sale
    // un poco menos fina.
  }
  return SourceRequest(
    pdf: pdf,
    page: page.pageNumber,
    x: point.x,
    y: page.height - point.y,
    word: text.word,
    text: text.line,
  );
}

bool _isLetter(String char) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(char);

/// La palabra bajo [point] y la línea del PDF en la que está.
///
/// La letra más cercana, si está a menos de medio cuerpo: pulsar entre dos
/// palabras o al final de una línea cuenta como pulsar la de al lado.
({String? word, String? line}) wordAndLineAt(
  String fullText,
  List<PdfRect> charRects,
  PdfPoint point,
) {
  var best = -1;
  var distance = double.infinity;
  final count = charRects.length < fullText.length
      ? charRects.length
      : fullText.length;
  for (var i = 0; i < count; i += 1) {
    if (!_isLetter(fullText[i])) continue;
    final d = charRects[i].distanceSquaredTo(point);
    if (d < distance) {
      distance = d;
      best = i;
    }
  }
  if (best < 0 || distance > 36) return (word: null, line: null);
  var start = best;
  while (start > 0 && _isLetter(fullText[start - 1])) {
    start -= 1;
  }
  var end = best + 1;
  while (end < fullText.length && _isLetter(fullText[end])) {
    end += 1;
  }
  final lineStart = fullText.lastIndexOf('\n', best) + 1;
  final lineEnd = fullText.indexOf('\n', best);
  return (
    word: fullText.substring(start, end),
    line: fullText
        .substring(lineStart, lineEnd < 0 ? fullText.length : lineEnd)
        .trim(),
  );
}

/// De qué repositorio abierto es [pdf]: el que tenga su carpeta de
/// compilación dentro. Null si de ninguno, y entonces se pregunta al primero.
String? repoOfPdf(Session session, String pdf) {
  for (final repo in session.snippetRepos) {
    final root = session.pathOf(repo);
    if (root != null && pdf.startsWith('$root/')) return repo;
  }
  return null;
}

/// Va a donde diga SyncTeX: la lección, en su idioma y en su línea.
///
/// Lo que no es de una lección --la portada, el índice, que los escribe el
/// documento-- se dice con su fichero y su línea, sin ir a ninguna parte.
/// [onLeave], antes de irse: cerrar el diálogo en el que está el PDF.
Future<void> openSourceAt(
  BuildContext context,
  Session session,
  SourceRequest request, {
  VoidCallback? onLeave,
}) async {
  final repo = repoOfPdf(session, request.pdf);
  final compiler = session.compiler(repo: repo);
  if (compiler == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.maybeOf(context);
  void say(String text) => messenger?.showSnackBar(
    SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      width: 520,
    ),
  );
  final SourceSpot? spot;
  try {
    spot = await compiler.sourceAt(
      pdf: request.pdf,
      page: request.page,
      x: request.x,
      y: request.y,
      word: request.word,
      text: request.text,
    );
  } on CompileException catch (error) {
    say(error.message);
    return;
  }
  if (spot == null) {
    say(tr('En ese punto no hay nada que venga de un fichero.'));
    return;
  }
  final unit = spot.unit == null
      ? null
      : session.unitByPath(spot.unit!, repo: repo);
  if (unit == null) {
    say(
      tr(
        'Eso lo escribe {0}, en la línea {1}: '
        'no es de ninguna lección.',
        [spot.path ?? spot.file, spot.line],
      ),
    );
    return;
  }
  onLeave?.call();
  router?.go(Routes.unit(unit.path, language: spot.language, line: spot.line));
}
