/// Un PDF compilado, abierto dentro de la aplicación.
///
/// Antes esto salía al visor del sistema, y estaba mal por una razón que se
/// ve en cuanto se usa: comparar «cómo queda en diapositivas» con «cómo queda
/// en libro» es mirar dos cosas a la vez, y salir a otra aplicación para cada
/// una rompe justo eso. Ahora cada salida es una pestaña más, al lado de los
/// idiomas y de `unit.yaml`, y se abren varias.
///
/// El visor del sistema **sigue estando**, en dos botones. No es redundancia:
/// tiene pantalla completa para pasar diapositivas de verdad, y el Finder es
/// desde donde se arrastra un PDF a un correo. Lo que se quita es la
/// obligación de salir para verlo.
library;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'theme.dart';

/// Un PDF abierto: qué es, y de dónde salió.
class OpenPdf {
  const OpenPdf({
    required this.path,
    required this.profile,
    required this.language,
    required this.pages,
  });

  final String path;
  final String profile;
  final String language;
  final int pages;

  /// Lo que pone en la pestaña. Corto: caben tres o cuatro.
  String get label => '$profile · $language';

  /// La identidad de la pestaña. Es la ruta y no el perfil, porque dos
  /// unidades distintas pueden tener el mismo perfil abierto a la vez.
  String get key => path;
}

class PdfTabView extends StatefulWidget {
  const PdfTabView({
    super.key,
    required this.pdf,
    required this.onOpenExternally,
    required this.onReveal,
    required this.onRecompile,
  });

  final OpenPdf pdf;

  /// El visor del sistema: pantalla completa para pasar diapositivas.
  final VoidCallback onOpenExternally;

  /// El Finder: desde donde se arrastra un PDF a un correo.
  final VoidCallback onReveal;

  /// Volver a compilar esta misma salida, para después de editar.
  final VoidCallback onRecompile;

  @override
  State<PdfTabView> createState() => _PdfTabViewState();
}

class _PdfTabViewState extends State<PdfTabView> {
  final PdfViewerController _controller = PdfViewerController();
  int _page = 1;
  int _pages = 0;
  Object? _problem;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Bar(
          pdf: widget.pdf,
          page: _page,
          pages: _pages == 0 ? widget.pdf.pages : _pages,
          onFirst: () => _controller.goToPage(pageNumber: 1),
          onPrevious: _page > 1
              ? () => _controller.goToPage(pageNumber: _page - 1)
              : null,
          onNext: _page < (_pages == 0 ? widget.pdf.pages : _pages)
              ? () => _controller.goToPage(pageNumber: _page + 1)
              : null,
          onOpenExternally: widget.onOpenExternally,
          onReveal: widget.onReveal,
          onRecompile: widget.onRecompile,
        ),
        Expanded(
          child: _problem != null
              ? _Failure(path: widget.pdf.path, problem: _problem!)
              : ColoredBox(
                  // Gris y no blanco: un PDF blanco sobre blanco no tiene
                  // bordes, y en diapositivas el borde es donde se ve si algo
                  // se sale de la caja.
                  color: const Color(0xFF52565C),
                  child: PdfViewer.file(
                    widget.pdf.path,
                    controller: _controller,
                    params: PdfViewerParams(
                      margin: 10,
                      backgroundColor: const Color(0xFF52565C),
                      // Dos páginas de diapositivas caben al lado; en A4 no,
                      // y el visor decide por el ancho disponible.
                      onViewerReady: (document, controller) {
                        if (!mounted) return;
                        setState(() => _pages = document.pages.length);
                      },
                      onPageChanged: (page) {
                        if (!mounted || page == null) return;
                        setState(() => _page = page);
                      },
                      errorBannerBuilder:
                          (context, error, stackTrace, documentRef) {
                            // Se cuenta en la pantalla en lugar de dejar un
                            // hueco gris: un PDF que no abre suele ser una
                            // compilación que se borró.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _problem = error);
                            });
                            return const SizedBox.shrink();
                          },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.pdf,
    required this.page,
    required this.pages,
    required this.onFirst,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenExternally,
    required this.onReveal,
    required this.onRecompile,
  });

  final OpenPdf pdf;
  final int page;
  final int pages;
  final VoidCallback onFirst;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onOpenExternally;
  final VoidCallback onReveal;
  final VoidCallback onRecompile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          return Row(
            children: [
              IconButton(
                tooltip: 'Primera página',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.first_page, size: 18),
                onPressed: pages > 1 ? onFirst : null,
              ),
              IconButton(
                tooltip: 'Anterior',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: onPrevious,
              ),
              Text(
                '$page / $pages',
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: didactaMuted,
                ),
              ),
              IconButton(
                tooltip: 'Siguiente',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed: onNext,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pdf.path.split('/').last,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: didactaMuted,
                  ),
                ),
              ),
              IconButton(
                key: const Key('pdf-recompile'),
                tooltip: 'Volver a compilar',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: onRecompile,
              ),
              // Los dos caminos externos, que siguen haciendo falta: pantalla
              // completa para pasar diapositivas, y el Finder para arrastrar
              // el PDF a un correo.
              if (narrow)
                MenuAnchor(
                  builder: (context, controller, child) => IconButton(
                    tooltip: 'Más',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.open_in_new, size: 15),
                      onPressed: onOpenExternally,
                      child: const Text('Abrir en el visor del sistema'),
                    ),
                    MenuItemButton(
                      leadingIcon: const Icon(
                        Icons.folder_open_outlined,
                        size: 15,
                      ),
                      onPressed: onReveal,
                      child: const Text('Ver en el Finder'),
                    ),
                  ],
                )
              else ...[
                IconButton(
                  key: const Key('pdf-external'),
                  tooltip:
                      'Abrir en el visor del sistema '
                      '(pantalla completa)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_new, size: 17),
                  onPressed: onOpenExternally,
                ),
                IconButton(
                  key: const Key('pdf-reveal'),
                  tooltip: 'Ver en el Finder',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.folder_open_outlined, size: 17),
                  onPressed: onReveal,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.path, required this.problem});

  final String path;
  final Object problem;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se ha podido abrir el PDF',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SelectableText(
              path,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: didactaMuted,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Lo más probable es que la compilación se haya borrado: el '
              'directorio de compilación no se versiona y se puede limpiar. '
              'Vuelve a compilar.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            SelectableText(
              '$problem',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    ),
  );
}
