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

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/browser.dart';
import '../data/content_gateway.dart';
import '../data/frozen.dart';
import '../model/catalogue.dart';
import '../router.dart';
import '../state/mcp_service.dart';
import '../state/appearance.dart';
import '../state/session.dart';
import 'brand.dart';
import 'build_strip.dart';
import 'command_palette.dart';
import 'freezes.dart';
import 'platform_menus.dart';
import 'problem.dart';
import 'shortcuts.dart';
import 'sync_bar.dart';
import 'theme.dart';
import 'tour.dart';
import '../l10n/tr.dart';

class DidactaShell extends StatelessWidget {
  const DidactaShell({
    super.key,
    required this.location,
    this.url,
    required this.child,
  });

  /// La ruta, sin la parte `?…`: es lo que decide qué sección del carril
  /// está marcada.
  final String location;

  /// La dirección entera, con su `?…`: es lo que se apunta en el historial.
  /// Con la ruta sola, «atrás» volvía a Ajustes pero no a la sección de
  /// Ajustes en la que se estaba, ni a una lección en el idioma que se
  /// miraba. Null es lo mismo que [location].
  final String? url;

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
  static List<_Destination> _destinationsWith({
    required bool between,
    required bool mcp,
  }) => [
    ..._always.sublist(0, _always.length - 1),
    // Solo con varios repositorios abiertos: con uno no hay nada que cruzar,
    // y las dos comprobaciones que lleva --metadatos que discrepan y
    // documentos que llaman fuera-- no pueden dar nada. Un apartado que
    // siempre dice «todo cuadra» es un apartado que se deja de abrir.
    if (between)
      _Destination(
        '/between',
        Icons.compare_arrows_outlined,
        Icons.compare_arrows,
        tr('Entre repos'),
      ),
    if (mcp)
      _Destination('/mcp', Icons.hub_outlined, Icons.hub, tr('Servidor')),
    _always.last,
  ];

  static List<_Destination> get _always => [
    _Destination(
      '/courses',
      Icons.school_outlined,
      Icons.school,
      tr('Asignaturas'),
    ),
    _Destination(
      '/',
      Icons.library_books_outlined,
      Icons.library_books,
      tr('Biblioteca'),
    ),
    _Destination(
      '/translations',
      Icons.translate_outlined,
      Icons.translate,
      tr('Traducción'),
    ),
    _Destination(
      '/settings',
      Icons.settings_outlined,
      Icons.settings,
      tr('Ajustes'),
    ),
  ];

  /// Envuelve el icono de un destino si el tour habla de él.
  ///
  /// Solo los dos que el recorrido explica desde el carril --la biblioteca y
  /// las asignaturas tienen capítulo propio, dentro de su pantalla--: marcar
  /// los seis dejaría claves registradas que no usa nadie, y una clave global
  /// por icono no es gratis.
  static Widget _tourable(_Destination destination, Widget icon) =>
      switch (destination.path) {
        '/translations' => TourTarget(id: 'rail-translations', child: icon),
        '/settings' => TourTarget(id: 'rail-settings', child: icon),
        _ => icon,
      };

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

  // Con la interfaz Completa, «Entre repos» se ve siempre.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final session = watchSession(context);
    // `watch` y no `read`: encender el servidor tiene que hacer aparecer el
    // icono sin cambiar de pantalla. Si no está el proveedor --un test que
    // monta el armazón suelto-- el carril es el de siempre.
    final mcp = context.watch<McpService?>();
    final destinations = _destinationsWith(
      // Con la interfaz Esencial, solo si hay algo que mirar: casi siempre
      // dice «todo cuadra», y así el día que no, se ve. Y mientras se está
      // en ella, aunque se acabe de arreglar lo último.
      between:
          session.workspace.isMultiple &&
          (session.completeInterface ||
              session.betweenReposNeedsLooking ||
              location.startsWith('/between')),
      mcp: mcp?.running ?? false,
    );
    final index = _indexIn(destinations);

    // Anotado después del fotograma: cambiar el historial avisa a quien lo
    // escucha, y avisar mientras se construye es un `setState` en mitad de
    // un build.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => session.history.record(url ?? location),
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
                  FrozenBar(session: session),
                  SyncBar(session: session),
                  Expanded(child: child),
                  BuildStrip(session: session),
                  const Divider(height: 1),
                  _GatewayStrip(gateway: session.gateway),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                elevation: 0,
                height: 58,
                backgroundColor: context.palette.panel,
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
                // Marcado para el tour: el carril entero y, dentro, los tres
                // destinos que el recorrido explica uno a uno. Envolver el
                // icono y no la `NavigationRailDestination` porque lo que
                // Material pinta --y lo que hay que rodear con el foco-- es
                // el icono.
                TourTarget(
                  id: 'rail',
                  child: NavigationRail(
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
                    // Abajo del todo, lejos de los destinos: se toca una vez
                    // al día, y al lado de ellos se pulsaría por error.
                    trailingAtBottom: true,
                    trailing: const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: AppearanceToggle(),
                    ),
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: _tourable(
                            destination,
                            destination.path == '/translations' && pending > 0
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
                                    label: Text(
                                      pending > 99 ? '+99' : '$pending',
                                    ),
                                    alignment: const Alignment(1.9, -1.2),
                                    // Ámbar apagado y no naranja fuerte: dice
                                    // «queda trabajo», no «algo ha fallado», y en
                                    // un carril de cuatro iconos era lo que más
                                    // llamaba de toda la aplicación.
                                    backgroundColor: context.palette.pending,
                                    textStyle: TextStyle(
                                      fontSize: 9,
                                      height: 1.1,
                                      fontWeight: FontWeight.w600,
                                      color: context.palette.onPending,
                                    ),
                                    textColor: context.palette.onPending,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Icon(destination.icon),
                                  )
                                : Icon(destination.icon),
                          ),
                          // También el seleccionado, y no es un detalle: el
                          // carril enseña `selectedIcon` para la sección en
                          // la que estás, así que sin marcar este el tour no
                          // puede señalar justamente donde te encuentras
                          // --que es la mitad de las veces--.
                          selectedIcon: _tourable(
                            destination,
                            Icon(destination.selectedIcon),
                          ),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      FrozenBar(session: session),
                      TourTarget(
                        id: 'sync',
                        child: SyncBar(session: session),
                      ),
                      Expanded(child: child),
                      // Lo que se compila, en todas las pantallas: cerrar la
                      // consola no para nada, y sin esto no se sabía.
                      BuildStrip(session: session),
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
/// La banda que dice que lo que se está mirando es una versión congelada.
///
/// Arriba del todo y en todas las pantallas, no en una sola: abrir una
/// congelación cambia el catálogo entero, así que la biblioteca, las
/// asignaturas y el editor enseñan el material de aquel día. Sin una banda
/// permanente, «¿por qué no está el tema que añadí ayer?» no tiene respuesta
/// visible.
///
/// De un color distinto al resto a propósito. No es un aviso de error --no
/// hay nada roto-- sino un cambio de contexto, y lo que tiene que hacer es
/// que sea imposible olvidarlo.
class FrozenBar extends StatelessWidget {
  const FrozenBar({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final frozen = session.frozen;
    if (frozen == null) return const SizedBox.shrink();
    return Material(
      color: context.palette.thm.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
        child: Row(
          children: [
            Icon(Icons.ac_unit, size: 15, color: context.palette.thm),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(
                  'Estás viendo «{0}»'
                  '{1}'
                  ' · {2}'
                  '{3}'
                  '. Es una versión congelada: se mira, no se edita.',
                  [
                    frozen.freeze.name,
                    frozen.freeze.year.isEmpty
                        ? ''
                        : ' · ${frozen.freeze.year}',
                    frozen.freeze.shortCommit,
                    frozen.rebuilt ? tr(' · catálogo reconstruido') : '',
                  ],
                ),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            // Lo que se puede hacer desde aquí. Tres cosas y no una:
            // impedir la edición sin ofrecer salida deja a alguien mirando
            // una foto sin forma de usarla.
            MenuAnchor(
              builder: (context, controller, child) => TextButton.icon(
                key: const Key('frozen-actions'),
                icon: const Icon(Icons.more_horiz, size: 15),
                label: Text(tr('Qué puedo hacer')),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  key: const Key('frozen-restore-course'),
                  leadingIcon: const Icon(Icons.restore, size: 15),
                  onPressed: () => _restoreCourse(context, session, frozen),
                  child: Text(tr('Restaurar este curso desde aquí…')),
                ),
                MenuItemButton(
                  key: const Key('frozen-new-year'),
                  leadingIcon: const Icon(Icons.add, size: 15),
                  onPressed: () => _yearFromHere(context, session, frozen),
                  child: Text(tr('Crear un curso desde aquí…')),
                ),
              ],
            ),
            TextButton(
              key: const Key('leave-freeze'),
              onPressed: session.leaveFreeze,
              child: Text(tr('Volver a la versión actual')),
            ),
          ],
        ),
      ),
    );
  }
}

Course? _courseOf(Session session, FrozenView frozen) {
  for (final course in session.catalogue.courses) {
    if (course.id == frozen.freeze.course) return course;
  }
  return null;
}

Future<void> _restoreCourse(
  BuildContext context,
  Session session,
  FrozenView frozen,
) async {
  final course = _courseOf(session, frozen);
  if (course == null) return;
  await showRestore(
    context,
    session: session,
    course: course,
    year: frozen.freeze.year,
    freeze: frozen.freeze,
  );
}

Future<void> _yearFromHere(
  BuildContext context,
  Session session,
  FrozenView frozen,
) async {
  final course = _courseOf(session, frozen);
  if (course == null) return;
  await showYearFromFreeze(context, session, course, frozen.freeze);
}

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

  /// El tamaño del texto, desde el teclado.
  void _textSize(Appearance appearance, AppShortcut shortcut) =>
      unawaited(switch (shortcut) {
        AppShortcut.biggerText => appearance.biggerText(),
        AppShortcut.smallerText => appearance.smallerText(),
        _ => appearance.normalText(),
      });

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      // El tamaño del texto: las teclas de más --el «+» de otros teclados, el
      // teclado numérico-- en todos los sistemas, y las de la tabla donde no
      // las atiende la barra de menú.
      if (context.read<Appearance?>() case final appearance?)
        for (final shortcut in const [
          AppShortcut.biggerText,
          AppShortcut.smallerText,
          AppShortcut.normalText,
        ]) ...{
          if (!PlatformMenus.supported)
            activatorFor(shortcut): () => _textSize(appearance, shortcut),
          for (final also in alsoFor(shortcut))
            also: () => _textSize(appearance, shortcut),
        },
      // La paleta, en todos los sistemas: en macOS la barra de menú la
      // tiene también, y es la que atiende el atajo.
      activatorFor(AppShortcut.palette): () =>
          unawaited(showCommandPalette(context)),
      activatorFor(AppShortcut.back): () => _back(context),
      activatorFor(AppShortcut.forward): () => _forward(context),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
          _back(context),
      const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
          _forward(context),
      // Los que en macOS atiende la barra de menú. En Windows y en Linux no
      // hay barra, y antes no había atajo: solo existían en el Mac.
      if (!PlatformMenus.supported) ...{
        activatorFor(AppShortcut.courses): () => context.go(Routes.courses()),
        activatorFor(AppShortcut.library): () => context.go(Routes.library()),
        activatorFor(AppShortcut.translations): () =>
            context.go(Routes.translations()),
        activatorFor(AppShortcut.settings): () => context.go(Routes.settings()),
        activatorFor(AppShortcut.refresh): () =>
            refreshAndTell(context, session),
        activatorFor(AppShortcut.help): () => showShortcuts(context),
        if (session.workspace.isNotEmpty) ...{
          activatorFor(AppShortcut.pull): () => pullAndTell(context, session),
          activatorFor(AppShortcut.push): () => pushAndTell(context, session),
        },
      },
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
            tooltip: history.canGoBack
                ? tr('Atrás  {0}', [labelFor(AppShortcut.back)])
                : tr('No hay a dónde volver'),
            visualDensity: VisualDensity.compact,
            // 32 como mínimo: un blanco más pequeño cuesta acertarlo, y más
            // con un trackpad o sin ver bien.
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
              tooltip: tr('Adelante  {0}', [labelFor(AppShortcut.forward)]),
              visualDensity: VisualDensity.compact,
              // 32 como mínimo: un blanco más pequeño cuesta acertarlo, y más
              // con un trackpad o sin ver bien.
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
            color: _over ? context.palette.accentDark : context.palette.muted,
            decoration: _over ? TextDecoration.underline : null,
            decorationColor: context.palette.accentDark,
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

/// El sol y la luna: pasa de claro a oscuro y al revés.
///
/// Desde lo que se ve, y no desde lo que está elegido: con «el del sistema»
/// puesto y el sistema en oscuro, pulsarlo tiene que dar claro, no «oscuro»
/// otra vez. Volver a «el del sistema» está en Ajustes → Apariencia.
class AppearanceToggle extends StatelessWidget {
  const AppearanceToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<Appearance?>();
    if (appearance == null) return const SizedBox.shrink();
    final dark = appearance.brightness == Brightness.dark;
    return IconButton(
      key: const Key('appearance-toggle'),
      tooltip: dark ? tr('Pasar a claro') : tr('Pasar a oscuro'),
      onPressed: appearance.toggle,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween(begin: 0.75, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          key: ValueKey(dark),
          size: 19,
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr('Didacta'),
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
/// Cómo está lo que se ha escrito, en una frase y sin git.
///
/// La barra de abajo decía «Clon local en /Users/…, como Nombre `<correo>`,
/// enviando cada commit»: todo cierto y nada de lo que se quiere saber, que
/// es si lo tuyo está a salvo en GitHub o falta algo.
String syncStateOf(Session session, ContentGateway gateway) {
  if (gateway.kind == GatewayKind.none) return gateway.describe();
  if (!gateway.canWrite) return tr('Solo lectura: aquí no se puede guardar');
  final pending = session.pendingCount;
  final ahead = session.ahead;
  final behind = session.behind ?? 0;
  final parts = [
    if (pending > 0)
      pending == 1
          ? tr('1 fichero sin guardar en el historial')
          : tr('{0} ficheros sin guardar en el historial', [pending]),
    if (ahead > 0)
      ahead == 1
          ? tr('1 cambio sin enviar')
          : tr('{0} cambios sin enviar', [ahead]),
    if (behind > 0)
      behind == 1
          ? tr('1 cambio nuevo en GitHub')
          : tr('{0} cambios nuevos en GitHub', [behind]),
  ];
  return parts.isEmpty ? tr('Guardado en GitHub · al día') : parts.join(' · ');
}

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
                ? tr(
                    'Actualizado. En GitHub hay {0} '
                    '{1} que no están aquí.',
                    [behind, behind == 1 ? 'commit' : 'commits'],
                  )
                : problem != null
                ? tr(
                    'Actualizado desde el disco. No se pudo preguntar a '
                    'GitHub: {0}',
                    [problem],
                  )
                : tr('Actualizado. Nada nuevo en GitHub.'),
          ),
          duration: Duration(seconds: behind > 0 || problem != null ? 8 : 3),
          // Traerlo es otra decisión, y por eso es otro botón: un `pull`
          // cambia los ficheros de debajo de quien está editando.
          action: behind > 0
              ? SnackBarAction(
                  label: tr('Traerlos'),
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
      // Traer ya lo deja todo al día --índice, catálogo, lo compilado--: no
      // hace falta «actualizarlo todo» después, que lo repetía entero.
      await session.pullAll();
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Traído de GitHub y actualizado.'))),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).repoSync,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final gateway = widget.gateway;
    // Leída aquí y no dentro del `onPressed`: `watch` solo vale mientras se
    // construye, y llamarlo desde una pulsación lanza --y el botón no hacía
    // nada sin decir por qué.
    final session = watchSession(context);
    final (icon, colour) = switch (gateway.kind) {
      GatewayKind.clone => (
        Icons.folder_open_outlined,
        context.palette.accentDark,
      ),
      GatewayKind.none => (Icons.lock_outline, context.palette.muted),
    };

    return Material(
      color: context.palette.panel,
      child: InkWell(
        onTap: () => context.go(Routes.settings(section: 'repositorios')),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: colour),
              const SizedBox(width: 6),
              // Cómo está lo tuyo, dicho sin git: «Guardado en GitHub · al
              // día» o «2 cambios sin enviar». Dónde está la copia y como
              // quién se escribe, en el tooltip: es lo que se mira cuando
              // algo no cuadra, no cada vez.
              Expanded(
                child: Tooltip(
                  message: gateway.describe(),
                  child: Text(
                    syncStateOf(session, gateway),
                    key: const Key('sync-state'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.muted,
                    ),
                  ),
                ),
              ),
              if (!gateway.canWrite)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.palette.rule),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    tr('solo lectura'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.palette.muted,
                    ),
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
                          tooltip: tr(
                            'Actualizar: releer el disco, regenerar el '
                            'índice y mirar si hay algo nuevo en GitHub'
                            '  {0}',
                            [labelFor(AppShortcut.refresh)],
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.refresh, size: 15),
                          onPressed: () => _refresh(session),
                        ),
                ),
              // Contar un problema, al lado de actualizar.
              //
              // Aquí y no escondido en Ajustes porque el momento en que se
              // encuentra un fallo es el momento en que se está usando la
              // aplicación, y para entonces nadie va a buscar un menú. Es el
              // mismo sitio donde ya se mira cuando algo no cuadra.
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  key: const Key('report-issue'),
                  tooltip: tr('Contar un problema de Didacta en GitHub'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.bug_report_outlined, size: 15),
                  onPressed: () => openLink(issueLink(context)),
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
                          ? context.palette.thm.withValues(alpha: 0.18)
                          : context.palette.thm.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(Radii.small),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.south_outlined,
                          size: 12,
                          color: context.palette.thm,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          tr('{0} en GitHub', [session.behind]),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: context.palette.thm,
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
      // Sobre la página, en el color de una tarjeta, en lugar de una raya
      // debajo: la cabecera se separa del contenido por el tono y no por una
      // línea más, que es lo que hacía que cada pantalla pareciera un
      // formulario.
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Atrás y adelante, siempre en su sitio --un botón que aparece y
          // desaparece no se aprende-- pero sin una fila para ellos solos:
          // con migas van delante de ellas, y sin migas, delante del título.
          // Encima del título y solo, en una pantalla de arriba del todo, era
          // una flecha gris huérfana.
          if (breadcrumbs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const BackForward(),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final (index, crumb) in breadcrumbs.indexed) ...[
                          _Crumb(label: crumb.$1, route: crumb.$2),
                          if (index < breadcrumbs.length - 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Icon(
                                Icons.chevron_right,
                                size: 14,
                                color: context.palette.faint,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (breadcrumbs.isEmpty) ...[
                const BackForward(),
                const SizedBox(width: 8),
              ],
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
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: context.palette.muted,
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
