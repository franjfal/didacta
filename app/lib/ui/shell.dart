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
                leading: const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 4),
                  child: _Mark(),
                ),
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: destination.label == 'Traducción' && pending > 0
                          ? Badge(
                              // The number, not a dot: "how much is waiting"
                              // is the question, and a dot cannot answer it.
                              label: Text('$pending'),
                              backgroundColor: didactaEx,
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
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
                    InkWell(
                      onTap: () => context.go(crumb.$2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          crumb.$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: didactaThm,
                          ),
                        ),
                      ),
                    ),
                    if (index < breadcrumbs.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          '/',
                          style: TextStyle(fontSize: 12, color: didactaMuted),
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12,
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
          if (bottom != null) bottom! else const SizedBox(height: 12),
        ],
      ),
    );
  }
}
