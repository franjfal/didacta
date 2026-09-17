/// Didacta.
///
/// Levanta la sesión y el router, en ese orden, y enseña la aplicación en
/// cuanto el catálogo está cargado.
///
/// Aquí ya no se configura casi nada: los repositorios se eligen dentro de la
/// aplicación --se entra en GitHub y se añaden-- y cada uno se clona en su
/// carpeta. Antes había que compilar una versión por repositorio, con su
/// dueño, su nombre y la dirección de un Worker metidos en el binario.
///
/// Lo único que se puede pasar al compilar es el Client ID de la OAuth App, y
/// tampoco hace falta: se escribe en Ajustes y se guarda.
///
///     flutter build macos --release \
///       --dart-define=DIDACTA_GITHUB_CLIENT=Iv1.xxxxxxxx
library;

import 'dart:ui' show PlatformDispatcher;

import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/app_info.dart';
import 'data/catalogue_source.dart';
import 'data/preferences.dart';
import 'data/repository_access.dart';
import 'router.dart';
import 'data/mcp_process.dart';
import 'state/mcp_service.dart';
import 'state/session.dart';
import 'state/update_service.dart';
import 'ui/platform_menus.dart';
import 'ui/sign_in.dart';
import 'ui/theme.dart';
import 'ui/tour.dart';
import 'ui/update_section.dart';
import 'ui/welcome.dart';

/// Where the generated catalogue is served from.
const String indexBase = String.fromEnvironment(
  'DIDACTA_INDEX',
  defaultValue: 'generated',
);

/// El Client ID de la OAuth App con la que se entra en GitHub.
///
/// Se puede pasar al compilar, pero no hace falta: se escribe en Ajustes y se
/// guarda. Es público por definición --una aplicación de escritorio no puede
/// esconder un secreto-- así que no hay nada que proteger aquí; lo que se
/// evita es tener que recompilar para cambiar de aplicación de OAuth.
const String githubClientId = String.fromEnvironment('DIDACTA_GITHUB_CLIENT');

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

  // Dónde se clonan los repositorios, si no se ha dicho otra cosa.
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  final session = Session(
    catalogueSource: const HttpCatalogueSource(base: indexBase),
    tokenStore: TokenStore(),
    preferences: StoredPreferences(
      defaultClonePath: '',
      defaultEnginePath: enginePath,
      defaultClientId: githubClientId,
    ),
  );

  // La primera vez, los repositorios se clonan aquí. Se puede cambiar en
  // Ajustes; esto es solo un sitio razonable para no preguntar de entrada.
  if ((await session.preferences.cloneBase() ?? '').isEmpty &&
      home.isNotEmpty) {
    await session.preferences.setCloneBase('$home/Didacta');
  }

  // Quién es esta copia de Didacta: la versión sale del paquete construido,
  // no de una constante que puede quedarse atrás de la compilación.
  final info = await AppInfo.load();
  // Sin credencial: las versiones están en un repositorio público, así que
  // buscarlas no depende de haber entrado en GitHub ni de seguir teniendo
  // acceso a nada.
  final updates = UpdateService(info: info, preferences: session.preferences);

  // El servidor MCP, apagado. Se enciende desde Ajustes: encendido, un
  // modelo puede escribir en los repositorios de quien lo enciende, y eso es
  // una decisión que se toma, no una que se hereda de una instalación.
  final mcp = McpService(
    openRunner: () => McpRunner.forHost(
      enginePath: session.enginePath ?? '',
      texPath: session.texPath,
    ),
  );

  // El tour guiado. Se enciende al terminar la bienvenida y desde Ajustes;
  // terminarlo o salirse lo da por hecho, y por eso lo apunta él mismo.
  final tour = TourController(
    onFinished: () => session.preferences.setTourDone(true),
  );

  runApp(DidactaApp(session: session, updates: updates, mcp: mcp, tour: tour));
}

class DidactaApp extends StatefulWidget {
  const DidactaApp({
    super.key,
    required this.session,
    required this.updates,
    this.mcp,
    this.tour,
  });

  final Session session;
  final UpdateService updates;

  /// El tour guiado. Opcional: un test que monta la aplicación para mirar
  /// otra cosa no tiene por qué traerse uno, y sin él no hay recorrido.
  final TourController? tour;

  /// El servidor MCP. Opcional: un test que monta la aplicación para mirar
  /// otra cosa no tiene por qué traerse un servidor, y sin él lo único que
  /// pasa es que el interruptor dice que no se puede.
  final McpService? mcp;

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
    final started = widget.session.start();
    // Tocarlo es crearlo: el oyente se suscribe al construirse.
    _lifecycle;
    // Después de que la sesión levante el espacio de trabajo: los
    // repositorios son lo que se le da al servidor al arrancar, y arrancarlo
    // sin ninguno lo dejaría sirviendo la nada hasta el siguiente reinicio.
    if (widget.mcp != null) unawaited(started.then((_) => _restartMcp()));

    // Las actualizaciones, después y sin esperarlas. Ni una petición de red
    // ni una lectura de preferencias pueden retrasar la primera pantalla, y
    // si fallan no se entera nadie: buscar actualizaciones nunca puede
    // impedir usar Didacta.
    unawaited(
      widget.updates.load().then((_) => widget.updates.checkIfDue()).catchError(
        (Object problem) {
          debugPrint('Didacta · actualizaciones: $problem');
        },
      ),
    );
  }

  late final TourController _tour = widget.tour ?? TourController();

  /// El que venga, o uno que no puede encender nada y lo dice.
  late final McpService _mcp =
      widget.mcp ??
      McpService(
        openRunner: () => const UnavailableRunner(
          'Esta copia se ha montado sin servidor MCP.',
        ),
      );

  /// Vuelve a encender el servidor MCP si quedó encendido.
  Future<void> _restartMcp() async {
    if (!await widget.session.preferences.mcpEnabled()) return;
    final writable = (await widget.session.preferences.mcpWritable()).toSet();
    final repositories = [
      for (final repo in widget.session.workspace.repos)
        if ((widget.session.pathOf(repo.id) ?? '').isNotEmpty)
          McpRepository(
            id: repo.id,
            directory: widget.session.pathOf(repo.id)!,
            writable: writable.contains(repo.id),
          ),
    ];
    if (repositories.isEmpty) return;
    await _mcp.start(repositories: repositories);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (widget.mcp == null) _mcp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.session),
        // Aparte de la sesión, y no dentro: son dos cosas que cambian por
        // motivos distintos, y una pantalla que solo mira la versión no
        // tiene por qué repintarse cuando se recarga el catálogo.
        ChangeNotifierProvider.value(value: widget.updates),
        ChangeNotifierProvider.value(value: _mcp),
        ChangeNotifierProvider.value(value: _tour),
      ],
      child: const _Bootstrap(),
    );
  }
}

/// Shows a loader, a failure, or the app.
///
/// The router is built only once the catalogue is in: every route reads it,
/// and a router whose screens have to handle a null catalogue puts that check
/// in every one of them for a state none of them can do anything about.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  Object? _routerFor;
  dynamic _router;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);

    // La bienvenida, antes incluso que la puerta de GitHub.
    //
    // El orden importa y no es simetría: entrar en GitHub es **uno de los
    // pasos** de la bienvenida, no algo que haya que hacer antes de que nadie
    // te haya dicho qué es esto. Pedirle a alguien un token antes de
    // explicarle para qué es el programa es pedirle que confíe a ciegas.
    //
    // `null` es «todavía no se ha leído la preferencia», y ahí lo que toca es
    // la pantalla de carga: con `false` por defecto, cada arranque enseñaría
    // la bienvenida durante un parpadeo.
    if (session.welcomeDone == null) return const _Splash();
    if (session.welcomeDone == false) {
      return MaterialApp(
        title: 'Didacta',
        debugShowCheckedModeBanner: false,
        theme: didactaTheme(),
        home: WelcomeScreen(
          session: session,
          onFinished: () => _finishWelcome(session),
        ),
      );
    }

    // La sesión, antes que nada.
    //
    // **Sin sesión no hay aplicación**: no es un velo por encima de la
    // biblioteca sino la pantalla en lugar de ella. Construir el router y
    // taparlo habría construido igual todo lo que hay debajo, y lo que hay
    // debajo son los ficheros de un repositorio privado.
    //
    // El orden importa: mientras se lee el llavero la respuesta no es «no ha
    // entrado» sino que todavía no se sabe, y ahí lo que toca es la pantalla
    // de carga. Sin esa distinción, cada arranque enseñaría la puerta durante
    // un parpadeo antes de abrir la biblioteca.
    if (session.signInState == SignInState.signedOut) {
      return MaterialApp(
        title: 'Didacta',
        debugShowCheckedModeBanner: false,
        theme: didactaTheme(),
        home: SignInGate(session: session),
      );
    }

    return switch (session.state) {
      LoadState.loading => const _Splash(),
      LoadState.failed => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: didactaTheme(),
        home: _LoadFailure(session: session),
      ),
      LoadState.ready when session.signInState == SignInState.checking =>
        const _Splash(),
      LoadState.ready => _buildApp(session),
    };
  }

  /// Dar la bienvenida por vista y, si es la primera vez, lanzar el tour.
  ///
  /// El retraso es lo que no se puede quitar: el tour señala partes del
  /// armazón, y el armazón no existe hasta que la aplicación se ha construido
  /// **después** de este cambio de estado. Sin esperar, el tour arranca,
  /// no encuentra ningún objetivo montado y se da por terminado sin enseñar
  /// nada -- que es peor que no ofrecerlo.
  Future<void> _finishWelcome(Session session) async {
    await session.completeWelcome();
    if (await session.preferences.tourDone()) return;
    if (!mounted) return;
    final tour = context.read<TourController>();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) tour.start();
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
        // un aviso salía como una franja negra con el texto
        // ilegible. Un color de fondo opaco lo arregla y no cuesta nada.
        child: ColoredBox(
          color: didactaSurface,
          // El tour va en un `Stack` por encima de la aplicación entera, y no
          // dentro de una pantalla: señala el carril y la barra de arriba,
          // que están fuera de todas ellas.
          child: Stack(
            children: [
              Column(
                children: [
                  // Sin repositorios la aplicación abre vacía a propósito: no
                  // es un error, es que falta decirle con qué trabajas. Un aviso
                  // con el camino, en lugar de una biblioteca vacía sin
                  // explicación.
                  // Y solo cuando además no hay nada cargado: si la biblioteca
                  // tiene unidades, el aviso sería mentira --hay con qué
                  // trabajar-- y estaría ocupando sitio en cada pantalla.
                  // Lo primero de todo: si hay versión nueva, es lo más útil que
                  // se puede decir en esta franja.
                  const UpdateBanner(),
                  if (session.needsRepository &&
                      session.catalogue.units.isEmpty)
                    const _NoRepositoriesBanner(),
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
              TourOverlay(controller: context.watch<TourController>()),
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

/// Todavía no hay ningún repositorio con el que trabajar.
class _NoRepositoriesBanner extends StatelessWidget {
  const _NoRepositoriesBanner();

  @override
  Widget build(BuildContext context) => Material(
    color: didactaAccentDark.withValues(alpha: 0.10),
    child: InkWell(
      onTap: () => context.go(Routes.settings()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.folder_open_outlined, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Todavía no hay ningún repositorio abierto. Añade uno en '
                'Ajustes: desde GitHub, o eligiendo una carpeta que ya tengas '
                'clonada en el disco.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('go-to-settings'),
              onPressed: () => context.go(Routes.settings()),
              child: const Text('Abrir Ajustes'),
            ),
          ],
        ),
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

  /// Añadir una carpeta que ya esté clonada, y volver a arrancar.
  ///
  /// Sin pasar por GitHub: de qué repositorio es lo dice su propio remoto.
  /// Aquí importa más que en ningún sitio, porque esta pantalla es la que se
  /// ve cuando todavía no hay nada configurado.
  Future<void> _choose() async {
    try {
      final chosen = await getDirectoryPath(
        confirmButtonText: 'Usar este repositorio',
      );
      if (chosen == null) return;
      await widget.session.addExistingRepository(chosen);
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
        widget.session.canUseClone && widget.session.workspace.isEmpty;
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
                    'Todavía no hay ningún repositorio de contenido abierto. '
                    'Añade uno: si ya lo tienes clonado en el disco, elige su '
                    'carpeta; si no, entra en GitHub desde Ajustes y añádelo '
                    'desde allí.',
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
                          label: const Text('Añadir una carpeta…'),
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
