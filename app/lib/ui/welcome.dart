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
library;

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
    if (widget.onFinished == null) widget.session.completeWelcome();
  }

  @override
  Widget build(BuildContext context) {
    // Escuchando la sesión: entrar en GitHub y clonar un repositorio pasan
    // por debajo de esta pantalla, y lo que el paso enseña depende de si ya
    // ocurrieron.
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => Scaffold(
        backgroundColor: didactaSurface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              // Los botones abajo y fuera del desplazamiento. Estaban dentro,
              // al final de la columna, y un paso que crece --unos dibujos,
              // un párrafo más-- los empuja fuera de la pantalla: quien lo
              // lee se queda sin «Siguiente» y sin «Saltar», y no hay nada
              // que sugiera que hay que bajar a buscarlos.
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _header(),
                          const SizedBox(height: 22),
                          _body(),
                          if (_working) ...[
                            const SizedBox(height: 14),
                            Working(step: _doing, line: _progress),
                          ] else if (_doing.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              _doing,
                              style: const TextStyle(
                                fontSize: 12,
                                color: didactaMuted,
                              ),
                            ),
                          ],
                          if (_problem != null) ...[
                            const SizedBox(height: 14),
                            Note('$_problem', tone: didactaTeacher),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: didactaRule)),
                    ),
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                    child: _footer(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      const DidactaMark(size: 34),
      const SizedBox(width: 10),
      const Text(
        'Didacta',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      const Spacer(),
      // Los puntos de los pasos. Sin números: lo que hace falta saber es
      // cuánto queda, no en cuál se está.
      for (final step in _steps)
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _steps.indexOf(step) <= _steps.indexOf(_step)
                ? didactaAccentDark
                : didactaRule,
          ),
        ),
    ],
  );

  Widget _body() => switch (_step) {
    WelcomeStep.what => const _WhatIsThis(),
    WelcomeStep.account => _Account(session: widget.session),
    WelcomeStep.repository => _Repository(
      session: widget.session,
      adder: _adder,
      working: _working,
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
          TextButton(
            key: const Key('welcome-back'),
            onPressed: _working ? null : () => _go(steps[at - 1]),
            child: const Text('Atrás'),
          ),
        const Spacer(),
        if (!last)
          TextButton(
            key: const Key('welcome-skip'),
            onPressed: _working ? null : _finish,
            child: const Text('Saltar la presentación'),
          ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('welcome-next'),
          onPressed: _working || blocked ? null : (last ? _finish : _next),
          child: Text(switch (_step) {
            WelcomeStep.what => 'Empezar',
            WelcomeStep.done => 'Empezar a trabajar',
            _ => 'Siguiente',
          }),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- los pasos ---

class _WhatIsThis extends StatelessWidget {
  const _WhatIsThis();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'El material se escribe una vez.\nLos PDF se generan.',
        style: TextStyle(
          fontSize: 25,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
      const SizedBox(height: 16),
      const _Claim(
        icon: Icons.file_copy_outlined,
        title: 'Microlecciones',
        body:
            'La pieza es una lección pequeña --una definición, un teorema, un '
            'problema-- que se escribe una vez y la usan los cursos que la '
            'necesiten, este año y los siguientes. No es una copia en cada '
            'curso: es la misma, así que corregir una errata es corregirla '
            'una vez.',
      ),
      const WelcomeArt(painter: ReusePainter()),
      const _Claim(
        icon: Icons.dynamic_feed_outlined,
        title: 'Una fuente, quince salidas',
        body:
            'Del mismo fichero salen las diapositivas, los apuntes, el libro, '
            'la hoja de problemas, el examen y la copia del profesor de cada '
            'uno. En los idiomas que tenga.',
      ),
      const WelcomeArt(painter: OutputsPainter()),
      const _Claim(
        icon: Icons.hub_outlined,
        title: 'Todo vive en GitHub',
        body:
            'Cada cambio queda con tu nombre y su mensaje, y puedes ver cómo '
            'estaba cualquier fichero en cualquier momento. Lo que compartes '
            'y lo que no lo decide a quién le das acceso.',
      ),
      const WelcomeArt(painter: HistoryPainter()),
    ],
  );
}

class _Claim extends StatelessWidget {
  const _Claim({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: didactaAccentDark),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(body, style: const TextStyle(fontSize: 12.5, height: 1.5)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Account extends StatelessWidget {
  const _Account({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    if (session.signedIn) {
      return _Step(
        title: 'Ya has entrado',
        body:
            'Como ${session.user?.login ?? 'tu cuenta de GitHub'}. A partir de '
            'aquí, lo que puedas leer y escribir lo dice GitHub: Didacta no '
            'mantiene ninguna otra lista.',
        child: const _Tick('Sesión iniciada'),
      );
    }
    return _Step(
      title: 'Entra en GitHub',
      body:
          'Tu material vive en repositorios de GitHub y cada cambio se guarda '
          'como un commit con tu nombre, así que hace falta una cuenta.\n\n'
          'La contraseña se teclea en github.com y en ningún otro sitio: '
          'Didacta te dará un código corto para autorizarla allí.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SignInForm(session: session),
        ),
      ),
    );
  }
}

class _Repository extends StatelessWidget {
  const _Repository({
    required this.session,
    required this.adder,
    required this.working,
  });

  final Session session;
  final RepositoryAdder adder;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final repos = session.workspace.repos;
    return _Step(
      title: 'Tu primer repositorio',
      body:
          'Un repositorio de contenido es uno de GitHub con material de '
          'Didacta dentro. Puedes abrir varios a la vez: la colección de '
          'problemas del departamento y tus apuntes son dos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final repo in repos)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _Tick(repo.id),
            ),
          if (repos.isNotEmpty) const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('welcome-add-repo'),
                onPressed: working ? null : () => adder.fromGitHub(context),
                icon: const Icon(Icons.add, size: 16),
                label: Text(repos.isEmpty ? 'Elegir en GitHub' : 'Añadir otro'),
              ),
              OutlinedButton.icon(
                key: const Key('welcome-add-folder'),
                onPressed: working ? null : () => adder.fromFolder(context),
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Ya lo tengo clonado'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '¿Empezar de cero? Crea un repositorio vacío en GitHub y elígelo '
            'aquí: Didacta verá que no tiene nada y se ofrecerá a prepararlo.',
            style: TextStyle(fontSize: 12, color: didactaMuted, height: 1.45),
          ),
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
    title: 'Lo que hace falta en tu ordenador',
    body:
        'Didacta no trabaja sola: pide prestado a cuatro programas. Escribir y '
        'organizar el material necesita el primero; sacar los PDF, los otros '
        'tres. Los que falten se instalan desde aquí.',
    child: ToolchainCheck(session: session, toolchain: toolchain),
  );
}

class _Done extends StatelessWidget {
  const _Done({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final repos = session.workspace.repos.length;
    return _Step(
      title: 'Listo',
      body: repos == 0
          ? 'No has abierto ningún repositorio todavía, y no pasa nada: la '
                'aplicación te lo recordará, y se añaden en Ajustes cuando '
                'quieras.'
          : 'Tienes ${repos == 1 ? 'un repositorio' : '$repos repositorios'} '
                'abiertos. Al entrar verás tus asignaturas; la biblioteca es '
                'todo el material junto.',
      child: const Text(
        'En cuanto entres, un recorrido corto te enseñará dónde está cada '
        'cosa. Puedes salirte en cualquier momento, y volver a verlo desde '
        'Ajustes.',
        style: TextStyle(fontSize: 12.5, height: 1.5, color: didactaMuted),
      ),
    );
  }
}

// ------------------------------------------------------------- las piezas ---

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.body, required this.child});

  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      const SizedBox(height: 8),
      Text(body, style: const TextStyle(fontSize: 13, height: 1.55)),
      const SizedBox(height: 18),
      child,
    ],
  );
}

class _Tick extends StatelessWidget {
  const _Tick(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.check_circle, size: 16, color: didactaAccentDark),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
    ],
  );
}
