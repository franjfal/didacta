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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/content_gateway.dart';
import '../router.dart';
import 'brand.dart';
import 'theme.dart';

class DidactaShell extends StatelessWidget {
  const DidactaShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const List<_Destination> _destinations = [
    _Destination(
      '/',
      Icons.library_books_outlined,
      Icons.library_books,
      'Biblioteca',
    ),
    _Destination(
      '/courses',
      Icons.school_outlined,
      Icons.school,
      'Asignaturas',
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
  int get _index {
    if (location.startsWith('/courses')) return 1;
    if (location.startsWith('/translations')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final pending = session.catalogueOrNull == null
            ? 0
            : session.needingTranslation(session.language).length;

        if (!wide) {
          return Scaffold(
            body: Column(
              children: [
                Expanded(child: child),
                const Divider(height: 1),
                _GatewayStrip(gateway: session.gateway),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              elevation: 0,
              height: 58,
              backgroundColor: didactaPanel,
              selectedIndex: _index,
              onDestinationSelected: (index) =>
                  context.go(_destinations[index].path),
              destinations: [
                for (final destination in _destinations)
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
                selectedIndex: _index,
                onDestinationSelected: (index) =>
                    context.go(_destinations[index].path),
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
                  for (final destination in _destinations)
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
class _GatewayStrip extends StatelessWidget {
  const _GatewayStrip({required this.gateway});

  final ContentGateway gateway;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (gateway.kind) {
      GatewayKind.direct => (Icons.vpn_key_outlined, didactaAccentDark),
      GatewayKind.api =>
        gateway.canWrite
            ? (Icons.cloud_done_outlined, didactaThm)
            : (Icons.cloud_outlined, didactaMuted),
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
          if (breadcrumbs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
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
