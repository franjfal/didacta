/// La bienvenida: qué es esto, y cómo dejarlo listo para trabajar.
///
/// Se enseña **en lugar de** la aplicación la primera vez, y por la misma
/// razón que la puerta de GitHub: lo que hay detrás no sirve de nada hasta
/// que haya un repositorio abierto, y una biblioteca vacía con un aviso
/// arriba no explica ni qué es esto ni qué hay que hacer.
///
/// Lo que había antes era eso: la aplicación abría, no había nada, y una
/// franja decía «añade un repositorio en Ajustes». Quien ya sabía qué es
/// Didacta lo hacía; quien no, cerraba.
///
/// Cuatro decisiones:
///
/// **Primero qué es, después la configuración.** Tres afirmaciones y un
/// botón. Pedirle a alguien un token de GitHub antes de decirle para qué es
/// el programa es pedirle que confíe a ciegas.
///
/// **La configuración se hace aquí, no se explica.** El paso del repositorio
/// abre el mismo diálogo que Ajustes --[RepositoryAdder], que es de los dos--
/// y el de las herramientas las instala. Un asistente que dice «ahora ve a
/// Ajustes y…» es una página de documentación con botones.
///
/// **Se puede saltar todo.** Cada paso tiene su «ahora no», y saltárselo no
/// deja la aplicación rota: lo que falte lo volverá a decir la pantalla que
/// lo necesite, en su sitio y cuando haga falta.
///
/// **Y no vuelve.** Terminarla o saltarla la da por vista. Se vuelve a ver
/// desde Ajustes, que es donde alguien la buscaría.
///
/// Del aspecto, una cosa: es la primera pantalla de Didacta que ve alguien, y
/// era un formulario --texto pegado a la izquierda, tres dibujos quietos uno
/// debajo de otro--. Ahora va centrada, cada paso entra con una transición
/// corta, y lo que se explica se ve moverse: la lección que viaja a los
/// cursos, las salidas que salen del fichero. Con el sistema pidiendo menos
/// movimiento, todo se queda quieto y se lee igual.
library;

import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/toolchain.dart';
import '../state/session.dart';
import 'add_repository.dart';
import 'brand.dart';
import 'sign_in.dart';
import 'theme.dart';
import 'toolchain_check.dart';
import 'welcome_art.dart';
import 'working.dart';
import '../l10n/tr.dart';

/// Cuánto dura el paso de un paso a otro. Corto: es para que se note que la
/// pantalla ha cambiado, no para lucirse.
const Duration _turn = Duration(milliseconds: 220);

/// Qué pasos tiene la bienvenida.
enum WelcomeStep {
  /// Qué es Didacta. Tres afirmaciones.
  what,

  /// Entrar en GitHub.
  account,

  /// Las herramientas que tienen que estar en la máquina.
  ///
  /// **Antes que el repositorio, y no después como estaba el motor.** Clonar
  /// el primer repositorio se hace con git, así que un asistente que pide el
  /// repositorio primero manda a alguien a un paso que no puede terminar y le
  /// enseña el fallo de git en el peor sitio: dentro del diálogo de elegir
  /// repositorio, dicho en el idioma de git.
  tools,

  /// Abrir el primer repositorio de contenido.
  repository,

  /// Listo.
  done,
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.session,
    this.onFinished,
    this.toolchain,
  });

  final Session session;

  /// Con qué se comprueban las herramientas. Null es la de verdad.
  ///
  /// Se inyecta por lo mismo que en [ToolchainCheck]: comprobar lanza
  /// procesos, y un test de widgets no puede esperar a un proceso de verdad.
  final Toolchain? toolchain;

  /// Qué hacer al terminar. Por defecto, darla por vista.
  ///
  /// La aplicación pasa la suya porque además del «ya está vista» tiene que
  /// arrancar el tour, y eso no es cosa de esta pantalla.
  final VoidCallback? onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  WelcomeStep _step = WelcomeStep.what;

  /// Hacia dónde se va, para que la transición entre por el lado bueno.
  bool _forward = true;

  bool _working = false;
  String _doing = '';
  String _progress = '';
  Object? _problem;

  late final RepositoryAdder _adder = RepositoryAdder(
    session: widget.session,
    onBusy: (working) {
      if (mounted) setState(() => _working = working);
    },
    onStep: (what) {
      if (mounted) {
        setState(() {
          _doing = what;
          _progress = '';
        });
      }
    },
    onProgress: (line) {
      if (mounted) setState(() => _progress = line);
    },
    onProblem: (problem) {
      if (mounted) setState(() => _problem = problem);
    },
  );

  /// Los pasos que tocan en esta copia.
  ///
  /// El de las herramientas no sale donde no se puede compilar --la web--
  /// porque enseñar un paso que solo puede decir «aquí no» es alargar la
  /// bienvenida para no decir nada.
  List<WelcomeStep> get _steps => [
    WelcomeStep.what,
    WelcomeStep.account,
    if (widget.session.canCompile) WelcomeStep.tools,
    WelcomeStep.repository,
    WelcomeStep.done,
  ];

  void _go(WelcomeStep step) => setState(() {
    _forward = _steps.indexOf(step) >= _steps.indexOf(_step);
    _step = step;
    _problem = null;
    _doing = '';
    _progress = '';
  });

  void _next() {
    final steps = _steps;
    final at = steps.indexOf(_step);
    if (at < 0 || at + 1 >= steps.length) {
      _finish();
      return;
    }
    _go(steps[at + 1]);
  }

  void _finish() {
    widget.onFinished?.call();
    if (widget.onFinished == null) unawaited(widget.session.completeWelcome());
  }

  @override
  Widget build(BuildContext context) {
    // Escuchando la sesión: entrar en GitHub y clonar un repositorio pasan
    // por debajo de esta pantalla, y lo que el paso enseña depende de si ya
    // ocurrieron.
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => Scaffold(
        backgroundColor: context.palette.surface,
        body: WelcomeBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                _centred(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
                    child: _header(),
                  ),
                ),
                // Los botones abajo y fuera del desplazamiento. Estaban
                // dentro, al final de la columna, y un paso que crece --unos
                // dibujos, un párrafo más-- los empuja fuera de la pantalla:
                // quien lo lee se queda sin «Siguiente» y sin «Saltar», y no
                // hay nada que sugiera que hay que bajar a buscarlos.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                      child: ConstrainedBox(
                        // Centrado también en vertical cuando cabe: un paso
                        // corto pegado arriba deja media ventana vacía debajo
                        // y parece que falta algo.
                        constraints: BoxConstraints(
                          minHeight: math.max(0, constraints.maxHeight - 40),
                        ),
                        child: Center(child: _centred(_page())),
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.palette.card.withValues(alpha: 0.72),
                    border: Border(
                      top: BorderSide(color: context.palette.rule),
                    ),
                  ),
                  child: _centred(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 14),
                      child: _footer(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Con el ancho de la columna de texto, en el centro de la ventana.
  Widget _centred(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: child,
    ),
  );

  /// El paso, con lo que esté pasando debajo.
  Widget _page() => AnimatedSwitcher(
    duration: _turn,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) {
      final entering = child.key == ValueKey(_step);
      final from = Offset((_forward == entering ? 1 : -1) * 0.04, 0);
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: from, end: Offset.zero).animate(animation),
          child: child,
        ),
      );
    },
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    ),
    child: KeyedSubtree(
      key: ValueKey(_step),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _body(),
          if (_working) ...[
            const SizedBox(height: 18),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Working(step: _doing, line: _progress),
              ),
            ),
          ] else if (_doing.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              _doing,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
          ],
          if (_problem != null) ...[
            const SizedBox(height: 14),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Note('$_problem', tone: context.palette.teacher),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _header() {
    final steps = _steps;
    final at = steps.indexOf(_step);
    return Row(
      children: [
        const DidactaMark(size: 30),
        const SizedBox(width: 10),
        Text(
          tr('Didacta'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        // Los pasos, con su nombre donde cabe. Lo que hace falta saber es
        // cuánto queda y qué viene, no el número en el que se está.
        LayoutBuilder(
          builder: (context, constraints) => _Progress(
            names: [for (final step in steps) _stepName(step)],
            at: at,
            // Dentro de un `Row` el ancho no está acotado; se mira la
            // ventana entera.
            withNames: MediaQuery.sizeOf(context).width >= 720,
          ),
        ),
      ],
    );
  }

  static String _stepName(WelcomeStep step) => switch (step) {
    WelcomeStep.what => tr('Qué es'),
    WelcomeStep.account => tr('Cuenta'),
    WelcomeStep.tools => tr('Herramientas'),
    WelcomeStep.repository => tr('Material'),
    WelcomeStep.done => tr('Listo'),
  };

  Widget _body() => switch (_step) {
    WelcomeStep.what => const _WhatIsThis(),
    WelcomeStep.account => _Account(session: widget.session),
    WelcomeStep.repository => _Repository(
      session: widget.session,
      adder: _adder,
      working: _working,
      onOpened: () {
        if (mounted) _next();
      },
    ),
    WelcomeStep.tools => _Tools(
      session: widget.session,
      toolchain: widget.toolchain,
    ),
    WelcomeStep.done => _Done(session: widget.session),
  };

  Widget _footer() {
    final steps = _steps;
    final at = steps.indexOf(_step);
    final last = _step == WelcomeStep.done;

    // Qué hace falta para poder seguir, y qué se puede dejar para luego. Solo
    // la cuenta es obligatoria: sin sesión no hay nada que abrir.
    final blocked = _step == WelcomeStep.account && !widget.session.signedIn;

    return Row(
      children: [
        if (at > 0 && !last)
          TextButton.icon(
            key: const Key('welcome-back'),
            onPressed: _working ? null : () => _go(steps[at - 1]),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(tr('Atrás')),
          ),
        const Spacer(),
        if (!last)
          TextButton(
            key: const Key('welcome-skip'),
            onPressed: _working ? null : _finish,
            child: Text(tr('Saltar la presentación')),
          ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('welcome-next'),
          onPressed: _working || blocked ? null : (last ? _finish : _next),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(switch (_step) {
                WelcomeStep.what => tr('Empezar'),
                WelcomeStep.done => tr('Empezar a trabajar'),
                _ => tr('Siguiente'),
              }),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward, size: 16),
            ],
          ),
        ),
      ],
    );
  }
}

/// Los pasos arriba a la derecha: un punto por paso, alargado el actual.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.names,
    required this.at,
    required this.withNames,
  });

  final List<String> names;
  final int at;
  final bool withNames;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (index, name) in names.indexed) ...[
        if (index > 0) const SizedBox(width: 6),
        AnimatedContainer(
          duration: _turn * 1.5,
          curve: Curves.easeOutCubic,
          width: index == at ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: index <= at
                ? context.palette.accentDark
                : context.palette.faint.withValues(alpha: 0.45),
          ),
        ),
        if (withNames && index == at) ...[
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: context.palette.accentDark,
            ),
          ),
        ],
      ],
    ],
  );
}

// ------------------------------------------------------------- los pasos ---

/// Una de las tres ideas: su icono, su título, su texto y su dibujo.
class _Idea {
  const _Idea({
    required this.icon,
    required this.title,
    required this.body,
    required this.art,
  });

  final IconData icon;
  final String title;
  final String body;
  final ArtBuilder art;
}

List<_Idea> get _ideas => [
  _Idea(
    icon: Icons.file_copy_outlined,
    title: tr('Microlecciones'),
    body: tr(
      'La pieza es una lección pequeña --una definición, un teorema, un '
      'problema-- que se escribe una vez y la usan los cursos que la '
      'necesiten, este año y los siguientes. No es una copia en cada curso: '
      'es la misma, así que corregir una errata es corregirla una vez.',
    ),
    art: ReusePainter.new,
  ),
  _Idea(
    icon: Icons.dynamic_feed_outlined,
    title: tr('Una fuente, quince salidas'),
    body: tr(
      'Del mismo fichero salen las diapositivas, los apuntes, el libro, la '
      'hoja de problemas, el examen y la copia del profesor de cada uno. En '
      'los idiomas que tenga.',
    ),
    art: OutputsPainter.new,
  ),
  _Idea(
    icon: Icons.hub_outlined,
    title: tr('Todo vive en GitHub'),
    body: tr(
      'Cada cambio queda con tu nombre y su mensaje, y puedes ver cómo '
      'estaba cualquier fichero en cualquier momento. Lo que compartes y lo '
      'que no lo decide a quién le das acceso.',
    ),
    art: HistoryPainter.new,
  ),
];

class _WhatIsThis extends StatelessWidget {
  const _WhatIsThis();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _Rise(child: DidactaMark(size: 58)),
      SizedBox(height: 18),
      Text(
        tr('El material se escribe una vez.\nLos PDF se generan.'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 30,
          height: 1.18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      SizedBox(height: 10),
      Text(
        tr(
          'Tus clases en LaTeX, en piezas pequeñas que se reúnen en cada curso.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: context.palette.muted,
        ),
      ),
      SizedBox(height: 26),
      _Showcase(),
    ],
  );
}

/// Las tres ideas, una detrás de otra, con su dibujo moviéndose.
///
/// Una a la vez y no las tres apiladas: eran tres párrafos con tres dibujos
/// que había que bajar a buscar, y el tercero no lo leía nadie. Pasan solas
/// --despacio: da tiempo a leer el párrafo-- y se puede elegir cualquiera.
class _Showcase extends StatefulWidget {
  const _Showcase();

  @override
  State<_Showcase> createState() => _ShowcaseState();
}

class _ShowcaseState extends State<_Showcase>
    with SingleTickerProviderStateMixin {
  int _at = 0;

  late final AnimationController _dwell =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed || !mounted) return;
          setState(() => _at = (_at + 1) % _ideas.length);
          unawaited(_dwell.forward(from: 0));
        });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sin movimiento, tampoco pasan solas: que la pantalla cambie sin que
    // nadie la toque es justo lo que se pide que no pase.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _dwell.stop();
    } else if (!_dwell.isAnimating && _dwell.value == 0) {
      unawaited(_dwell.forward());
    }
  }

  @override
  void dispose() {
    _dwell.dispose();
    super.dispose();
  }

  void _show(int index) {
    setState(() => _at = index);
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      unawaited(_dwell.forward(from: 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final idea = _ideas[_at];
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, each) in _ideas.indexed)
              _IdeaTab(
                key: Key('welcome-idea-$index'),
                idea: each,
                selected: index == _at,
                progress: _dwell,
                onTap: () => _show(index),
              ),
          ],
        ),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(Radii.dialog),
            border: Border.all(color: context.palette.rule),
            boxShadow: [
              BoxShadow(
                color: context.palette.shadow.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: AnimatedSwitcher(
              duration: _turn * 1.5,
              child: Column(
                key: ValueKey(_at),
                children: [
                  WelcomeArt(builder: idea.art, height: 200),
                  const SizedBox(height: 14),
                  Text(
                    idea.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      idea.body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La pestaña de una idea, con la barrita de cuánto le queda si es la actual.
class _IdeaTab extends StatelessWidget {
  const _IdeaTab({
    super.key,
    required this.idea,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final _Idea idea;
  final bool selected;
  final Animation<double> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? context.palette.accentDark.withValues(alpha: 0.10)
        : context.palette.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: selected ? context.palette.accentDark : context.palette.rule,
        width: selected ? 1.3 : 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  idea.icon,
                  size: 16,
                  color: selected
                      ? context.palette.accentDark
                      : context.palette.muted,
                ),
                const SizedBox(width: 7),
                Text(
                  idea.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? context.palette.accentDark
                        : context.palette.ink,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: progress,
                builder: (context, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.value,
                  child: Container(height: 2, color: context.palette.accent),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Algo que entra subiendo un poco y apareciendo, una vez.
class _Rise extends StatelessWidget {
  const _Rise({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 12),
          child: Transform.scale(scale: 0.9 + 0.1 * value, child: child),
        ),
      ),
      child: child,
    );
  }
}

class _Account extends StatelessWidget {
  const _Account({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    if (session.signedIn) {
      return _Step(
        icon: Icons.verified_user_outlined,
        title: tr('Ya has entrado'),
        body: tr(
          'Como {0}. A partir de '
          'aquí, lo que puedas leer y escribir lo dice GitHub: Didacta no '
          'mantiene ninguna otra lista.',
          [session.user?.login ?? tr('tu cuenta de GitHub')],
        ),
        child: Center(child: _Tick(tr('Sesión iniciada'))),
      );
    }
    return _Step(
      icon: Icons.lock_person_outlined,
      title: tr('Entra en GitHub'),
      body: tr(
        'Tu material vive en repositorios de GitHub y cada cambio se guarda '
        'en el historial con tu nombre, así que hace falta una cuenta.\n\n'
        'La contraseña se teclea en github.com y en ningún otro sitio: '
        'Didacta te dará un código corto para autorizarla allí.',
      ),
      child: _Panel(child: SignInForm(session: session)),
    );
  }
}

class _Repository extends StatelessWidget {
  const _Repository({
    required this.session,
    required this.adder,
    required this.working,
    required this.onOpened,
  });

  final Session session;
  final RepositoryAdder adder;
  final bool working;

  /// Qué hacer cuando el ejemplo ha quedado abierto: pasar al último paso,
  /// que es lo que haría cualquiera después.
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final repos = session.workspace.repos;
    return _Step(
      icon: Icons.folder_special_outlined,
      title: repos.isEmpty ? tr('Tu primer material') : tr('Tu material'),
      body: tr(
        'El material vive en repositorios de GitHub con el contenido de '
        'Didacta dentro. Puedes abrir varios a la vez: la colección de '
        'problemas del departamento y tus apuntes son dos.',
      ),
      child: Column(
        children: [
          if (repos.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 6,
              children: [for (final repo in repos) _Tick(repo.id)],
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              // Tres columnas del mismo alto si caben, una debajo de otra si
              // no: tres tarjetas estrujadas se leen peor que tres filas.
              final wide = constraints.maxWidth >= 660;
              final choices = [
                _Choice(
                  stretch: wide,
                  icon: Icons.auto_stories_outlined,
                  title: tr('Probar con un ejemplo'),
                  body: tr(
                    'Una asignatura pequeña con un tema, una hoja de '
                    'problemas y lecciones en varios idiomas. Se crea en tu '
                    'cuenta, privada, para que la toques sin miedo.',
                  ),
                  badge: tr('Para empezar'),
                  action: FilledButton.icon(
                    key: const Key('welcome-try-example'),
                    onPressed: working
                        ? null
                        : () async {
                            if (await adder.example(context)) onOpened();
                          },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(tr('Crear el ejemplo')),
                  ),
                ),
                _Choice(
                  stretch: wide,
                  icon: Icons.cloud_download_outlined,
                  title: tr('Uno tuyo de GitHub'),
                  body: tr(
                    'Elige los repositorios con tu material. Si está vacío, '
                    'Didacta se ofrecerá a prepararlo.',
                  ),
                  action: OutlinedButton.icon(
                    key: const Key('welcome-add-repo'),
                    onPressed: working ? null : () => adder.fromGitHub(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      repos.isEmpty
                          ? tr('Elegir en GitHub')
                          : tr('Añadir otro'),
                    ),
                  ),
                ),
                _Choice(
                  stretch: wide,
                  icon: Icons.folder_open_outlined,
                  title: tr('Ya está en tu disco'),
                  body: tr(
                    'Si ya lo tienes clonado, ábrelo desde su carpeta: no se '
                    'vuelve a descargar.',
                  ),
                  action: OutlinedButton.icon(
                    key: const Key('welcome-add-folder'),
                    onPressed: working ? null : () => adder.fromFolder(context),
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: Text(tr('Ya lo tengo clonado')),
                  ),
                ),
              ];
              if (!wide) {
                return Column(
                  children: [
                    for (final (index, choice) in choices.indexed) ...[
                      if (index > 0) const SizedBox(height: 12),
                      choice,
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, choice) in choices.indexed) ...[
                      if (index > 0) const SizedBox(width: 12),
                      Expanded(child: choice),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            tr(
              '¿Empezar de cero? Crea un repositorio vacío en GitHub y elígelo '
              'aquí: Didacta verá que no tiene nada y se ofrecerá a prepararlo.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.muted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una de las maneras de abrir material, en su tarjeta.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    this.badge,
    this.stretch = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  /// Una etiqueta arriba, para la que se recomienda.
  final String? badge;

  /// Si va en una fila de tarjetas del mismo alto: entonces el botón baja al
  /// pie, y los tres quedan a la misma altura.
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final featured = badge != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(Radii.dialog),
        border: Border.all(
          color: featured ? context.palette.accentDark : context.palette.rule,
          width: featured ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: context.palette.shadow.withValues(
              alpha: featured ? 0.07 : 0.04,
            ),
            blurRadius: featured ? 18 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(icon: icon, size: 36),
              const Spacer(),
              if (featured)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: context.palette.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: context.palette.accentDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: context.palette.muted,
            ),
          ),
          if (stretch) const Spacer() else const SizedBox(height: 14),
          if (stretch) const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }
}

/// El paso de las herramientas.
///
/// Era «el motor», y contaba dos de las cuatro piezas --LaTeX y el motor-- en
/// prosa, con un solo botón que descargaba una de ellas. Las otras dos --git y
/// Python-- no se mencionaban, y faltando cualquiera de ellas la aplicación
/// fallaba más tarde y en otro sitio: al clonar el primer repositorio, o al
/// pulsar compilar.
///
/// Ahora las cuatro están en la misma lista, con lo que cada una hace, si está
/// y dónde. La prosa sobra: una fila que dice «Git 2.39.5, /usr/bin/git»
/// explica más que un párrafo sobre control de versiones.
class _Tools extends StatelessWidget {
  const _Tools({required this.session, this.toolchain});

  final Session session;
  final Toolchain? toolchain;

  @override
  Widget build(BuildContext context) => _Step(
    icon: Icons.handyman_outlined,
    title: tr('Lo que hace falta en tu ordenador'),
    body: tr(
      'Didacta no trabaja sola: pide prestado a cuatro programas. Escribir y '
      'organizar el material necesita el primero; sacar los PDF, los otros '
      'tres. Los que falten se instalan desde aquí.',
    ),
    child: _Panel(
      maxWidth: 680,
      child: ToolchainCheck(session: session, toolchain: toolchain),
    ),
  );
}

class _Done extends StatelessWidget {
  const _Done({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final repos = session.workspace.repos.length;
    return _Step(
      icon: Icons.check_rounded,
      celebrate: true,
      title: tr('Listo'),
      body: repos == 0
          ? tr(
              'No has abierto ningún repositorio todavía, y no pasa nada: la '
              'aplicación te lo recordará, y se añaden en Ajustes cuando '
              'quieras.',
            )
          : tr(
              'Tienes {0}. '
              'Al entrar verás tus asignaturas; la biblioteca es todo el '
              'material junto.',
              [
                repos == 1
                    ? tr('un repositorio abierto')
                    : tr('{0} repositorios abiertos', [repos]),
              ],
            ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const WelcomeArt(
              builder: TourPainter.new,
              height: 170,
              period: Duration(seconds: 8),
              rest: 0.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tr(
              'En cuanto entres, un recorrido corto te enseñará dónde está cada '
              'cosa: las asignaturas por dentro, la biblioteca y sus filtros, y '
              'una lección con sus idiomas y lo que se compila. Puedes salirte '
              'en cualquier momento y volver a verlo desde Ajustes.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: context.palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- las piezas ---

/// Un paso: su icono en un círculo, el título, el texto y lo que se hace.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    required this.child,
    this.celebrate = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget child;

  /// Con el círculo relleno y entrando con un rebote: el último paso.
  final bool celebrate;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _Rise(
        child: _Badge(icon: icon, size: 56, filled: celebrate),
      ),
      const SizedBox(height: 16),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, height: 1.55),
        ),
      ),
      const SizedBox(height: 24),
      child,
    ],
  );
}

/// Un icono en un círculo verde claro.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.size, this.filled = false});

  final IconData icon;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled
          ? context.palette.accentDark
          : context.palette.accent.withValues(alpha: 0.14),
      boxShadow: filled
          ? [
              BoxShadow(
                color: context.palette.accentDark.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ]
          : null,
    ),
    child: Icon(
      icon,
      size: size * 0.5,
      color: filled ? context.palette.onAccent : context.palette.accentDark,
    ),
  );
}

/// Una tarjeta blanca para un formulario, centrada.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.maxWidth = 520});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(Radii.dialog),
          border: Border.all(color: context.palette.rule),
          boxShadow: [
            BoxShadow(
              color: context.palette.shadow.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    ),
  );
}

class _Tick extends StatelessWidget {
  const _Tick(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.check_circle, size: 16, color: context.palette.accentDark),
      const SizedBox(width: 8),
      Flexible(child: Text(text, style: const TextStyle(fontSize: 12.5))),
    ],
  );
}
