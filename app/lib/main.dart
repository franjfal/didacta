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

import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_selector/file_selector.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/auth.dart';
import 'data/catalogue_source.dart';
import 'data/firebase_options.dart';
import 'data/local_clone.dart';
import 'data/preferences.dart';
import 'data/repository_access.dart';
import 'router.dart';
import 'state/session.dart';
import 'ui/platform_menus.dart';
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
///
/// Vacío es lo normal: si no se pasa, se busca en el disco. Pasarlo por
/// `--dart-define` mete la ruta dentro del binario, donde no se ve, y la
/// siguiente compilación que se haga sin acordarse produce una aplicación
/// que no encuentra el catálogo y dice «no se pudo cargar» sin que falte
/// ningún catálogo. Pasó, y de ahí viene la búsqueda.
const String clonePath = String.fromEnvironment('DIDACTA_CLONE');

/// El repositorio del motor, el que tiene `cli/didacta`. Hace falta para
/// compilar; si no se pasa, la aplicación lo busca al lado del clon.
const String enginePath = String.fromEnvironment('DIDACTA_ENGINE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every error goes to the console with its stack, and none of them takes
  // the app down. Both halves of that are deliberate.
  //
  // Silence is what made two black screens expensive to diagnose: the app
  // died before its first frame and the only trace was a minified object in
  // a console nobody was looking at. An error that is printed with a stack
  // is an error somebody can act on in a minute.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Didacta · error: ${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Didacta · error sin capturar: $error\n$stack');
    // Handled: an unhandled asynchronous error terminates the isolate, and
    // a failed keychain read is not worth the whole application.
    return true;
  };

  // Firebase is only for identity, and the app has to work without it: a
  // static publication of public material needs no sign-in, and a
  // misconfigured project must not take the whole app down with it.
  //
  // Only attempted where there are options for the platform, which today
  // means the web. On desktop there is no `GoogleService-Info.plist` and
  // there does not need to be: a clone on your own disk takes its commit
  // author from git, so the whole editor works with no sign-in anywhere.
  var firebaseReady = false;
  if (kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
      firebaseReady = true;
    } catch (error) {
      debugPrint('Firebase no disponible: $error');
    }
  }

  // Dónde está el repositorio de contenido. Lo que se haya elegido en
  // Ajustes manda sobre esto; esto es solo el valor por defecto, y buscarlo
  // es mejor que no tenerlo: en escritorio, sin clon no hay catálogo --el
  // índice se pediría por HTTP a una ruta relativa que no resuelve-- y la
  // pantalla diría «no se pudo cargar el catálogo» sin que falte ninguno.
  final defaultClone = clonePath.isNotEmpty
      ? clonePath
      : await LocalClone.discover(repo: contentRepo) ?? '';

  final session = Session(
    catalogueSource: const HttpCatalogueSource(base: indexBase),
    // Only when Firebase actually came up. `DidactaAuth` reads
    // `FirebaseAuth.instance` in its constructor, so building it without
    // Firebase throws here -- before `runApp` -- and the window stays black
    // with the reason only in a log. That is exactly what happened.
    auth: firebaseReady
        ? DidactaAuth()
        : const UnavailableAuth(
            'Firebase no está configurado en esta versión, así que no hay '
            'inicio de sesión. En escritorio no hace falta: el clon local '
            'toma el autor de los commits de la identidad de git.',
          ),
    tokenStore: TokenStore(),
    apiBase: apiBase,
    contentOwner: contentOwner,
    contentRepo: contentRepo,
    contentBranch: contentBranch,
    preferences: StoredPreferences(
      defaultClonePath: defaultClone,
      defaultEnginePath: enginePath,
    ),
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
  /// Al volver a la ventana, mirar el disco.
  ///
  /// El vigilante del sistema de ficheros se pierde eventos --un `mv`
  /// atómico, un volumen de red-- y no avisa de que se los ha perdido. Volver
  /// a la aplicación después de tocar algo por fuera es exactamente cuando
  /// hay que comprobarlo, y cuesta dos `stat`.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onShow: () => unawaited(widget.session.checkDisk()),
    onRestart: () => unawaited(widget.session.checkDisk()),
  );

  @override
  void initState() {
    super.initState();
    widget.session.start();
    // Tocarlo es crearlo: el oyente se suscribe al construirse.
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
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
        home: _LoadFailure(session: session),
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
      // El menú del sistema va aquí, por debajo del router, porque sus
      // acciones navegan: por encima no habría a dónde.
      builder: (context, child) => PlatformMenus(
        // Pintado, y no transparente como estaba.
        //
        // Esto era un fallo que se veía feísimo y solo en según qué máquina:
        // aquí arriba, por encima del Scaffold, **no hay nada que pinte el
        // fondo**, así que un banner con alfa se componía sobre el fondo
        // nativo de la ventana. En un macOS en modo oscuro eso es negro, y
        // el aviso de Firebase salía como una franja negra con el texto
        // ilegible. Un color de fondo opaco lo arregla y no cuesta nada.
        child: ColoredBox(
          color: didactaSurface,
          child: Column(
            children: [
              if (!widget.firebaseReady) const _FirebaseBanner(),
              if (session.catalogue.errors.isNotEmpty)
                _ErrorBanner(errors: session.catalogue.errors),
              if (session.indexNote != null)
                _IndexBanner(
                  note: session.indexNote!,
                  onDismiss: session.dismissIndexNote,
                ),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        ),
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
    // Opaco: con alfa se compone sobre el fondo de la ventana, que en un
    // macOS oscuro es negro.
    color: const Color(0xFFFBF3E4),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: Color(0xFF8A5D1B)),
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
/// Que el índice se ha regenerado, o que no se ha podido.
///
/// Se enseña porque cambia lo que la biblioteca lista. Quien acaba de mover
/// una carpeta tiene que ver que la aplicación se ha enterado; y quien no ha
/// tocado nada, enterarse de que alguien sí.
class _IndexBanner extends StatelessWidget {
  const _IndexBanner({required this.note, required this.onDismiss});

  final String note;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFEFF5EC),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 6, 5),
      child: Row(
        children: [
          const Icon(Icons.autorenew, size: 15, color: didactaAccentDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          // Sin `Tooltip` y sin `IconButton`: esta franja vive **por
          // encima** del Navigator, donde no hay Overlay, y un tooltip ahí
          // arriba revienta la construcción entera. Un gesto y un icono
          // hacen lo mismo sin pedir nada.
          InkResponse(
            key: const Key('dismiss-index-note'),
            onTap: onDismiss,
            radius: 16,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 15, color: didactaMuted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFBEDED),
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

/// La pantalla de cuando no hay catálogo.
///
/// Con una salida y no solo un motivo. Ajustes vive dentro del router, y el
/// router solo existe cuando hay catálogo, así que desde aquí no se podía
/// llegar a la única pantalla que arregla el problema: la elección de la
/// carpeta del repositorio está repetida aquí a propósito.
class _LoadFailure extends StatefulWidget {
  const _LoadFailure({required this.session});

  final Session session;

  @override
  State<_LoadFailure> createState() => _LoadFailureState();
}

class _LoadFailureState extends State<_LoadFailure> {
  Object? _problem;

  Object get error => _problem ?? widget.session.error!;
  String get where => widget.session.catalogueOrigin;

  void onRetry() => widget.session.start();

  /// Elegir la carpeta del clon y volver a arrancar.
  Future<void> _choose() async {
    try {
      final chosen = await getDirectoryPath(
        confirmButtonText: 'Usar este repositorio',
      );
      if (chosen == null) return;
      await widget.session.useClone(chosen);
      await widget.session.start();
    } catch (problem) {
      if (mounted) setState(() => _problem = problem);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Que no haya clon es un problema distinto de que el índice no esté, y
    // el consejo es otro: aquí no falta ningún catálogo, falta decir dónde
    // está el repositorio.
    final noClone =
        widget.session.canUseClone && widget.session.clonePath == null;
    return _body(context, noClone);
  }

  Widget _body(BuildContext context, bool noClone) {
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
                    // Expanded: es la pantalla que se ve en un móvil cuando
                    // no hay catálogo, y una cabecera que desborda tapa el
                    // motivo, que es lo único que hay aquí.
                    Expanded(
                      child: Text(
                        'No se pudo cargar el catálogo',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
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
                if (noClone) ...[
                  const Text(
                    'No hay ninguna carpeta del repositorio de contenido '
                    'elegida, así que no hay de dónde leer el catálogo. '
                    'Elige el clon que tengas en el disco.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Es la carpeta que tiene dentro didacta.yaml, content/ y '
                    'courses/.',
                    style: TextStyle(fontSize: 12, color: didactaMuted),
                  ),
                ] else ...[
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
                ],
                const SizedBox(height: 20),
                // Con el ancho entero para que `end` signifique algo: en una
                // columna alineada a la izquierda, un Wrap se encoge y los
                // botones acaban donde no se los espera. Y Wrap y no Row
                // porque los dos botones no caben en un móvil.
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.session.canUseClone)
                        OutlinedButton.icon(
                          key: const Key('choose-clone'),
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Elegir la carpeta…'),
                          onPressed: _choose,
                        ),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reintentar'),
                        onPressed: onRetry,
                      ),
                    ],
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
