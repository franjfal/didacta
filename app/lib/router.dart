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

import 'model/library_place.dart';
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
import 'ui/unsaved_dialog.dart';
import 'ui/year_page.dart';
import 'l10n/tr.dart';

/// Builds the router. Takes the session so a route can refuse to resolve
/// against a catalogue that does not contain what the URL names.
/// Antes de dejar una pantalla, lo que tenga escrito y sin guardar.
///
/// En las tres donde se escribe: una lección, un curso y un documento. Sin
/// esto, cambiar de lección con un párrafo a medio escribir se lo llevaba
/// sin decir nada.
Future<bool> _leaving(
  BuildContext context,
  GoRouterState state,
  Session session,
) => confirmLeaving(context, session.unsaved.whatAt(state.uri.path));

GoRouter buildRouter(Session session) {
  return GoRouter(
    // Se entra por las asignaturas y no por la biblioteca.
    //
    // La biblioteca contesta «¿qué tengo de esto?», que es una pregunta que
    // se hace a ratos; al abrir Didacta lo que se viene a hacer es preparar
    // una clase, y eso empieza en la asignatura que se da mañana. La
    // biblioteca sigue en `/`, a un clic del carril: lo que cambia es por
    // dónde se entra.
    initialLocation: '/courses',
    // Sin `refreshListenable`: no hay ninguna redirección que recalcular, y
    // escuchar a la sesión rehacía las páginas en cada aviso suyo, que son
    // decenas por guardado. Cada página escucha lo suyo.
    routes: [
      ShellRoute(
        builder: (context, state, child) => DidactaShell(
          location: state.uri.path,
          url: state.uri.toString(),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => NoTransitionPage(
              child: LibraryPage(
                place: LibraryPlace.fromQuery(state.uri.queryParameters),
              ),
            ),
          ),
          GoRoute(
            // `:path(.*)` takes the rest of the URL, slashes included, which
            // is what lets a unit path stay readable in the address bar.
            path: '/unit/:path(.*)',
            onExit: (context, state) => _leaving(context, state, session),
            pageBuilder: (context, state) => NoTransitionPage(
              // Con clave por lección: sin ella, ir de una a otra --«Aprobar y
              // siguiente», un enlace-- reutilizaba la pantalla con los
              // editores de la anterior, y guardar escribía su texto en la
              // nueva. El `pageKey` de go_router es por ruta, no por
              // dirección. Otro idioma u otra línea de la misma sí la
              // conservan: lo lleva `didUpdateWidget`.
              child: UnitPage(
                key: ValueKey('unit:${state.pathParameters['path']}'),
                unitPath: state.pathParameters['path'] ?? '',
                language: state.uri.queryParameters['lang'],
                line: int.tryParse(state.uri.queryParameters['linea'] ?? ''),
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
            onExit: (context, state) => _leaving(context, state, session),
            pageBuilder: (context, state) => NoTransitionPage(
              // Por lo mismo que la lección: cada curso, su pantalla.
              child: YearPage(
                key: ValueKey(
                  'year:${state.pathParameters['course']}/'
                  '${state.pathParameters['year']}',
                ),
                courseId: state.pathParameters['course']!,
                year: state.pathParameters['year']!,
              ),
            ),
          ),
          GoRoute(
            path: '/courses/:course/:year/:document',
            onExit: (context, state) => _leaving(context, state, session),
            pageBuilder: (context, state) => NoTransitionPage(
              child: DocumentPage(
                key: ValueKey(
                  'document:${state.pathParameters['course']}/'
                  '${state.pathParameters['year']}/'
                  '${state.pathParameters['document']}',
                ),
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
            pageBuilder: (context, state) => NoTransitionPage(
              child: SettingsPage(section: state.uri.queryParameters['s']),
            ),
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

  /// La biblioteca, en [place]: con lo que se había abierto, filtrado y
  /// buscado, para volver al mismo sitio.
  static String library([LibraryPlace place = const LibraryPlace()]) {
    final query = place.toQuery();
    return query.isEmpty
        ? '/'
        : Uri(path: '/', queryParameters: query).toString();
  }

  /// Una unidad. Con [language], abierta en ese idioma.
  ///
  /// Hace falta para «esto falta por traducir»: llevar a la unidad y dejar
  /// que abra el idioma de siempre obligaría a buscar la pestaña, que es
  /// justo el paso que sobra cuando se viene de una lista de lo que falta.
  static String unit(String path, {String? language, int? line}) {
    final query = [
      if (language != null) 'lang=$language',
      // La línea, para llegar a un error con el cursor ya en él.
      if (line != null) 'linea=$line',
    ];
    return query.isEmpty ? '/unit/$path' : '/unit/$path?${query.join('&')}';
  }

  static String courses() => '/courses';

  static String year(String course, String year) => '/courses/$course/$year';

  static String document(String course, String year, String document) =>
      '/courses/$course/$year/$document';

  static String translations() => '/translations';

  /// Las comprobaciones que solo tienen sentido con varios repositorios.
  static String between() => '/between';

  static String mcp() => '/mcp';

  /// Ajustes, abiertos por [section] si se dice cuál: `repositorios`,
  /// `herramientas`, `idiomas`… (ver `settingsSections`).
  static String settings({String? section}) =>
      section == null ? '/settings' : '/settings?s=$section';
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
                Text(
                  tr('Esa dirección no existe'),
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
                  child: Text(tr('Ir a la biblioteca')),
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

/// Navega desde cualquier sitio **por debajo** del router.
///
/// Para que una pantalla pueda ir a una dirección sin importar `go_router`.
/// Por encima no vale: lo que va en el `builder` de `MaterialApp.router` --el
/// menú del sistema, las franjas de aviso-- envuelve al `Router`, y desde ahí
/// `GoRouter.of` no encuentra nada. Eso navega con el `go` del router, que
/// `main.dart` les pasa.
void goTo(BuildContext context, String route) => GoRouter.of(context).go(route);
