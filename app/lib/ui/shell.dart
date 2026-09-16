/// The frame every screen sits in.
///
/// A navigation rail on anything wide enough and a bottom bar below that. The
/// rail carries live counts -- how many units need translating, how many
/// documents there are -- because a number in the navigation is the cheapest
/// way to answer "is there anything waiting for me" without opening the page.
///
/// It also carries the one piece of state that has to be visible from
/// everywhere: **how content is being reached, and as whom.** Where a change
/// will go should never be a mystery, so it is in the frame rather than buried
/// in a settings screen.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/content_gateway.dart';
import '../router.dart';
import '../state/mcp_service.dart';
import '../state/session.dart';
import 'brand.dart';
import 'sync_bar.dart';
import 'theme.dart';

class DidactaShell extends StatelessWidget {
  const DidactaShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  /// El orden del carril.
  ///
  /// Asignaturas primero, y no la biblioteca: es donde se trabaja. La
  /// biblioteca son dos mil unidades ordenadas por materia, que es cómo se
  /// busca material; una asignatura es lo que se está dando este cuatrimestre,
  /// que es lo que se abre cada día.
  /// El carril, contando si el servidor MCP está encendido.
  ///
  /// Condicional y no siempre presente: apagado no hay nada que mirar --ni
  /// actividad, ni dirección a la que conectarse-- y un icono que lleva a una
  /// pantalla vacía es una pestaña que se aprende a ignorar. Encendido sí,
  /// porque entonces hay un programa escribiendo en tus ficheros y tiene que
  /// estar a un clic.
  static List<_Destination> _destinationsWith({required bool mcp}) => [
    ..._always.sublist(0, _always.length - 1),
    if (mcp)
      const _Destination(
        '/mcp',
        Icons.hub_outlined,
        Icons.hub,
        'Servidor',
      ),
    _always.last,
  ];

  static const List<_Destination> _always = [
    _Destination(
      '/courses',
      Icons.school_outlined,
      Icons.school,
      'Asignaturas',
    ),
    _Destination(
      '/',
      Icons.library_books_outlined,
      Icons.library_books,
      'Biblioteca',
    ),
    _Destination(
      '/translations',
      Icons.translate_outlined,
      Icons.translate,
      'Traducción',
    ),
    _Destination(
      '/settings',
      Icons.settings_outlined,
      Icons.settings,
      'Ajustes',
    ),
  ];

  /// Which destination the current URL belongs to.
  ///
  /// Prefix-matched so `/unit/...` keeps the library selected and
  /// `/courses/am-iii/2025-2026` keeps Asignaturas selected -- a rail that
  /// deselects everything when you open a detail leaves the reader unsure
  /// where they are.
  ///
  /// Por posición en [_destinations] y no con números escritos a mano: eran
  /// cuatro constantes que había que acordarse de cambiar al reordenar el
  /// carril, y olvidarse deja la sección marcada en el sitio equivocado.
  int _indexIn(List<_Destination> destinations) {
    for (final (index, destination) in destinations.indexed) {
      if (destination.path == '/') continue;
      if (location.startsWith(destination.path)) return index;
    }
    return destinations.indexWhere((destination) => destination.path == '/');
  }

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    // `watch` y no `read`: encender el servidor tiene que hacer aparecer el
    // icono sin cambiar de pantalla. Si no está el proveedor --un test que
    // monta el armazón suelto-- el carril es el de siempre.
    final mcp = context.watch<McpService?>();
    final destinations = _destinationsWith(mcp: mcp?.running ?? false);
    final index = _indexIn(destinations);

    // Anotado después del fotograma: cambiar el historial avisa a quien lo
    // escucha, y avisar mientras se construye es un `setState` en mitad de
    // un build.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => session.history.record(location),
    );

    return _Shortcuts(
      session: session,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          final pending = session.catalogueOrNull == null
              ? 0
              : session.needingTranslation(session.language).length;

          if (!wide) {
            return Scaffold(
              body: Column(
                children: [
                  SyncBar(session: session),
                  Expanded(child: child),
                  const Divider(height: 1),
                  _GatewayStrip(gateway: session.gateway),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                elevation: 0,
                height: 58,
                backgroundColor: didactaPanel,
                selectedIndex: index,
                onDestinationSelected: (at) =>
                    context.go(destinations[at].path),
                destinations: [
                  for (final destination in destinations)
                    NavigationDestination(
                      icon: Icon(destination.icon, size: 20),
                      selectedIcon: Icon(destination.selectedIcon, size: 20),
                      label: destination.label,
                    ),
                ],
              ),
            );
          }

          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (at) =>
                      context.go(destinations[at].path),
                  // Un poco más ancho que el mínimo de Material: las etiquetas
                  // («Asignaturas», «Traducción») llegaban al borde y el
                  // carril se leía apretado al lado de una página con aire.
                  minWidth: 76,
                  groupAlignment: -0.92,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 14, bottom: 10),
                    child: _Mark(),
                  ),
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.label == 'Traducción' && pending > 0
                            ? Badge(
                                // The number, not a dot: "how much is waiting"
                                // is the question, and a dot cannot answer it.
                                //
                                // Arriba a la derecha y en pequeño: centrado
                                // sobre el glifo, un «2147» tapaba el icono y
                                // el naranja chillaba más que la navegación
                                // entera.
                                // Con tope: «2147» es una etiqueta de cuatro
                                // cifras encima de un icono de 20 px, y además
                                // no dice nada que «+99» no diga. El número
                                // exacto está en la pantalla de traducción.
                                label: Text(pending > 99 ? '+99' : '$pending'),
                                alignment: const Alignment(1.9, -1.2),
                                // Ámbar apagado y no naranja fuerte: dice
                                // «queda trabajo», no «algo ha fallado», y en
                                // un carril de cuatro iconos era lo que más
                                // llamaba de toda la aplicación.
                                backgroundColor: const Color(0xFFC08A3E),
                                textStyle: const TextStyle(
                                  fontSize: 9,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Icon(destination.icon),
                              )
                            : Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      SyncBar(session: session),
                      Expanded(child: child),
                      const Divider(height: 1),
                      _GatewayStrip(gateway: session.gateway),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Atrás y adelante desde el teclado y desde el ratón.
///
/// Los tres gestos que la gente ya tiene en los dedos: ⌘[ y ⌘] --lo que usa
/// todo macOS--, Alt+flechas para quien viene de Windows o Linux, y los
/// botones laterales del ratón, que en una aplicación de escritorio se
/// prueban sin pensar.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.session, required this.child});

  final Session session;
  final Widget child;

  void _back(BuildContext context) {
    final target = session.history.back();
    if (target != null) context.go(target);
  }

  void _forward(BuildContext context) {
    final target = session.history.forward();
    if (target != null) context.go(target);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): () =>
          _back(context),
      const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): () =>
          _forward(context),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
          _back(context),
      const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
          _forward(context),
    },
    child: Focus(
      autofocus: true,
      child: Listener(
        onPointerDown: (event) {
          // Los botones 4 y 5 del ratón. `kBackMouseButton` es el de atrás
          // en cualquier plataforma.
          if (event.buttons & kBackMouseButton != 0) _back(context);
          if (event.buttons & kForwardMouseButton != 0) _forward(context);
        },
        child: child,
      ),
    ),
  );
}

/// Atrás y adelante, donde están las migas de pan.
///
/// Ahí y no en una barra propia porque es la misma pregunta --dónde estoy y
/// cómo vuelvo-- y porque una fila más de cromo en cada pantalla se paga en
/// alto útil. «Atrás» apagado cuando no hay a dónde, y «adelante» escondido
/// del todo mientras no se haya vuelto: un botón que nunca se enciende es
/// ruido.
class BackForward extends StatelessWidget {
  const BackForward({super.key});

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final history = session.history;
    return AnimatedBuilder(
      animation: history,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('go-back'),
            tooltip: history.canGoBack ? 'Atrás  ⌘[' : 'No hay a dónde volver',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_back, size: 16),
            onPressed: history.canGoBack
                ? () {
                    final target = history.back();
                    if (target != null) context.go(target);
                  }
                : null,
          ),
          if (history.canGoForward)
            IconButton(
              key: const Key('go-forward'),
              tooltip: 'Adelante  ⌘]',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_forward, size: 16),
              onPressed: () {
                final target = history.forward();
                if (target != null) context.go(target);
              },
            ),
        ],
      ),
    );
  }
}

/// Una miga de pan: gris hasta que el ratón pasa por encima.
///
/// Antes eran azules y en cada pantalla. Un enlace que se sabe que es un
/// enlace en cuanto se apunta no necesita gritarlo todo el rato, y así lo
/// más llamativo de la cabecera vuelve a ser el título.
class _Crumb extends StatefulWidget {
  const _Crumb({required this.label, required this.route});

  final String label;
  final String route;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _over = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _over = true),
    onExit: (_) => setState(() => _over = false),
    child: GestureDetector(
      onTap: () => context.go(widget.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            color: _over ? didactaAccentDark : didactaMuted,
            decoration: _over ? TextDecoration.underline : null,
            decorationColor: didactaAccentDark,
          ),
        ),
      ),
    ),
  );
}

class _Destination {
  const _Destination(this.path, this.icon, this.selectedIcon, this.label);

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'Didacta',
    // La misma marca que el icono de la aplicación, del mismo código: un
    // logo dibujado aparte se separa del icono en el primer retoque.
    child: DidactaMark(),
  );
}

/// One line saying where a change would go, and as whom.
///
/// Always present. The alternative -- surfacing it only when something fails
/// -- means the first time anyone learns they are in read-only mode is when
/// they lose an edit.
class _GatewayStrip extends StatefulWidget {
  const _GatewayStrip({required this.gateway});

  final ContentGateway gateway;

  @override
  State<_GatewayStrip> createState() => _GatewayStripState();
}

class _GatewayStripState extends State<_GatewayStrip> {
  bool _busy = false;

  Future<void> _refresh(Session session) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.refreshEverything();
      final behind = session.behind ?? 0;
      final problem = session.remoteProblem;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            behind > 0
                ? 'Actualizado. En GitHub hay $behind '
                      '${behind == 1 ? 'commit' : 'commits'} que no están aquí.'
                : problem != null
                ? 'Actualizado desde el disco. No se pudo preguntar a '
                      'GitHub: $problem'
                : 'Actualizado. Nada nuevo en GitHub.',
          ),
          duration: Duration(seconds: behind > 0 || problem != null ? 8 : 3),
          // Traerlo es otra decisión, y por eso es otro botón: un `pull`
          // cambia los ficheros de debajo de quien está editando.
          action: behind > 0
              ? SnackBarAction(
                  label: 'Traerlos',
                  onPressed: () => _pull(session),
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pull(Session session) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.pullAll();
      await session.refreshEverything();
      messenger.showSnackBar(
        const SnackBar(content: Text('Traído de GitHub y actualizado.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 10),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gateway = widget.gateway;
    // Leída aquí y no dentro del `onPressed`: `watch` solo vale mientras se
    // construye, y llamarlo desde una pulsación lanza --y el botón no hacía
    // nada sin decir por qué.
    final session = watchSession(context);
    final (icon, colour) = switch (gateway.kind) {
      GatewayKind.clone => (Icons.folder_open_outlined, didactaAccentDark),
      GatewayKind.none => (Icons.lock_outline, didactaMuted),
    };

    return Material(
      color: didactaPanel,
      child: InkWell(
        onTap: () => context.go(Routes.settings()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: colour),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  gateway.describe(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
              ),
              if (!gateway.canWrite)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: didactaRule),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'solo lectura',
                    style: TextStyle(fontSize: 10.5, color: didactaMuted),
                  ),
                ),
              // Actualizar, aquí, porque esta barra es lo que dice de dónde
              // sale lo que se está viendo: el sitio donde se pregunta «¿esto
              // es lo que hay en el disco?» es el mismo donde se contesta.
              if (session.canCompile)
                SizedBox(
                  width: 26,
                  height: 26,
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          key: const Key('refresh-everything'),
                          tooltip:
                              'Actualizar: releer el disco, regenerar el '
                              'índice y mirar si hay algo nuevo en GitHub'
                              '  ⌘R',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.refresh, size: 15),
                          onPressed: () => _refresh(session),
                        ),
                ),
              // Lo que espera en GitHub, en la misma barra que dice de dónde
              // sale el contenido. Un número y no un punto: «hay tres
              // commits» dice si merece la pena pararse ahora.
              if ((session.behind ?? 0) > 0)
                Hoverable(
                  key: const Key('pull-pending'),
                  onTap: () => _pull(session),
                  builder: (context, hovering) => Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: hovering
                          ? didactaThm.withValues(alpha: 0.18)
                          : didactaThm.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(Radii.small),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.south_outlined,
                          size: 12,
                          color: didactaThm,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${session.behind} en GitHub',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: didactaThm,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page header, used by every screen so they line up.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.breadcrumbs = const [],
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String? subtitle;

  /// `(label, route)` pairs. A detail screen is reached by a link, so getting
  /// back up has to be a link too and not just the browser's back button.
  final List<(String, String)> breadcrumbs;

  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Blanca sobre la página gris, en lugar de una raya debajo: la
      // cabecera se separa del contenido por el tono y no por una línea
      // más, que es lo que hacía que cada pantalla pareciera un formulario.
      decoration: const BoxDecoration(
        color: didactaCard,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const BackForward(),
                if (breadcrumbs.isNotEmpty) const SizedBox(width: 4),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (index, crumb) in breadcrumbs.indexed) ...[
                        _Crumb(label: crumb.$1, route: crumb.$2),
                        if (index < breadcrumbs.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(
                              Icons.chevron_right,
                              size: 14,
                              color: didactaRule,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: didactaMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (bottom != null) bottom! else const SizedBox(height: 14),
        ],
      ),
    );
  }
}
