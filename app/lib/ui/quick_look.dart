/// Ojear un PDF ya compilado, sin salir de la biblioteca.
///
/// La pregunta que resuelve es la de quien prepara una clase: de estas ocho
/// lecciones sobre sucesiones, ¿cuál era la que tenía el dibujo? Entrar en
/// cada una, mirar y volver son tres pasos por lección; verla encima de la
/// lista es uno.
///
/// Solo enseña lo que **ya está compilado**. Compilar desde aquí sería
/// esconder tres segundos de espera detrás de un gesto que parece
/// instantáneo, y la pantalla de la unidad ya existe para eso.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/compiler.dart';
import '../model/catalogue.dart';
import 'package:provider/provider.dart';

import '../router.dart';
import '../state/session.dart';
import 'theme.dart';

/// Qué versión de una unidad se puede ojear, si es que hay alguna.
///
/// Prefiere la que se haya elegido arriba y el idioma que se está mirando;
/// si eso no está compilado, cualquier otra cosa que sí lo esté. Enseñar
/// «diapositivas en valenciano» cuando se pidió «libro en castellano» es
/// peor que nada solo si no se dice, y se dice.
ExistingOutput? quickLookFor(
  Session session,
  Unit unit, {
  String? profile,
  String? language,
}) {
  final outputs = session.built[unit.path];
  if (outputs == null || outputs.isEmpty) return null;
  final wanted = profile ?? session.previewProfile;
  final code = language ?? session.language;

  ExistingOutput? best;
  for (final output in outputs) {
    if (!output.exists) continue;
    if (output.profile == wanted && output.language == code) return output;
    // Por orden de cercanía a lo pedido: la versión que se quería en otro
    // idioma antes que otra versión cualquiera.
    final better =
        best == null ||
        (output.profile == wanted && best.profile != wanted) ||
        (output.language == code &&
            best.language != code &&
            output.profile == best.profile);
    if (better) best = output;
  }
  return best;
}

/// Abre el previo en un modal.
Future<void> showQuickLook(
  BuildContext context, {
  required Unit unit,
  required ExistingOutput output,
  required String language,
  required VoidCallback onOpenUnit,
  required ValueChanged<String> onExternal,
  required ValueChanged<String> onReveal,
}) => showDialog<void>(
  context: context,
  // Un modal y no una pestaña: se abre para mirar tres segundos y cerrarse,
  // y una pestaña por cada lección que se ojea llenaría la barra de
  // pestañas que nadie pidió.
  builder: (context) => _QuickLook(
    unit: unit,
    output: output,
    language: language,
    onOpenUnit: onOpenUnit,
    onExternal: onExternal,
    onReveal: onReveal,
  ),
);

class _QuickLook extends StatefulWidget {
  const _QuickLook({
    required this.unit,
    required this.output,
    required this.language,
    required this.onOpenUnit,
    required this.onExternal,
    required this.onReveal,
  });

  final Unit unit;
  final ExistingOutput output;
  final String language;
  final VoidCallback onOpenUnit;
  final ValueChanged<String> onExternal;
  final ValueChanged<String> onReveal;

  @override
  State<_QuickLook> createState() => _QuickLookState();
}

class _QuickLookState extends State<_QuickLook> {
  final PdfViewerController _controller = PdfViewerController();
  int _page = 1;
  int _pages = 0;

  @override
  Widget build(BuildContext context) {
    final output = widget.output;
    final asked =
        output.profile == context.read<Session>().previewProfile &&
        output.language == widget.language;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 980,
        height: 760,
        child: Column(
          children: [
            _Bar(
              title: widget.unit.title(widget.language),
              output: output,
              asked: asked,
              page: _page,
              pages: _pages,
              onPage: (delta) => _controller.goToPage(
                pageNumber: (_page + delta).clamp(1, _pages == 0 ? 1 : _pages),
              ),
              onOpenUnit: () {
                Navigator.of(context).pop();
                widget.onOpenUnit();
              },
              onExternal: () => widget.onExternal(output.pdf),
              onReveal: () => widget.onReveal(output.pdf),
            ),
            Expanded(
              child: ColoredBox(
                color: didactaPanel,
                child: PdfViewer.file(
                  output.pdf,
                  controller: _controller,
                  params: PdfViewerParams(
                    margin: 10,
                    backgroundColor: didactaPanel,
                    onViewerReady: (document, controller) {
                      if (!mounted) return;
                      setState(() => _pages = document.pages.length);
                    },
                    onPageChanged: (page) {
                      if (mounted && page != null) setState(() => _page = page);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.title,
    required this.output,
    required this.asked,
    required this.page,
    required this.pages,
    required this.onPage,
    required this.onOpenUnit,
    required this.onExternal,
    required this.onReveal,
  });

  final String title;
  final ExistingOutput output;
  final bool asked;
  final int page;
  final int pages;
  final ValueChanged<int> onPage;
  final VoidCallback onOpenUnit;
  final VoidCallback onExternal;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: didactaCard,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${output.label} · ${output.language}',
                    style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                  ),
                  // Cuando no es lo que se pidió, se dice: enseñar otra cosa
                  // sin avisar es peor que no enseñar nada.
                  if (!asked)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text(
                        'la que había compilada',
                        style: TextStyle(fontSize: 11, color: didactaEx),
                      ),
                    ),
                  if (output.stale)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text(
                        'se ha editado después de compilar',
                        style: TextStyle(fontSize: 11, color: didactaEx),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (pages > 0) ...[
          IconButton(
            tooltip: 'Anterior',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: page > 1 ? () => onPage(-1) : null,
          ),
          Text(
            '$page/$pages',
            style: const TextStyle(
              fontSize: 12,
              color: didactaMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: 'Siguiente',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: page < pages ? () => onPage(1) : null,
          ),
          const SizedBox(width: 6),
        ],
        IconButton(
          key: const Key('quick-look-external'),
          tooltip: 'Abrir en el visor del sistema',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.open_in_new, size: 17),
          onPressed: onExternal,
        ),
        IconButton(
          key: const Key('quick-look-reveal'),
          tooltip: 'Ver en el Finder',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.folder_open_outlined, size: 17),
          onPressed: onReveal,
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          key: const Key('quick-look-open-unit'),
          icon: const Icon(Icons.edit_outlined, size: 15),
          label: const Text('Abrir la unidad'),
          onPressed: onOpenUnit,
        ),
        IconButton(
          key: const Key('quick-look-close'),
          tooltip: 'Cerrar',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// El botón de ojear una unidad, cuando hay algo compilado que ojear.
///
/// Aparece al pasar por encima y no siempre: en una rejilla de treinta
/// tarjetas, treinta botones son treinta cosas que miran hacia atrás. Al
/// apuntar una, la que se está mirando, aparece el suyo.
class QuickLookButton extends StatelessWidget {
  const QuickLookButton({
    super.key,
    required this.unit,
    required this.language,
    required this.visible,
    this.compact = false,
  });

  final Unit unit;
  final String language;

  /// Si el ratón está encima. Se sigue construyendo cuando no, para que la
  /// fila no cambie de alto al apuntarla.
  final bool visible;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final output = quickLookFor(session, unit, language: language);
    final size = compact ? 26.0 : 30.0;
    if (output == null) return SizedBox(width: size);

    return SizedBox(
      width: size,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 110),
        opacity: visible ? 1 : 0,
        child: IconButton(
          key: Key('quick-look-${unit.path}'),
          tooltip: output.stale
              ? 'Ojear lo compilado (se ha editado después)'
              : 'Ojear ${output.label.toLowerCase()} sin abrir la unidad',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          icon: Icon(
            Icons.visibility_outlined,
            size: compact ? 15 : 16,
            color: output.stale ? didactaEx : didactaMuted,
          ),
          // Sin `onPressed` cuando no se ve: si no, un clic en el hueco de
          // una fila que no está apuntada abriría un PDF.
          onPressed: !visible
              ? null
              : () => showQuickLook(
                  context,
                  unit: unit,
                  output: output,
                  language: language,
                  onOpenUnit: () => context.go(Routes.unit(unit.path)),
                  onExternal: (path) => _external(context, session, path),
                  onReveal: (path) =>
                      _external(context, session, path, reveal: true),
                ),
        ),
      ),
    );
  }

  Future<void> _external(
    BuildContext context,
    Session session,
    String path, {
    bool reveal = false,
  }) async {
    final compiler = session.compiler(repo: unit.repo);
    if (compiler == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      reveal ? await compiler.reveal(path) : await compiler.open(path);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
