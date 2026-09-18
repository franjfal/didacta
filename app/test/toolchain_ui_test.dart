/// La lista de herramientas: lo que enseña, y sobre todo lo que dice al fallar.
///
/// El camino feliz de esta pantalla --falta algo, se pulsa, aparece-- es el
/// menos interesante de los tres. Los otros dos son los que deciden si alguien
/// sigue usando Didacta:
///
/// **Instalar y que falle.** Pasa constantemente: no hay Homebrew, la máquina
/// es de la universidad y no se puede instalar nada, la red de la facultad
/// corta CTAN. Lo que se comprueba aquí es que el modal traiga las tres cosas
/// que permiten salir del paso --qué se intentó, qué contestó, cómo se hace a
/// mano-- y no un «no se pudo instalar» a secas.
///
/// **Instalar sin error y que siga sin aparecer.** El peor de todos, porque
/// parece que ha ido bien. Un instalador que deja el programa en una carpeta
/// que no es ninguna de las de siempre, y un tick verde que miente.
@TestOn('vm')
library;

import 'package:didacta_app/data/toolchain.dart';
import 'package:didacta_app/model/toolchain.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/toolchain_check.dart';
import 'package:didacta_app/ui/welcome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

FakeSession sessionForTools() => FakeSession(
  gatewayOverride: FakeGateway(),
  catalogue: catalogueWith(defaultUnits()),
);

Future<void> pumpCheck(
  WidgetTester tester,
  FakeToolchain toolchain, {
  Session? session,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ToolchainCheck(
            session: session ?? sessionForTools(),
            toolchain: toolchain,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('con todo puesto, no hay nada que pulsar', (tester) async {
    await pumpCheck(tester, FakeToolchain(present: ToolId.values.toSet()));

    expect(find.textContaining('Está todo'), findsOneWidget);
    // Ni un botón de instalar: una lista de botones que no hacen falta es
    // una lista que invita a tocar lo que funciona.
    expect(find.widgetWithText(OutlinedButton, 'Instalar'), findsNothing);
    expect(find.byKey(const Key('install-missing')), findsNothing);
  });

  testWidgets('dice dónde está cada una, no solo que está', (tester) async {
    await pumpCheck(tester, FakeToolchain(present: ToolId.values.toSet()));

    // La ruta y la versión. Es lo que contesta «¿cuál de los dos gits está
    // usando?», que es la pregunta del día que algo va raro.
    expect(find.text('/de/mentira/git'), findsOneWidget);
    expect(find.text('1.2.3'), findsNWidgets(ToolId.values.length));
  });

  testWidgets('lo que falta se dice, y con un botón al lado', (tester) async {
    await pumpCheck(
      tester,
      FakeToolchain(present: const {ToolId.git, ToolId.python}),
    );

    expect(find.byKey(const Key('install-latex')), findsOneWidget);
    expect(find.byKey(const Key('install-engine')), findsOneWidget);
    expect(find.byKey(const Key('install-git')), findsNothing);
    // Dos cosas faltando: el botón de hacerlo todo.
    expect(find.byKey(const Key('install-missing')), findsOneWidget);
    expect(find.textContaining('Está todo'), findsNothing);
  });

  testWidgets('instalar, y después comprobar que ha aparecido', (tester) async {
    // El paso que la pantalla no puede saltarse: instalar no es terminar.
    // Lo que cuenta es que Didacta la encuentre después.
    final toolchain = FakeToolchain(
      present: const {ToolId.python, ToolId.latex, ToolId.engine},
    );
    await pumpCheck(tester, toolchain);

    await tester.tap(find.byKey(const Key('install-git')));
    await settle(tester);

    expect(toolchain.installed, hasLength(1));
    expect(toolchain.present, contains(ToolId.git));
    expect(find.byKey(const Key('install-git')), findsNothing);
    expect(find.text('/de/mentira/git'), findsOneWidget);
    expect(find.textContaining('Está todo'), findsOneWidget);
  });

  testWidgets('en macOS con Homebrew se instala con Homebrew', (tester) async {
    final toolchain = FakeToolchain(
      present: const {ToolId.python, ToolId.latex, ToolId.engine},
    );
    await pumpCheck(tester, toolchain);

    await tester.tap(find.byKey(const Key('install-git')));
    await settle(tester);

    expect(toolchain.installed.single.label, 'Instalar con Homebrew');
  });

  testWidgets('sin Homebrew, el instalador de Apple', (tester) async {
    // Y el de Apple termina fuera de Didacta, así que la fila no puede decir
    // «instalado»: queda esperando y pide volver a comprobar.
    final toolchain = FakeToolchain(
      present: const {ToolId.python, ToolId.latex, ToolId.engine},
      available: const {},
      appears: false,
    );
    await pumpCheck(tester, toolchain);

    await tester.tap(find.byKey(const Key('install-git')));
    await settle(tester);

    expect(
      toolchain.installed.single.label,
      'Instalar las herramientas de Apple',
    );
    expect(toolchain.installed.single.handsOver, isTrue);
    expect(
      find.textContaining('Se está instalando fuera de Didacta'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('cuando falla, el modal dice qué pasó y cómo hacerlo a mano', (
    tester,
  ) async {
    final toolchain = FakeToolchain(
      present: const {ToolId.python, ToolId.latex, ToolId.engine},
      failure: const ToolInstallException(
        'La instalación terminó con un error (código 1).',
        detail: 'Error: No available formula with the name "git"',
      ),
    );
    await pumpCheck(tester, toolchain);

    await tester.tap(find.byKey(const Key('install-git')));
    await settle(tester);

    expect(find.byType(ToolProblemDialog), findsOneWidget);
    expect(find.text('Git: no se pudo instalar'), findsOneWidget);
    // Lo que contestó el proceso, tal cual: es lo que alguien va a pegar en
    // una búsqueda.
    expect(find.textContaining('No available formula'), findsOneWidget);
    // Y cómo salir del paso sin Didacta.
    expect(find.text('Cómo hacerlo a mano'), findsOneWidget);
    expect(find.textContaining('brew install git'), findsOneWidget);
    expect(find.byKey(const Key('open-guide')), findsOneWidget);
  });

  testWidgets('el modal dice dónde se ha mirado', (tester) async {
    // Para el caso frecuente de verdad: está instalado, pero en un sitio que
    // no es ninguno de los de siempre. Sin la lista, «instálalo» es el
    // consejo equivocado y no hay forma de saberlo.
    final toolchain = FakeToolchain(
      present: const {ToolId.python, ToolId.latex, ToolId.engine},
      failure: const ToolInstallException('no'),
    );
    await pumpCheck(tester, toolchain);

    await tester.tap(find.byKey(const Key('install-git')));
    await settle(tester);

    expect(
      find.textContaining('Didacta la ha buscado en: /de/mentira'),
      findsOneWidget,
    );
  });

  testWidgets('instalar sin error y que no aparezca no cuenta como hecho', (
    tester,
  ) async {
    // El peor final de los tres, porque parece que ha ido bien. Se avisa en
    // lugar de dejar un tick verde que miente.
    final toolchain = FakeToolchain(
      present: const {ToolId.git, ToolId.python, ToolId.engine},
      appears: false,
    );
    await pumpCheck(tester, toolchain);

    await tester.tap(find.byKey(const Key('install-latex')));
    await settle(tester);
    // LaTeX se elige antes de instalarse.
    await tester.tap(find.byKey(const Key('latex-choose')));
    await settle(tester);

    expect(find.byType(ToolProblemDialog), findsOneWidget);
    expect(find.textContaining('sigue sin aparecer'), findsOneWidget);
  });

  testWidgets('en Linux, donde hace falta sudo, no se anuncia un fallo', (
    tester,
  ) async {
    // Instalar paquetes del sistema pide la contraseña de administrador, y
    // eso Didacta no lo intenta siquiera. Titular «no se pudo instalar» algo
    // que no se ha intentado sería anunciar un fallo que no ha ocurrido.
    final toolchain = FakeToolchain(
      host: Host.linux,
      present: const {ToolId.python, ToolId.latex, ToolId.engine},
    );
    await pumpCheck(tester, toolchain);

    await tester.tap(find.byKey(const Key('install-git')));
    await settle(tester);

    expect(find.text('Git: cómo instalarlo'), findsOneWidget);
    expect(find.text('Git: no se pudo instalar'), findsNothing);
    expect(find.textContaining('sudo apt install git'), findsOneWidget);
    // Y no se ha ejecutado nada.
    expect(toolchain.installed, isEmpty);
  });

  group('elegir distribución de TeX', () {
    testWidgets('pregunta antes de bajar seis gigas', (tester) async {
      final toolchain = FakeToolchain(
        present: const {ToolId.git, ToolId.python, ToolId.engine},
      );
      await pumpCheck(tester, toolchain);

      await tester.tap(find.byKey(const Key('install-latex')));
      await settle(tester);

      expect(find.text('¿Qué distribución de TeX?'), findsOneWidget);
      for (final option in latexOptions(Host.macos)) {
        expect(find.byKey(Key('latex-${option.id}')), findsOneWidget);
      }
      // El tamaño en la lista, no en la letra pequeña: es el dato que decide.
      expect(find.text('~6 GB'), findsOneWidget);
      expect(
        find.textContaining('pide la contraseña de administrador'),
        findsWidgets,
      );
    });

    testWidgets('viene marcada la ligera, y el botón dice cuál', (
      tester,
    ) async {
      final toolchain = FakeToolchain(
        present: const {ToolId.git, ToolId.python, ToolId.engine},
      );
      await pumpCheck(tester, toolchain);

      await tester.tap(find.byKey(const Key('install-latex')));
      await settle(tester);

      // El botón lleva el nombre del plan elegido, no un «Aceptar»: es lo
      // que impide pulsar y descubrir después que eran seis gigas.
      expect(
        find.widgetWithText(FilledButton, 'Instalar TinyTeX'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('latex-mactex')));
      await settle(tester);
      expect(
        find.widgetWithText(FilledButton, 'Descargar MacTeX'),
        findsOneWidget,
      );
    });

    testWidgets('cancelar no instala nada', (tester) async {
      final toolchain = FakeToolchain(
        present: const {ToolId.git, ToolId.python, ToolId.engine},
      );
      await pumpCheck(tester, toolchain);

      await tester.tap(find.byKey(const Key('install-latex')));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await settle(tester);

      expect(toolchain.installed, isEmpty);
      expect(find.byKey(const Key('install-latex')), findsOneWidget);
    });

    testWidgets('la elegida es la que se instala', (tester) async {
      final toolchain = FakeToolchain(
        present: const {ToolId.git, ToolId.python, ToolId.engine},
      );
      await pumpCheck(tester, toolchain);

      await tester.tap(find.byKey(const Key('install-latex')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('latex-basictex')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('latex-choose')));
      await settle(tester);

      expect(toolchain.installed.single.label, 'Descargar BasicTeX');
      expect(toolchain.present, contains(ToolId.latex));
    });
  });

  testWidgets('volver a comprobar ve lo que se ha instalado por fuera', (
    tester,
  ) async {
    // Es el botón que cierra el círculo de todos los caminos que terminan
    // fuera de Didacta: el instalador de Apple, el de macOS, el terminal.
    final toolchain = FakeToolchain(present: const {ToolId.git});
    await pumpCheck(tester, toolchain);

    expect(find.textContaining('Está todo'), findsNothing);
    toolchain.present.addAll(ToolId.values);

    await tester.tap(find.byKey(const Key('recheck-tools')));
    await settle(tester);

    expect(find.textContaining('Está todo'), findsOneWidget);
  });

  testWidgets('el motor lo descarga la sesión, no una orden del sistema', (
    tester,
  ) async {
    final session = _EngineSession();
    final toolchain = FakeToolchain(
      present: const {ToolId.git, ToolId.python, ToolId.latex},
    );
    await pumpCheck(tester, toolchain, session: session);

    await tester.tap(find.byKey(const Key('install-engine')));
    await settle(tester);

    expect(session.installs, 1);
    // Y no ha pasado por la tabla de planes: el motor no se instala con brew.
    expect(toolchain.installed, isEmpty);
  });

  testWidgets('la bienvenida enseña la lista antes del repositorio', (
    tester,
  ) async {
    // El orden importa: clonar el primer repositorio se hace con git, así que
    // pedir el repositorio antes manda a alguien a un paso que no puede
    // terminar.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = sessionForTools();
    await session.primeForTest(catalogueWith(defaultUnits()));
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          session: session,
          toolchain: FakeToolchain(present: const {ToolId.git}),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const Key('welcome-next'))); // qué es
    await settle(tester);
    await tester.tap(find.byKey(const Key('welcome-next'))); // la cuenta
    await settle(tester);

    expect(find.text('Lo que hace falta en tu ordenador'), findsOneWidget);
    expect(find.byKey(const Key('tool-latex')), findsOneWidget);
    // Y el repositorio todavía no.
    expect(find.text('Tu primer repositorio'), findsNothing);
  });
}

/// Una sesión que no clona nada al pedirle el motor.
class _EngineSession extends FakeSession {
  _EngineSession()
    : super(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );

  int installs = 0;

  @override
  Future<String> installEngine({
    String owner = engineOwner,
    String repo = engineRepo,
    void Function(String line)? onProgress,
  }) async {
    installs += 1;
    return '/de/mentira/didacta';
  }
}
