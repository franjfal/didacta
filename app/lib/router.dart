/// The routes.
///
/// Every screen has a URL, and that is a requirement rather than a nicety:
/// this is a web app first, so "send me the link to that unit" has to work,
/// the back button has to mean something, and a reload has to land where you
/// were.
///
///   /                                       the library
///   `/unit/content/<path>`                    one unit, and its editor
///   /courses                                the subjects
///   /courses/:course/:year                  one year's composition
///   /courses/:course/:year/:document        one document, and its outputs
///   /translations                           what needs translating
///   /settings                               access, session, diagnostics
///
/// A unit's path has slashes in it (`content/analysis/normed/definition`), so
/// it is carried as the trailing part of the route rather than as a single
/// escaped segment: `/unit/content/analysis/normed/definition` reads as the
/// path it is, and a URL someone pastes into a message survives.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'state/session.dart';
import 'ui/between_repos_page.dart';
import 'ui/courses_page.dart';
import 'ui/document_page.dart';
import 'ui/library_page.dart';
import 'ui/mcp_page.dart';
import 'ui/settings_page.dart';
import 'ui/shell.dart';
import 'ui/translations_page.dart';
import 'ui/unit_page.dart';
import 'ui/year_page.dart';

/// Builds the router. Takes the session so a route can refuse to resolve
/// against a catalogue that does not contain what the URL names.
GoRouter buildRouter(Session session) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            DidactaShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LibraryPage()),
          ),
          GoRoute(
            // `:path(.*)` takes the rest of the URL, slashes included, which
            // is what lets a unit path stay readable in the address bar.
            path: '/unit/:path(.*)',
            pageBuilder: (context, state) => NoTransitionPage(
              child: UnitPage(
                unitPath: state.pathParameters['path'] ?? '',
                language: state.uri.queryParameters['lang'],
              ),
            ),
          ),
          GoRoute(
            path: '/courses',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: CoursesPage()),
          ),
          GoRoute(
            path: '/courses/:course/:year',
            pageBuilder: (context, state) => NoTransitionPage(
              child: YearPage(
                courseId: state.pathParameters['course']!,
                year: state.pathParameters['year']!,
              ),
            ),
          ),
          GoRoute(
            path: '/courses/:course/:year/:document',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DocumentPage(
                courseId: state.pathParameters['course']!,
                year: state.pathParameters['year']!,
                documentId: state.pathParameters['document']!,
              ),
            ),
          ),
          GoRoute(
            path: '/translations',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TranslationsPage()),
          ),
          GoRoute(
            path: '/between',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BetweenReposPage()),
          ),
          GoRoute(
            path: '/mcp',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: McpPage()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _NotFound(location: state.uri.toString()),
  );
}

/// Convenience so screens link by meaning rather than by string-building, and
/// a route rename is one edit.
class Routes {
  const Routes._();

  static String library() => '/';

  /// Una unidad. Con [language], abierta en ese idioma.
  ///
  /// Hace falta para «esto falta por traducir»: llevar a la unidad y dejar
  /// que abra el idioma de siempre obligaría a buscar la pestaña, que es
  /// justo el paso que sobra cuando se viene de una lista de lo que falta.
  static String unit(String path, {String? language}) =>
      language == null ? '/unit/$path' : '/unit/$path?lang=$language';

  static String courses() => '/courses';

  static String year(String course, String year) => '/courses/$course/$year';

  static String document(String course, String year, String document) =>
      '/courses/$course/$year/$document';

  static String translations() => '/translations';

  /// Las comprobaciones que solo tienen sentido con varios repositorios.
  static String between() => '/between';

  static String mcp() => '/mcp';

  static String settings() => '/settings';
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esa dirección no existe',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                // Shown rather than swallowed: a wrong link is usually a typo
                // or a stale bookmark, and seeing it is how you tell which.
                SelectableText(
                  location,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go(Routes.library()),
                  child: const Text('Ir a la biblioteca'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reads the session without listening. For callbacks, where rebuilding on
/// every change would be wrong.
Session sessionOf(BuildContext context) => context.read<Session>();

/// Reads and listens. For build methods.
Session watchSession(BuildContext context) => context.watch<Session>();

/// Navigates from anywhere below the router.
///
/// Exists so the platform menu bar does not import `go_router` itself: it is
/// the only caller outside a screen, and a menu that knows how routing is
/// implemented is a menu that breaks when the router changes.
void goTo(BuildContext context, String route) => GoRouter.of(context).go(route);
