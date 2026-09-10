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

  String get label => '$profile · $language';
}

/// Una pestaña: uno o varios PDF, lado a lado.
///
/// Varios porque la comparación que importa es la del mismo perfil en dos
/// idiomas: si la traducción valenciana sigue cabiendo en la diapositiva no
/// se puede saber sin las dos delante. Así que al compilar dos idiomas de un
/// perfil se abren juntos, y se pueden separar de un botón.
class PdfGroup {
  const PdfGroup({required this.id, required this.panes});

  /// La identidad de la pestaña. El perfil cuando el grupo salió de
  /// compilar; perfil e idioma cuando alguien lo desacopló, para que la
  /// versión separada no vuelva a caer en el grupo.
  final String id;

  final List<OpenPdf> panes;

  bool get isSingle => panes.length == 1;

  /// Lo que pone en la pestaña. Corto: caben tres o cuatro.
  String get label => isSingle
      ? panes.single.label
      : '${panes.first.profile} · ${panes.map((p) => p.language).join(' ')}';

  /// El número de páginas mayor, que es hasta dónde llega la navegación.
  ///
  /// El mayor y no el menor: si el valenciano ocupa una diapositiva más, esa
  /// diapositiva es exactamente la que hay que mirar.
  int get pages =>
      panes.fold(0, (most, pane) => pane.pages > most ? pane.pages : most);

  PdfGroup without(String language) => PdfGroup(
    id: id,
    panes: [
      for (final pane in panes)
        if (pane.language != language) pane,
    ],
  );
}

class PdfTabView extends StatefulWidget {
  const PdfTabView({
    super.key,
    required this.group,
    required this.onOpenExternally,
    required this.onReveal,
    required this.onRecompile,
    required this.onDetach,
  });

  final PdfGroup group;

  /// El visor del sistema: pantalla completa para pasar diapositivas.
  final ValueChanged<String> onOpenExternally;

  /// El Finder: desde donde se arrastra un PDF a un correo.
  final ValueChanged<String> onReveal;

  /// Volver a compilar, para después de editar.
  final VoidCallback onRecompile;

  /// Sacar una versión a su propia pestaña.
  final ValueChanged<String> onDetach;

  @override
  State<PdfTabView> createState() => _PdfTabViewState();
}

class _PdfTabViewState extends State<PdfTabView> {
  /// Un controlador por panel. La navegación de la barra los mueve a todos:
  /// comparar dos idiomas es mirar la misma página en los dos.
  final Map<String, PdfViewerController> _controllers = {};
  final Map<String, int> _page = {};
  final Map<String, int> _pages = {};
  final Map<String, Object> _problem = {};

  PdfViewerController _controllerFor(String key) =>
      _controllers.putIfAbsent(key, PdfViewerController.new);

  // Métodos con nombre en lugar de dejar que el panel toque `setState`: un
  // widget que llama al `setState` de otro es un widget que nadie puede leer
  // sin ir a mirar el otro.
  void _noteReady(String path, int pages) {
    if (!mounted) return;
    setState(() => _pages[path] = pages);
  }

  void _notePage(String path, int page) {
    if (!mounted) return;
    setState(() => _page[path] = page);
  }

  void _noteProblem(String path, Object error) {
    if (!mounted) return;
    setState(() => _problem[path] = error);
  }

  int pagesOf(OpenPdf pane) => _pages[pane.path] ?? pane.pages;

  int pageOf(OpenPdf pane) => _page[pane.path] ?? 1;

  Object? problemOf(OpenPdf pane) => _problem[pane.path];

  int get _current => _page[widget.group.panes.first.path] ?? 1;

  int get _total {
    final known = _pages[widget.group.panes.first.path];
    return known ?? widget.group.pages;
  }

  void _goTo(int page) {
    for (final pane in widget.group.panes) {
      final controller = _controllers[pane.path];
      if (controller == null) continue;
      final total = _pages[pane.path] ?? pane.pages;
      // Se recorta por panel: si una versión tiene una página menos, se
      // queda en la última en lugar de fallar.
      controller.goToPage(pageNumber: page > total ? total : page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panes = widget.group.panes;
    return Column(
      children: [
        _Bar(
          group: widget.group,
          page: _current,
          pages: _total,
          onFirst: _total > 1 ? () => _goTo(1) : null,
          onPrevious: _current > 1 ? () => _goTo(_current - 1) : null,
          onNext: _current < _total ? () => _goTo(_current + 1) : null,
          onOpenExternally: widget.onOpenExternally,
          onReveal: widget.onReveal,
          onRecompile: widget.onRecompile,
          onDetach: widget.onDetach,
        ),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < panes.length; i += 1) ...[
                if (i > 0) const VerticalDivider(width: 1),
                Expanded(
                  child: _Pane(pane: panes[i], parent: this),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Un panel: un PDF, con su idioma escrito encima.
///
/// El idioma se rotula siempre, incluso con un solo panel: dos capturas de
/// la misma diapositiva en dos idiomas son indistinguibles si el texto no se
/// lee, y el rótulo es lo que las distingue.
class _Pane extends StatelessWidget {
  const _Pane({required this.pane, required this.parent});

  final OpenPdf pane;
  final _PdfTabViewState parent;

  @override
  Widget build(BuildContext context) {
    final problem = parent.problemOf(pane);
    if (problem != null) {
      return _Failure(path: pane.path, problem: problem);
    }
    final total = parent.pagesOf(pane);
    final page = parent.pageOf(pane);

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: didactaPanel,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              Text(
                pane.language,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: didactaAccentDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$page / $total',
                  style: const TextStyle(
                    fontSize: 11,
                    color: didactaMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            // Gris y no blanco: un PDF blanco sobre blanco no tiene bordes,
            // y en diapositivas el borde es donde se ve si algo se sale.
            color: const Color(0xFF52565C),
            child: PdfViewer.file(
              pane.path,
              controller: parent._controllerFor(pane.path),
              params: PdfViewerParams(
                margin: 8,
                backgroundColor: const Color(0xFF52565C),
                onViewerReady: (document, controller) =>
                    parent._noteReady(pane.path, document.pages.length),
                onPageChanged: (page) {
                  if (page != null) parent._notePage(pane.path, page);
                },
                errorBannerBuilder: (context, error, stackTrace, documentRef) {
                  // Después del frame: esto se llama durante el build del
                  // visor, y un setState ahí no está permitido.
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => parent._noteProblem(pane.path, error),
                  );
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
    required this.group,
    required this.page,
    required this.pages,
    required this.onFirst,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenExternally,
    required this.onReveal,
    required this.onRecompile,
    required this.onDetach,
  });

  final PdfGroup group;
  final int page;
  final int pages;
  final VoidCallback? onFirst;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<String> onOpenExternally;
  final ValueChanged<String> onReveal;
  final VoidCallback onRecompile;
  final ValueChanged<String> onDetach;

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
          final narrow = constraints.maxWidth < 700;
          return Row(
            children: [
              IconButton(
                tooltip: 'Primera página',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.first_page, size: 18),
                onPressed: onFirst,
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
                  group.isSingle
                      ? group.panes.single.path.split('/').last
                      : '${group.panes.length} versiones a la vez',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textDirection: group.isSingle
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: didactaMuted,
                  ),
                ),
              ),
              // Separar una versión: solo tiene sentido cuando hay más de
              // una, así que solo aparece entonces.
              if (!group.isSingle)
                _DetachButton(group: group, onDetach: onDetach),
              IconButton(
                key: const Key('pdf-recompile'),
                tooltip: 'Volver a compilar',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: onRecompile,
              ),
              // Los dos caminos externos, que siguen haciendo falta: pantalla
              // completa para pasar diapositivas, y el Finder para arrastrar
              // el PDF a un correo. Con varios paneles preguntan cuál.
              _ExternalButtons(
                group: group,
                narrow: narrow,
                onOpenExternally: onOpenExternally,
                onReveal: onReveal,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Sacar una versión a su propia pestaña.
///
/// Con dos paneles no pregunta: separarlos es la única cosa que se puede
/// querer, y un menú de una opción es un clic de más. Con tres o más sí,
/// porque entonces «separar» no dice cuál.
class _DetachButton extends StatelessWidget {
  const _DetachButton({required this.group, required this.onDetach});

  final PdfGroup group;
  final ValueChanged<String> onDetach;

  @override
  Widget build(BuildContext context) {
    if (group.panes.length == 2) {
      return IconButton(
        key: const Key('pdf-detach'),
        tooltip: 'Separar ${group.panes.last.language} en otra pestaña',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.call_split, size: 17),
        onPressed: () => onDetach(group.panes.last.language),
      );
    }
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        key: const Key('pdf-detach'),
        tooltip: 'Separar una versión en otra pestaña',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.call_split, size: 17),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final pane in group.panes)
          MenuItemButton(
            key: Key('detach-${pane.language}'),
            onPressed: () => onDetach(pane.language),
            child: Text('Separar ${pane.language}'),
          ),
      ],
    );
  }
}

class _ExternalButtons extends StatelessWidget {
  const _ExternalButtons({
    required this.group,
    required this.narrow,
    required this.onOpenExternally,
    required this.onReveal,
  });

  final PdfGroup group;
  final bool narrow;
  final ValueChanged<String> onOpenExternally;
  final ValueChanged<String> onReveal;

  @override
  Widget build(BuildContext context) {
    // Con varios paneles hay que preguntar cuál, así que siempre es un menú
    // en ese caso; con uno solo, dos botones directos.
    if (narrow || !group.isSingle) {
      return MenuAnchor(
        builder: (context, controller, child) => IconButton(
          key: const Key('pdf-more'),
          tooltip: 'Abrir fuera',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.more_horiz, size: 18),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: [
          for (final pane in group.panes)
            MenuItemButton(
              leadingIcon: const Icon(Icons.open_in_new, size: 15),
              onPressed: () => onOpenExternally(pane.path),
              child: Text(
                group.isSingle
                    ? 'Abrir en el visor del sistema'
                    : 'Abrir ${pane.language} en el visor del sistema',
              ),
            ),
          const Divider(height: 1),
          for (final pane in group.panes)
            MenuItemButton(
              leadingIcon: const Icon(Icons.folder_open_outlined, size: 15),
              onPressed: () => onReveal(pane.path),
              child: Text(
                group.isSingle
                    ? 'Ver en el Finder'
                    : 'Ver ${pane.language} en el Finder',
              ),
            ),
        ],
      );
    }
    final only = group.panes.single;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('pdf-external'),
          tooltip: 'Abrir en el visor del sistema (pantalla completa)',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.open_in_new, size: 17),
          onPressed: () => onOpenExternally(only.path),
        ),
        IconButton(
          key: const Key('pdf-reveal'),
          tooltip: 'Ver en el Finder',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.folder_open_outlined, size: 17),
          onPressed: () => onReveal(only.path),
        ),
      ],
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
