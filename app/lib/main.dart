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

import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/diagnostics.dart';
import 'data/draft_store.dart';
import 'data/legacy_identity.dart';
import 'data/app_info.dart';
import 'data/github.dart' show didactaAppClientId;
import 'data/catalogue_source.dart';
import 'data/preferences.dart';
import 'data/repository_access.dart';
import 'router.dart';
import 'data/mcp_process.dart';
import 'state/appearance.dart';
import 'state/mcp_service.dart';
import 'state/session.dart';
import 'state/update_service.dart';
import 'ui/platform_menus.dart';
import 'ui/sign_in.dart';
import 'ui/brand.dart' show DidactaMark;
import 'ui/theme.dart';
import 'ui/tour.dart';
import 'ui/unsaved_dialog.dart';
import 'ui/update_section.dart';
import 'ui/welcome.dart';
import 'l10n/tr.dart';

/// Where the generated catalogue is served from.
const String indexBase = String.fromEnvironment(
  'DIDACTA_INDEX',
  defaultValue: 'generated',
);

/// El Client ID de la OAuth App con la que se entra en GitHub.
///
/// **Va escrito aquí a propósito, y no es un descuido.** Un Client ID es
/// público por definición: viaja en la URL de cada autorización, así que ya lo
/// ve en la barra de direcciones cualquiera que entre. El secreto de una
/// aplicación de OAuth es el *client secret*, y el device flow --que es el que
/// usa Didacta-- no lo usa; existe justamente porque una aplicación de
/// escritorio no puede esconder un secreto dentro de un binario que reparte.
/// Lo hacen igual `gh`, VS Code y GitHub Desktop.
///
/// Lo que se gana es lo que decide si alguien llega a usar esto: al abrir
/// Didacta por primera vez hay **un botón**, y no un campo pidiendo que te
/// crees una aplicación de OAuth en GitHub antes de poder empezar.
///
/// Se puede cambiar sin recompilar --en Ajustes, o con la define-- para
/// quien monte su propio despliegue.
const String githubClientId = String.fromEnvironment(
  'DIDACTA_GITHUB_CLIENT',
  defaultValue: 'Ov23liZqSOY4xMvnXU4Z',
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
  //
  // Y al registro de diagnóstico, en su fichero: la consola no la mira nadie
  // fuera de un terminal, y el informe de Ajustes → Ayuda sale de ahí.
  Diagnostics.instance.useDefaultFile();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Didacta · error: ${details.exception}\n${details.stack}');
    Diagnostics.instance.note('flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Didacta · error sin capturar: $error\n$stack');
    Diagnostics.instance.note('sin capturar', error, stack);
    // Handled: an unhandled asynchronous error terminates the isolate, and
    // a failed keychain read is not worth the whole application.
    return true;
  };

  // Lo que se guardó cuando la aplicación se llamaba es.uv.didacta. Antes de
  // tocar los ajustes: en Windows y en Linux viven en esa carpeta, y leerlos
  // primero sería arrancar con los de una instalación vacía.
  await bringLegacyData();

  // Dónde se clonan los repositorios, si no se ha dicho otra cosa. En el
  // navegador no hay carpeta personal, y `Platform.environment` lanza.
  final home = kIsWeb
      ? ''
      : (Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '');

  final session = Session(
    catalogueSource: const HttpCatalogueSource(base: indexBase),
    tokenStore: TokenStore(),
    preferences: StoredPreferences(
      defaultClonePath: '',
      defaultEnginePath: enginePath,
      // La GitHub App, cuando existe; si no, la OAuth App de siempre. Y el de
      // la OAuth App guardado al entrar deja de valer entonces: era el de
      // salida, no uno elegido.
      defaultClientId: didactaAppClientId.isNotEmpty
          ? didactaAppClientId
          : githubClientId,
      replacedClientIds: [if (didactaAppClientId.isNotEmpty) githubClientId],
    ),
    drafts: diskDrafts(),
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

  // Claro u oscuro, leído antes de la primera pantalla: leerlo después sería
  // un parpadeo en claro para quien trabaja en oscuro.
  final appearance = Appearance(preferences: session.preferences);
  await appearance.load();

  runApp(
    DidactaApp(
      session: session,
      updates: updates,
      mcp: mcp,
      tour: tour,
      appearance: appearance,
    ),
  );
}

class DidactaApp extends StatefulWidget {
  const DidactaApp({
    super.key,
    required this.session,
    required this.updates,
    this.mcp,
    this.tour,
    this.appearance,
  });

  final Session session;
  final UpdateService updates;

  /// Claro u oscuro. Opcional: sin él, lo que diga el sistema, sin recordarlo.
  final Appearance? appearance;

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
  ///
  /// Y la credencial de GitHub, si caduca: con el portátil dormido, el aviso
  /// de renovarla puede llegar tarde, y volver es cuando se va a enviar algo.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onShow: () => unawaited(widget.session.backInFront()),
    onRestart: () => unawaited(widget.session.backInFront()),
  );

  late final Appearance _appearance = widget.appearance ?? Appearance();

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
        openRunner: () =>
            UnavailableRunner(tr('Esta copia se ha montado sin servidor MCP.')),
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
    if (widget.appearance == null) _appearance.dispose();
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
        ChangeNotifierProvider.value(value: _appearance),
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
  GoRouter? _router;

  /// Cerrar Didacta con algo escrito y sin guardar pregunta antes.
  ///
  /// Aquí y no en la aplicación de arriba: el diálogo necesita el Navigator
  /// del router, y el router vive aquí.
  late final AppLifecycleListener _exit = AppLifecycleListener(
    onExitRequested: _exitRequested,
  );

  @override
  void initState() {
    super.initState();
    _exit;
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _exitRequested() async {
    final what = context.read<Session>().unsaved.what;
    final navigator = _router?.routerDelegate.navigatorKey.currentContext;
    if (what.isEmpty || navigator == null) return AppExitResponse.exit;
    final leave = await confirmLeaving(
      navigator,
      what,
      leave: tr('Cerrar sin guardar'),
    );
    return leave ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) {
    // Solo lo que se pinta aquí arriba, y no la sesión entera: la raíz
    // escuchando todo se reconstruía con cada aviso --decenas por guardado--
    // y con ella la aplicación. Cada pantalla escucha lo suyo.
    final session = context.read<Session>();
    final textScale = context.select<Appearance, double>(
      (appearance) => appearance.textScale,
    );
    // La paleta va en el tema de cada `MaterialApp`: cambiar de modo es
    // cambiar el tema, y lo que la lee con `context.palette` se vuelve a
    // construir solo, sin perder lo que haya a medio escribir.
    final theme = didactaTheme(
      context.select<Appearance, DidactaPalette>(
        (appearance) => appearance.palette,
      ),
    );
    context.select<Session, Object?>(
      (s) => (
        s.welcomeDone,
        s.signInState,
        s.state,
        s.startStep,
        s.needsRepository,
        s.catalogueOrNull?.units.isEmpty,
        s.catalogueOrNull?.errors,
        s.indexNote,
        // Lo que enseñan la puerta y la pantalla de fallo, que reciben la
        // sesión de aquí y no la escuchan por su cuenta.
        s.signInProblem,
        s.error,
        s.enginePath,
      ),
    );

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
        title: tr('Didacta'),
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        localizationsDelegates: didactaLocalizations,
        supportedLocales: didactaLocales,
        locale: didactaLocale,
        builder: scaledText(textScale),
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
        title: tr('Didacta'),
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        localizationsDelegates: didactaLocalizations,
        supportedLocales: didactaLocales,
        locale: didactaLocale,
        builder: scaledText(textScale),
        home: SignInGate(session: session),
      );
    }

    return switch (session.state) {
      LoadState.loading => _Splash(step: session.startStep),
      LoadState.failed => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        localizationsDelegates: didactaLocalizations,
        supportedLocales: didactaLocales,
        locale: didactaLocale,
        builder: scaledText(textScale),
        home: _LoadFailure(session: session),
      ),
      LoadState.ready when session.signInState == SignInState.checking =>
        const _Splash(),
      LoadState.ready => _buildApp(session, textScale, theme),
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

  /// El contexto del Navigator del router.
  ///
  /// Para abrir un diálogo desde lo que se monta en el `builder`: está por
  /// encima del `Router`, así que no tiene un Navigator al que pedírselo.
  BuildContext _navigatorContext() =>
      _router!.routerDelegate.navigatorKey.currentContext!;

  Widget _buildApp(Session session, double textScale, ThemeData theme) {
    // Built once and kept: rebuilding a GoRouter throws away the history,
    // which on the web means the back button stops working.
    if (_routerFor != session) {
      final router = buildRouter(session);
      _router = router;
      _routerFor = session;
      // El tour se crea antes que el router, y para cambiar de pantalla
      // necesita este: desde aquí arriba --el `builder`, por encima del
      // `Router`-- no hay `GoRouter.of` que encuentre nada.
      context.read<TourController>().attach(
        navigate: router.go,
        locate: () => router.routeInformationProvider.value.uri.toString(),
        session: session,
      );
    }
    // El router, también por encima de la aplicación: lo busca quien tiene
    // que ofrecer un botón que navega desde un aviso --«Volver a entrar»-- y
    // solo tiene el `ScaffoldMessenger`, que está por encima del `Router`.
    return Provider<GoRouter>.value(
      value: _router!,
      child: MaterialApp.router(
        title: tr('Didacta'),
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        localizationsDelegates: didactaLocalizations,
        supportedLocales: didactaLocales,
        locale: didactaLocale,
        routerConfig: _router,
        // Lo que va aquí está **por encima** del router, no por debajo: el
        // `builder` envuelve al `Router`, y go_router pone lo suyo más abajo,
        // alrededor del Navigator. Desde este contexto hay tema y
        // ScaffoldMessenger, pero ni `GoRouter.of` ni `Navigator.of` encuentran
        // nada. Así que lo que navega recibe el `go` del router, y lo que abre
        // un diálogo, el contexto de su Navigator.
        builder: scaledText(
          textScale,
          (context, child) => PlatformMenus(
            navigate: _router!.go,
            dialogContext: _navigatorContext,
            // Pintado, y no transparente como estaba.
            //
            // Esto era un fallo que se veía feísimo y solo en según qué máquina:
            // aquí arriba, por encima del Scaffold, **no hay nada que pinte el
            // fondo**, así que un banner con alfa se componía sobre el fondo
            // nativo de la ventana. En un macOS en modo oscuro eso es negro, y
            // un aviso salía como una franja negra con el texto
            // ilegible. Un color de fondo opaco lo arregla y no cuesta nada.
            child: ColoredBox(
              color: context.palette.surface,
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
                      UpdateBanner(dialogContext: _navigatorContext),
                      if (session.needsRepository &&
                          session.catalogue.units.isEmpty)
                        _NoRepositoriesBanner(navigate: _router!.go),
                      if (session.catalogue.errors.isNotEmpty)
                        _ErrorBanner(
                          errors: session.catalogue.errors,
                          dialogContext: _navigatorContext,
                        ),
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
        ),
      ),
    );
  }
}

/// El tamaño del texto elegido en Ajustes, por encima del que diga el
/// sistema, para todo lo que cuelga de un `MaterialApp`.
///
/// En su `builder` y no por fuera: la aplicación pone su propio `MediaQuery`
/// a partir de la ventana, y uno puesto más arriba no llegaría. Y siempre
/// con él, también en el tamaño normal: que apareciera y desapareciera
/// cambiaría la forma del árbol, y con ella se perdería la pantalla abierta,
/// el texto a medio escribir y el historial de navegación.
@visibleForTesting
TransitionBuilder scaledText(double scale, [TransitionBuilder? inner]) =>
    (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          textScaler: scale == 1
              ? media.textScaler
              : TextScaler.linear(media.textScaler.scale(1) * scale),
        ),
        child: inner == null
            ? (child ?? const SizedBox.shrink())
            : inner(context, child),
      );
    };

/// La pantalla de carga: la marca y qué se está haciendo.
///
/// Una rueda sola en medio de una ventana vacía no dice si falta un segundo
/// o si algo se ha colgado. El paso en curso --«Leyendo el catálogo»-- sí, y
/// es lo que alguien dice al pedir ayuda cuando se queda ahí.
class _Splash extends StatelessWidget {
  const _Splash({this.step});

  final String? step;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: didactaTheme(
      context.select<Appearance, DidactaPalette>(
        (appearance) => appearance.palette,
      ),
    ),
    themeAnimationDuration: Duration.zero,
    localizationsDelegates: didactaLocalizations,
    supportedLocales: didactaLocales,
    locale: didactaLocale,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DidactaMark(size: 56),
              const SizedBox(height: 14),
              Text(
                tr('Didacta'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 10),
              Text(
                step ?? tr('Abriendo'),
                key: const Key('splash-step'),
                style: TextStyle(fontSize: 12.5, color: context.palette.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _IndexBanner extends StatelessWidget {
  const _IndexBanner({required this.note, required this.onDismiss});

  final String note;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.tint(context.palette.accent, 0.10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 6, 5),
      child: Row(
        children: [
          Icon(Icons.autorenew, size: 15, color: context.palette.accentDark),
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
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 15, color: context.palette.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Todavía no hay ningún repositorio con el que trabajar.
class _NoRepositoriesBanner extends StatelessWidget {
  const _NoRepositoriesBanner({required this.navigate});

  /// El `go` del router: esta franja está por encima de él.
  final void Function(String route) navigate;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.accentDark.withValues(alpha: 0.10),
    child: InkWell(
      onTap: () => navigate(Routes.settings(section: 'repositorios')),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.folder_open_outlined, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(
                  'Todavía no hay ningún repositorio abierto. Añade uno en '
                  'Ajustes: desde GitHub, o eligiendo una carpeta que ya tengas '
                  'clonada en el disco.',
                ),
                style: TextStyle(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('go-to-settings'),
              onPressed: () =>
                  navigate(Routes.settings(section: 'repositorios')),
              child: Text(tr('Abrir Ajustes')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.errors, required this.dialogContext});

  final List<String> errors;

  /// De dónde se abre el diálogo: esta franja está por encima del Navigator.
  final BuildContext Function() dialogContext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.tint(context.palette.teacher, 0.09),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: context.palette.teacher,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                errors.length == 1
                    ? errors.first
                    : tr(
                        '{0} problemas al leer el repositorio: '
                        '{1}',
                        [errors.length, errors.first],
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              child: Text(tr('Ver todos')),
              onPressed: () => showDialog<void>(
                context: dialogContext(),
                builder: (context) => AlertDialog(
                  title: Text(tr('Problemas al leer el repositorio')),
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
                      child: Text(tr('Cerrar')),
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

  bool _rebuilding = false;

  /// Si hay con qué regenerarlo: el motor y la copia del repositorio.
  bool get _canRebuild => widget.session.liveCompiler() != null;

  /// Regenera el índice con el motor y vuelve a arrancar.
  ///
  /// Esta pantalla mandaba al terminal a escribir `didacta index`, cuando la
  /// aplicación sabe hacerlo sola: es lo mismo que hace al volver a la
  /// ventana si el índice está viejo.
  Future<void> _rebuild() async {
    setState(() {
      _rebuilding = true;
      _problem = null;
    });
    try {
      await widget.session.refreshIndex(force: true);
      await widget.session.start();
    } catch (problem) {
      if (mounted) setState(() => _problem = problem);
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  /// Añadir una carpeta que ya esté clonada, y volver a arrancar.
  ///
  /// Sin pasar por GitHub: de qué repositorio es lo dice su propio remoto.
  /// Aquí importa más que en ningún sitio, porque esta pantalla es la que se
  /// ve cuando todavía no hay nada configurado.
  Future<void> _choose() async {
    try {
      final chosen = await getDirectoryPath(
        confirmButtonText: tr('Usar este repositorio'),
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
                Row(
                  children: [
                    Icon(Icons.error_outline, color: context.palette.teacher),
                    SizedBox(width: 8),
                    // Expanded: es la pantalla que se ve en un móvil cuando
                    // no hay catálogo, y una cabecera que desborda tapa el
                    // motivo, que es lo único que hay aquí.
                    Expanded(
                      child: Text(
                        tr('No se pudo cargar el catálogo'),
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
                  tr('Origen: {0}', [where]),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: context.palette.muted,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  error.toString(),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 20),
                if (noClone) ...[
                  Text(
                    tr(
                      'Todavía no hay ningún repositorio de contenido abierto. '
                      'Añade uno: si ya lo tienes clonado en el disco, elige su '
                      'carpeta; si no, entra en GitHub desde Ajustes y añádelo '
                      'desde allí.',
                    ),
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      'Es la carpeta que tiene dentro didacta.yaml, content/ y '
                      'courses/.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ] else if (_canRebuild) ...[
                  Text(
                    tr(
                      'El catálogo lo genera el motor, y Didacta lo puede '
                      'regenerar ahora mismo a partir de lo que hay en el disco.',
                    ),
                    style: TextStyle(fontSize: 13),
                  ),
                ] else ...[
                  Text(
                    tr(
                      'El catálogo lo genera el motor, que no está configurado. '
                      'Se elige en Ajustes; mientras tanto, desde el repositorio '
                      'de contenido:',
                    ),
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: context.palette.terminal,
                    child: const SelectableText(
                      'didacta index',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: didactaOnTerminal,
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
                          label: Text(tr('Añadir una carpeta…')),
                          onPressed: _choose,
                        ),
                      if (!noClone && _canRebuild) ...[
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(tr('Reintentar')),
                          onPressed: _rebuilding ? null : onRetry,
                        ),
                        FilledButton.icon(
                          key: const Key('rebuild-index'),
                          icon: _rebuilding
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.build_outlined, size: 18),
                          label: Text(
                            _rebuilding
                                ? tr('Regenerando…')
                                : tr('Regenerar el índice'),
                          ),
                          onPressed: _rebuilding ? null : _rebuild,
                        ),
                      ] else
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(tr('Reintentar')),
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
