/// Didacta.
///
/// Brings up Firebase, the session and the router, in that order, and shows
/// the app once the catalogue has loaded.
///
/// Everything configurable is a build-time define, so one build can serve any
/// content repository:
///
///     flutter build web --release \
///       --dart-define=DIDACTA_INDEX=generated \
///       --dart-define=DIDACTA_API=https://didacta-api.<sub>.workers.dev \
///       --dart-define=DIDACTA_OWNER=franjfal \
///       --dart-define=DIDACTA_REPO=didacta_db
///
/// On desktop there is one more, for a clone that is already on disk:
///
///     flutter run -d macos --dart-define=DIDACTA_CLONE=~/didacta_db
///
/// The defaults point at a `generated/` directory next to the app and at no
/// API, which is exactly what a static publication of a content repository
/// looks like: the library browses, and nothing can be written until an API or
/// a token is configured.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/auth.dart';
import 'data/catalogue_source.dart';
import 'data/firebase_options.dart';
import 'data/preferences.dart';
import 'data/repository_access.dart';
import 'router.dart';
import 'state/session.dart';
import 'ui/theme.dart';

/// Where the generated catalogue is served from.
const String indexBase = String.fromEnvironment(
  'DIDACTA_INDEX',
  defaultValue: 'generated',
);

/// The Worker's origin. Empty is legitimate: a desktop build with a token
/// needs no API at all.
const String apiBase = String.fromEnvironment('DIDACTA_API');

const String contentOwner = String.fromEnvironment(
  'DIDACTA_OWNER',
  defaultValue: 'franjfal',
);
const String contentRepo = String.fromEnvironment(
  'DIDACTA_REPO',
  defaultValue: 'didacta_db',
);
const String contentBranch = String.fromEnvironment(
  'DIDACTA_BRANCH',
  defaultValue: 'main',
);

/// A clone already on disk, for a desktop build handed to someone who has
/// the repository. Ignored on the web, and overridden by whatever is chosen
/// in Ajustes.
const String clonePath = String.fromEnvironment('DIDACTA_CLONE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is only for identity, and the app has to work without it: a
  // static publication of public material needs no sign-in, and a
  // misconfigured project must not take the whole app down with it.
  //
  // On desktop it is often not configured at all, and that is fine rather
  // than broken: a clone on your own disk gets its commit author from git,
  // so the whole editor works with no sign-in anywhere.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: kIsWeb ? DefaultFirebaseOptions.web : null,
    );
    firebaseReady = true;
  } catch (error) {
    debugPrint('Firebase no disponible: $error');
  }

  final session = Session(
    catalogueSource: const HttpCatalogueSource(base: indexBase),
    auth: DidactaAuth(),
    tokenStore: TokenStore(),
    apiBase: apiBase,
    contentOwner: contentOwner,
    contentRepo: contentRepo,
    contentBranch: contentBranch,
    preferences: const StoredPreferences(defaultClonePath: clonePath),
  );

  runApp(DidactaApp(session: session, firebaseReady: firebaseReady));
}

class DidactaApp extends StatefulWidget {
  const DidactaApp({
    super.key,
    required this.session,
    this.firebaseReady = true,
  });

  final Session session;
  final bool firebaseReady;

  @override
  State<DidactaApp> createState() => _DidactaAppState();
}

class _DidactaAppState extends State<DidactaApp> {
  @override
  void initState() {
    super.initState();
    widget.session.start();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.session,
      child: _Bootstrap(firebaseReady: widget.firebaseReady),
    );
  }
}

/// Shows a loader, a failure, or the app.
///
/// The router is built only once the catalogue is in: every route reads it,
/// and a router whose screens have to handle a null catalogue puts that check
/// in every one of them for a state none of them can do anything about.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  Object? _routerFor;
  dynamic _router;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);

    return switch (session.state) {
      LoadState.loading => const _Splash(),
      LoadState.failed => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: didactaTheme(),
        home: _LoadFailure(
          error: session.error!,
          where: session.catalogueOrigin,
          onRetry: session.start,
        ),
      ),
      LoadState.ready => _buildApp(session),
    };
  }

  Widget _buildApp(Session session) {
    // Built once and kept: rebuilding a GoRouter throws away the history,
    // which on the web means the back button stops working.
    if (_routerFor != session) {
      _router = buildRouter(session);
      _routerFor = session;
    }
    return MaterialApp.router(
      title: 'Didacta',
      debugShowCheckedModeBanner: false,
      theme: didactaTheme(),
      routerConfig: _router,
      builder: (context, child) => Column(
        children: [
          if (!widget.firebaseReady) const _FirebaseBanner(),
          if (session.catalogue.errors.isNotEmpty)
            _ErrorBanner(errors: session.catalogue.errors),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: didactaTheme(),
    home: const Scaffold(body: Center(child: CircularProgressIndicator())),
  );
}

class _FirebaseBanner extends StatelessWidget {
  const _FirebaseBanner();

  @override
  Widget build(BuildContext context) => Material(
    color: didactaEx.withValues(alpha: 0.12),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: didactaEx),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Firebase no ha arrancado: se puede leer el catálogo, pero '
              'no iniciar sesión.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

/// What the engine complained about while reading the repository.
///
/// Surfaced rather than swallowed: an interface built on a repository that
/// does not load cleanly should say so.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: didactaTeacher.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: didactaTeacher,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                errors.length == 1
                    ? errors.first
                    : '${errors.length} problemas al leer el repositorio: '
                          '${errors.first}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              child: const Text('Ver todos'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Problemas al leer el repositorio'),
                  content: SizedBox(
                    width: 560,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final message in errors)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SelectableText(
                              message,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({
    required this.error,
    required this.where,
    required this.onRetry,
  });

  final Object error;
  final String where;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, color: didactaTeacher),
                    SizedBox(width: 8),
                    Text(
                      'No se pudo cargar el catálogo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Where it read from: "could not load" without a location is
                // not something anyone can act on.
                SelectableText(
                  'Origen: $where',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: didactaMuted,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  error.toString(),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 20),
                const Text(
                  'El catálogo lo genera el motor. Desde el repositorio de '
                  'contenido:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: didactaInk,
                  child: const SelectableText(
                    'didacta index',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                    onPressed: onRetry,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
