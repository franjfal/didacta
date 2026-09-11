/// Los PDF compilados, abiertos dentro de la aplicación.
///
/// Antes esto salía al visor del sistema, y estaba mal por una razón que se ve
/// en cuanto se usa: comparar «cómo queda en diapositivas» con «cómo queda en
/// libro», o el castellano con el valenciano, es mirar dos cosas a la vez, y
/// salir a otra aplicación para cada una rompe justo eso. Ahora cada salida es
/// una pestaña más, al lado de los idiomas y de `unit.yaml`, y los idiomas de
/// un mismo perfil van en la misma pestaña, lado a lado.
///
/// **Las acciones sobre un PDF viven en su panel.** Con dos PDF a la vez,
/// «abrir en el visor» en la barra de la pestaña no dice cuál, y resolverlo
/// con un menú que pregunta es un clic de más para contestar algo que el
/// sitio del botón ya contesta. En la barra queda lo que vale para toda la
/// pestaña: pasar página en los dos paneles a la vez, separar una versión, y
/// elegir otras.
///
/// El visor del sistema **sigue estando**, en cada panel. No es redundancia:
/// tiene pantalla completa para pasar diapositivas de verdad, y el Finder es
/// desde donde se arrastra un PDF a un correo. Lo que se quita es la
/// obligación de salir para verlo.
library;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/compiler.dart';
import 'theme.dart';

/// Un PDF abierto: qué es, y de dónde salió.
class OpenPdf {
  const OpenPdf({
    required this.path,
    required this.profile,
    required this.language,
    required this.pages,
    this.revision = 0,
    this.busy = false,
    this.stale = false,
  });

  final String path;
  final String profile;
  final String language;
  final int pages;

  /// Sube al recompilar. Va en la clave del visor porque la ruta no cambia
  /// --el mismo perfil y el mismo idioma escriben el mismo fichero-- y sin
  /// esto el visor seguiría enseñando el PDF de antes.
  final int revision;

  /// Mientras se recompila este panel, y no los demás.
  final bool busy;

  /// El origen se tocó después de compilar esto.
  ///
  /// Se marca en la pestaña y en el panel, en ámbar y discreto: lo que se
  /// está mirando sigue siendo un PDF de verdad --no es un error-- pero ya
  /// no es lo que dice el fichero, y eso hay que saberlo antes de
  /// proyectarlo en una clase.
  final bool stale;

  String get label => '$profile · $language';

  /// El mismo panel, recién compilado: nueva revisión y ya no ocupado.
  OpenPdf refreshed({int? pages}) => OpenPdf(
    path: path,
    profile: profile,
    language: language,
    pages: pages ?? this.pages,
    revision: revision + 1,
  );

  OpenPdf working() => OpenPdf(
    path: path,
    profile: profile,
    language: language,
    pages: pages,
    revision: revision,
    busy: true,
    stale: stale,
  );

  OpenPdf idle() => OpenPdf(
    path: path,
    profile: profile,
    language: language,
    pages: pages,
    revision: revision,
    stale: stale,
  );

  /// El mismo panel, con el aviso de viejo puesto o quitado.
  OpenPdf marked({required bool stale}) => OpenPdf(
    path: path,
    profile: profile,
    language: language,
    pages: pages,
    revision: revision,
    busy: busy,
    stale: stale,
  );
}

/// Una pestaña: uno o varios PDF, lado a lado.
///
/// Varios porque la comparación que importa es la del mismo perfil en dos
/// idiomas: si la traducción valenciana sigue cabiendo en la diapositiva no se
/// puede saber sin las dos delante. Así que al compilar dos idiomas de un
/// perfil se abren juntos, y se pueden separar de un botón.
class PdfGroup {
  const PdfGroup({required this.id, required this.panes});

  /// La identidad de la pestaña. El perfil cuando el grupo salió de compilar;
  /// perfil e idioma cuando alguien lo desacopló, para que la versión
  /// separada no vuelva a caer en el grupo.
  final String id;

  final List<OpenPdf> panes;

  bool get isSingle => panes.length == 1;

  /// Si alguna de las versiones abiertas se ha quedado vieja. Es lo que
  /// marca la pestaña.
  bool get hasStale => panes.any((pane) => pane.stale);

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

  OpenPdf? pane(String language) {
    for (final pane in panes) {
      if (pane.language == language) return pane;
    }
    return null;
  }

  /// El mismo grupo con un panel sustituido, para recompilar uno solo.
  PdfGroup replacing(OpenPdf pane) => PdfGroup(
    id: id,
    panes: [
      for (final other in panes)
        if (other.language == pane.language) pane else other,
    ],
  );

  PdfGroup without(String language) => PdfGroup(
    id: id,
    panes: [
      for (final pane in panes)
        if (pane.language != language) pane,
    ],
  );
}

/// Los resultados de una compilación, repartidos en pestañas.
///
/// Una pestaña por versión y dentro un panel por idioma. Es la regla que
/// hace útil compilar dos idiomas a la vez: lo que se compara es la misma
/// diapositiva en castellano y en valenciano, lado a lado, y no dos pestañas
/// entre las que hay que alternar.
///
/// Compartida entre la unidad y el tema porque es la misma regla: cambiarla
/// en un sitio y no en el otro daría dos comportamientos para el mismo
/// gesto.
List<PdfGroup> groupResults(List<CompileOutput> results) {
  final byProfile = <String, List<OpenPdf>>{};
  for (final result in results) {
    if (!result.ok || result.pdf == null) continue;
    byProfile
        .putIfAbsent(result.profile, () => [])
        .add(
          OpenPdf(
            path: result.pdf!,
            profile: result.profile,
            language: result.language,
            pages: result.pages,
          ),
        );
  }
  return [
    for (final entry in byProfile.entries)
      PdfGroup(id: entry.key, panes: entry.value),
  ];
}

class PdfTabView extends StatefulWidget {
  const PdfTabView({
    super.key,
    required this.group,
    required this.onOpenExternally,
    required this.onReveal,
    required this.onRecompile,
    required this.onRecompilePane,
    required this.onDetach,
  });

  final PdfGroup group;

  /// El visor del sistema: pantalla completa para pasar diapositivas.
  final ValueChanged<String> onOpenExternally;

  /// El Finder: desde donde se arrastra un PDF a un correo.
  final ValueChanged<String> onReveal;

  /// Ir a la pantalla de compilar, para elegir otras versiones.
  final VoidCallback onRecompile;

  /// Volver a compilar **este** panel, en su sitio.
  ///
  /// Es la acción de después de editar: cambias el valenciano, lo recompilas
  /// y se actualiza esa columna sin tocar la de al lado, que es lo que
  /// permite ver el cambio.
  final ValueChanged<String> onRecompilePane;

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
    setState(() {
      _pages[path] = pages;
      // Un PDF que abre bien deja de tener el problema de antes: tras
      // recompilar, el error de «no existe» ya no vale.
      _problem.remove(path);
    });
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

  int get _total => _pages[widget.group.panes.first.path] ?? widget.group.pages;

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
          onRecompile: widget.onRecompile,
          onDetach: widget.onDetach,
        ),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < panes.length; i += 1) ...[
                if (i > 0) const VerticalDivider(width: 1),
                Expanded(
                  child: _Pane(
                    pane: panes[i],
                    parent: this,
                    onOpenExternally: () =>
                        widget.onOpenExternally(panes[i].path),
                    onReveal: () => widget.onReveal(panes[i].path),
                    onRecompile: () =>
                        widget.onRecompilePane(panes[i].language),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Un panel: un PDF, con su idioma y sus acciones encima.
///
/// Los botones van aquí y no en la barra de la pestaña, y esa es la
/// corrección importante: con dos PDF a la vez, «abrir en el visor» en la
/// barra no dice cuál.
///
/// El idioma se rotula siempre, incluso con un solo panel: dos capturas de la
/// misma diapositiva en dos idiomas son indistinguibles si el texto no se lee,
/// y el rótulo es lo que las distingue.
class _Pane extends StatelessWidget {
  const _Pane({
    required this.pane,
    required this.parent,
    required this.onOpenExternally,
    required this.onReveal,
    required this.onRecompile,
  });

  final OpenPdf pane;
  final _PdfTabViewState parent;
  final VoidCallback onOpenExternally;
  final VoidCallback onReveal;
  final VoidCallback onRecompile;

  @override
  Widget build(BuildContext context) {
    final problem = parent.problemOf(pane);
    final total = parent.pagesOf(pane);
    final page = parent.pageOf(pane);

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: didactaPanel,
            border: Border(bottom: BorderSide(color: didactaRule)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 1, 2, 1),
          child: Row(
            children: [
              Text(
                pane.language,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: didactaAccentDark,
                ),
              ),
              if (pane.stale) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      'La unidad ha cambiado después de compilar esto. Lo que '
                      'se ve es de antes del cambio.',
                  child: Icon(
                    Icons.change_circle_outlined,
                    size: 15,
                    color: didactaEx,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pane.busy
                      ? 'compilando…'
                      : pane.stale
                      ? 'modificada después · $page / $total'
                      : '$page / $total',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: pane.stale ? didactaEx : didactaMuted,
                    fontWeight: pane.stale ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                key: Key('pane-recompile-${pane.language}'),
                tooltip: 'Volver a compilar ${pane.language}',
                visualDensity: VisualDensity.compact,
                icon: pane.busy
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                onPressed: pane.busy ? null : onRecompile,
              ),
              IconButton(
                key: Key('pane-external-${pane.language}'),
                tooltip:
                    'Abrir ${pane.language} en el visor del sistema '
                    '(pantalla completa)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new, size: 15),
                onPressed: onOpenExternally,
              ),
              IconButton(
                key: Key('pane-reveal-${pane.language}'),
                tooltip: 'Ver ${pane.language} en el Finder',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.folder_open_outlined, size: 15),
                onPressed: onReveal,
              ),
            ],
          ),
        ),
        Expanded(
          child: problem != null
              ? _Failure(path: pane.path, problem: problem)
              : ColoredBox(
                  // Gris y no blanco: un PDF blanco sobre blanco no tiene
                  // bordes, y en diapositivas el borde es donde se ve si algo
                  // se sale de la caja.
                  color: const Color(0xFF52565C),
                  child: PdfViewer.file(
                    pane.path,
                    // La revisión en la clave: recompilar escribe el mismo
                    // fichero, así que sin esto el visor seguiría enseñando
                    // el PDF de antes.
                    key: ValueKey('${pane.path}#${pane.revision}'),
                    controller: parent._controllerFor(pane.path),
                    params: PdfViewerParams(
                      margin: 8,
                      backgroundColor: const Color(0xFF52565C),
                      onViewerReady: (document, controller) =>
                          parent._noteReady(pane.path, document.pages.length),
                      onPageChanged: (page) {
                        if (page != null) parent._notePage(pane.path, page);
                      },
                      errorBannerBuilder:
                          (context, error, stackTrace, documentRef) {
                            // Después del frame: esto se llama durante el
                            // build del visor, y un setState ahí no está
                            // permitido.
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
    required this.onRecompile,
    required this.onDetach,
  });

  final PdfGroup group;
  final int page;
  final int pages;
  final VoidCallback? onFirst;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onRecompile;
  final ValueChanged<String> onDetach;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: didactaSurface,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // Aquí van las acciones que valen para toda la pestaña: pasar página en
      // los dos paneles a la vez, separar, y elegir otras versiones. Lo que
      // se hace a *un* PDF va en su panel, donde no hay que preguntar cuál.
      child: Row(
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
                  : '${group.panes.length} versiones · las páginas se mueven '
                        'juntas',
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              textDirection: group.isSingle
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
          ),
          // Separar una versión: solo tiene sentido cuando hay más de una.
          if (!group.isSingle) _DetachButton(group: group, onDetach: onDetach),
          IconButton(
            key: const Key('pdf-recompile'),
            tooltip: 'Elegir otras versiones',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.tune, size: 17),
            onPressed: onRecompile,
          ),
        ],
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

class _Failure extends StatelessWidget {
  const _Failure({required this.path, required this.problem});

  final String path;
  final Object problem;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se ha podido abrir el PDF',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
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
              'Vuelve a compilar con el botón de arriba.',
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
