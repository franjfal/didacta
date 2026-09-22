/// Dos repositorios a la vez, contra git de verdad.
///
/// Es la prueba que importa de todo el cambio: que lo que se escribe acaba en
/// **el repositorio del que salió el fichero**, que enviar cierra lo que está
/// suelto en cada uno y lo empuja, y que traer no se lleva por delante lo que
/// hubiera. Con clones reales y el binario `git`, porque lo que se está
/// probando es precisamente el trato con git.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/github.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

/// Un repositorio de contenido de mentira: un remoto desnudo y su clon.
class Repo {
  Repo(this.remote, this.directory);

  final String remote;
  final String directory;

  static Future<Repo> create(String root, String name, String unit) async {
    // Bajo `x/`, para que el remoto contenga `x/<nombre>`: es lo que mira la
    // aplicación para saber que una carpeta es el clon del repositorio que
    // dice ser, y aquí el remoto es una ruta en vez de una URL de GitHub.
    await Directory('$root/x').create(recursive: true);
    final remote = '$root/x/$name.git';
    final seed = '$root/$name-seed';
    final clone = '$root/$name';

    await _git(['init', '--bare', '--initial-branch=main', remote], root);
    await Directory('$seed/$unit').create(recursive: true);
    File('$seed/$unit/es.tex').writeAsStringSync('De $name.\n');
    File('$seed/didacta.yaml').writeAsStringSync('name: $name\n');
    await _git(['init', '--initial-branch=main', seed], root);
    await _git(['add', '.'], seed);
    await _git(['commit', '-m', 'Semilla'], seed);
    await _git(['remote', 'add', 'origin', remote], seed);
    await _git(['push', '-u', 'origin', 'main'], seed);
    await _git(['clone', '--branch', 'main', remote, clone], root);
    return Repo(remote, clone);
  }

  /// Lo que el remoto tiene en ese fichero, que es lo que vería otra persona.
  Future<String> remoteText(String path) async {
    final result = await Process.run('git', [
      'show',
      'main:$path',
    ], workingDirectory: remote);
    return result.exitCode == 0 ? result.stdout as String : '';
  }

  Future<int> remoteCommits() async {
    final result = await Process.run('git', [
      'rev-list',
      '--count',
      'main',
    ], workingDirectory: remote);
    return int.tryParse((result.stdout as String).trim()) ?? 0;
  }
}

Future<void> _git(List<String> arguments, String directory) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
    environment: const {
      'GIT_AUTHOR_NAME': 'Semilla',
      'GIT_AUTHOR_EMAIL': 'semilla@example.com',
      'GIT_COMMITTER_NAME': 'Semilla',
      'GIT_COMMITTER_EMAIL': 'semilla@example.com',
      'GIT_TERMINAL_PROMPT': '0',
    },
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
  }
}

void main() {
  late Directory root;
  late Repo uno;
  late Repo dos;
  late Session session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('didacta-multi-');
    uno = await Repo.create(root.path, 'uno', 'content/analysis/normed/def');
    dos = await Repo.create(root.path, 'dos', 'content/algebra/matrices/rank');

    final workspace = Workspace([
      ContentRepo(
        owner: 'x',
        name: 'uno',
        directory: uno.directory,
        colour: 0xFF346E34,
      ),
      ContentRepo(
        owner: 'x',
        name: 'dos',
        directory: dos.directory,
        colour: 0xFF2D5FA0,
      ),
    ]);

    session = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(repos: workspace.toJson()),
    );
    await session.start();
    // El autor: en un clon propio sale de git, sin entrar en ningún sitio.
    await session.setCloneAuthor(name: 'Javier', email: 'javier@uv.es');
  });

  tearDown(() => root.delete(recursive: true));

  test('cada repositorio tiene su pasarela, y escriben en el suyo', () async {
    // `looksRight` compara el remoto, y aquí es una ruta: lo que importa es
    // que la pasarela de cada uno apunta a su clon.
    expect(session.workspace.repos.length, 2);

    await session
        .gatewayFor('x/uno')
        .save(
          path: 'content/analysis/normed/def/es.tex',
          text: 'Escrito en uno.\n',
          sha: await _shaOf(
            session,
            'x/uno',
            'content/analysis/normed/def/es.tex',
          ),
          message: 'Editar en uno',
        );
    await session
        .gatewayFor('x/dos')
        .save(
          path: 'content/algebra/matrices/rank/es.tex',
          text: 'Escrito en dos.\n',
          sha: await _shaOf(
            session,
            'x/dos',
            'content/algebra/matrices/rank/es.tex',
          ),
          message: 'Editar en dos',
        );

    // Cada cambio, en su clon. Sin esto, con dos repositorios abiertos todo
    // se escribiría en el primero.
    expect(
      File(
        '${uno.directory}/content/analysis/normed/def/es.tex',
      ).readAsStringSync(),
      'Escrito en uno.\n',
    );
    expect(
      File(
        '${dos.directory}/content/algebra/matrices/rank/es.tex',
      ).readAsStringSync(),
      'Escrito en dos.\n',
    );
  });

  test('enviar cierra lo suelto de cada uno y lo empuja', () async {
    // Como si alguien hubiera editado con otro programa: ficheros escritos y
    // sin commit, en los dos repositorios.
    File(
      '${uno.directory}/content/analysis/normed/def/es.tex',
    ).writeAsStringSync('Tocado por fuera en uno.\n');
    File(
      '${dos.directory}/content/algebra/matrices/rank/es.tex',
    ).writeAsStringSync('Tocado por fuera en dos.\n');

    final boxes = await session.outbox();
    expect(boxes.length, 2);
    expect(boxes.first.pending.single, 'content/analysis/normed/def/es.tex');

    final result = await session.pushAll('Trabajo de la tarde');
    expect(result.values.every((each) => each is int), isTrue);

    // Y está en el remoto, que es lo único que le consta a otra persona.
    expect(
      await uno.remoteText('content/analysis/normed/def/es.tex'),
      'Tocado por fuera en uno.\n',
    );
    expect(
      await dos.remoteText('content/algebra/matrices/rank/es.tex'),
      'Tocado por fuera en dos.\n',
    );
  });

  test('enviar cuenta lo que hace, en el registro', () async {
    // La razón de que exista el registro: un envío grande son minutos de
    // `git add`, `git commit` y `git push`, y sin esto el único indicio de
    // que algo pasaba era un botón gris --que se vuelve a pulsar, porque
    // desde fuera eso es una aplicación colgada--.
    File(
      '${uno.directory}/content/analysis/normed/def/es.tex',
    ).writeAsStringSync('Tocado por fuera en uno.\n');

    await session.pushAll('Trabajo de la tarde');

    final console = session.syncConsole;
    expect(console.running, isFalse);
    expect(console.ok, isTrue);
    expect(console.title, 'Enviar a GitHub');
    // El repositorio al que le toca, y las órdenes que se le dieron a git.
    expect(console.lines, contains('=== x/uno'));
    expect(console.lines, contains(r'$ git push'));
    expect(
      console.lines.where((line) => line.startsWith(r'$ git add -A')),
      isNotEmpty,
    );
    // Y lo que git contestó: sin esto el registro sería una lista de órdenes,
    // que es lo mismo que no tener registro.
    expect(
      console.lines.where((line) => line.contains('main')),
      isNotEmpty,
      reason: 'el resumen del commit que escribe git',
    );
  });

  test('un envío que falla se queda dicho en el registro', () async {
    // El remoto desaparece por debajo: es el caso en que el registro tiene
    // que quedarse abierto, porque lo que git diga ahí es lo único que
    // explica por qué no salió.
    File(
      '${uno.directory}/content/analysis/normed/def/es.tex',
    ).writeAsStringSync('Tocado por fuera en uno.\n');
    await Directory(uno.remote).delete(recursive: true);

    final result = await session.pushAll('Trabajo de la tarde');

    expect(result['x/uno'], isA<CloneException>());
    expect(session.syncConsole.ok, isFalse);
    expect(
      session.syncConsole.lines.where((line) => line.startsWith('--- FAIL')),
      isNotEmpty,
    );
  });

  test('traer se trae lo de los dos', () async {
    // Otra persona empuja a cada remoto.
    for (final repo in [uno, dos]) {
      final other = '${root.path}/otro-${repo.remote.hashCode}';
      await _git(['clone', '--branch', 'main', repo.remote, other], root.path);
      File('$other/nuevo.txt').writeAsStringSync('De otra persona\n');
      await _git(['add', '.'], other);
      await _git(['commit', '-m', 'Desde fuera'], other);
      await _git(['push'], other);
    }

    await session.pullAll();

    expect(File('${uno.directory}/nuevo.txt').existsSync(), isTrue);
    expect(File('${dos.directory}/nuevo.txt').existsSync(), isTrue);

    // Y contado, igual que el envío.
    expect(session.syncConsole.title, 'Traer de GitHub');
    expect(session.syncConsole.ok, isTrue);
    expect(session.syncConsole.lines, contains(r'$ git pull --ff-only'));
    expect(
      session.syncConsole.lines.where(
        (line) => line.startsWith('--- ahora en'),
      ),
      hasLength(2),
      reason: 'los dos clones se movieron, y el registro dice a dónde',
    );
  });

  test('lo que no se toca no se envía', () async {
    // Un historial con commits vacíos es un historial que nadie lee.
    final before = await uno.remoteCommits();
    await session.pushAll('Nada que enviar');
    expect(await uno.remoteCommits(), before);
  });

  test(
    'un clon que ya está en el disco se añade, comprobándolo en GitHub',
    () async {
      // El camino de vuelta para quien ya tenía un clon. Pasa por GitHub igual:
      // de qué repositorio es lo dice su propio remoto, y si esta cuenta llega
      // a él lo dice GitHub.
      final fresh = LocalSession(
        catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
        tokenStore: StubStore(),
        preferences: MemoryPreferences(),
      );
      await fresh.start();
      // Sin repositorios abre vacía y **sin error**: no es un fallo, es que
      // falta decirle con qué trabajar.
      expect(fresh.state, LoadState.ready);
      expect(fresh.needsRepository, isTrue);

      final added = await fresh.addExistingRepository(uno.directory);
      expect(added.name, 'uno');
      expect(added.directory, uno.directory);
      expect(fresh.needsRepository, isFalse);
      expect(fresh.gatewayFor(added.id).canWrite, isTrue);
      // Y se preguntó por el par exacto que dice el remoto del clon.
      expect(fresh.asked, contains('x/uno'));
    },
  );

  test('un clon atrasado se pone al día al añadirlo', () async {
    // Una carpeta que llevaba meses parada abre enseñando material viejo sin
    // decirlo. Traer y avanzar es gratis cuando no hay nada que perder, y es
    // lo que hace que lo que se ve nada más añadir sea lo que hay en GitHub.
    final seed = '${root.path}/uno-seed';
    File(
      '$seed/content/analysis/normed/def/es.tex',
    ).writeAsStringSync('Lo nuevo de otra persona.\n');
    await _git(['commit', '-am', 'De otra persona'], seed);
    await _git(['push'], seed);

    final fresh = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    );
    await fresh.start();
    final added = await fresh.addExistingRepository(uno.directory);

    expect(fresh.addProblem, isNull, reason: 'quedó al día');
    expect(fresh.statusOf(added.id)?.isSynced, isTrue);
    expect(
      File(
        '${uno.directory}/content/analysis/normed/def/es.tex',
      ).readAsStringSync(),
      contains('Lo nuevo de otra persona'),
    );
  });

  test('un clon solo con trabajo sin enviar no es un desfase', () async {
    // Tener commits propios esperando a salir no es estar desincronizado con
    // GitHub: es trabajo en la bandeja de salida, y de eso habla la barra de
    // sincronización. Tratarlo como un problema al añadir habría puesto un
    // aviso permanente en el caso más normal de todos.
    File(
      '${uno.directory}/content/analysis/normed/def/es.tex',
    ).writeAsStringSync('Mío, sin enviar.\n');
    await _git(['commit', '-am', 'Mío'], uno.directory);

    final fresh = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    );
    await fresh.start();
    final added = await fresh.addExistingRepository(uno.directory);

    expect(fresh.workspace.repos.map((r) => r.id), contains(added.id));
    expect(fresh.addProblem, isNull);
  });

  test('un clon que ha divergido se añade, y se dice', () async {
    // Las dos historias han seguido por su lado. Juntarlas es un merge, y eso
    // no lo decide un botón de «añadir carpeta». Pero tampoco se calla: un
    // desfase callado es una sorpresa tres días después.
    File(
      '${uno.directory}/content/analysis/normed/def/es.tex',
    ).writeAsStringSync('Mío, sin enviar.\n');
    await _git(['commit', '-am', 'Mío'], uno.directory);

    final seed = '${root.path}/uno-seed';
    File('$seed/didacta.yaml').writeAsStringSync('name: uno\n# y algo más\n');
    await _git(['commit', '-am', 'De otra persona'], seed);
    await _git(['push'], seed);

    final fresh = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    );
    await fresh.start();
    final added = await fresh.addExistingRepository(uno.directory);

    expect(fresh.workspace.repos.map((r) => r.id), contains(added.id));
    expect('${fresh.addProblem}', contains('no está al día'));
    expect('${fresh.addProblem}', contains('1 commit por traer'));
    expect('${fresh.addProblem}', contains('1 sin enviar'));
  });

  group('al día antes de modificar', () {
    test('guardar trae lo que haya en GitHub antes de escribir', () async {
      // Editar sobre material viejo es cómo dos personas sobre el mismo tema
      // se pisan sin enterarse hasta que una no puede enviar.
      final seed = '${root.path}/uno-seed';
      File(
        '$seed/content/analysis/normed/def/es.tex',
      ).writeAsStringSync('Lo de otra persona.\n');
      await _git(['commit', '-am', 'De otra persona'], seed);
      await _git(['push'], seed);

      await session.ensureFresh('x/uno');

      expect(
        File(
          '${uno.directory}/content/analysis/normed/def/es.tex',
        ).readAsStringSync(),
        contains('Lo de otra persona'),
      );
      expect(session.driftOf('x/uno'), isNull);
    });

    test('no vuelve a preguntar si acaba de mirarlo', () async {
      // La ventana, que es lo que evita saturar: guardar es lo que más se
      // hace, y una llamada de red por guardado se nota justo en lo que más
      // se nota.
      await session.ensureFresh('x/uno');

      final seed = '${root.path}/uno-seed';
      File(
        '$seed/content/analysis/normed/def/es.tex',
      ).writeAsStringSync('Posterior a la comprobación.\n');
      await _git(['commit', '-am', 'Después'], seed);
      await _git(['push'], seed);

      await session.ensureFresh('x/uno');

      expect(
        File(
          '${uno.directory}/content/analysis/normed/def/es.tex',
        ).readAsStringSync(),
        isNot(contains('Posterior a la comprobación')),
      );
    });

    test('traer o enviar vuelve a abrir la ventana', () async {
      // Lo que se acaba de hacer cambia lo que una comprobación anterior daba
      // por bueno, así que la caducidad no puede sobrevivir a un pull.
      await session.ensureFresh('x/uno');
      await session.pullAll();

      final seed = '${root.path}/uno-seed';
      File(
        '$seed/content/analysis/normed/def/es.tex',
      ).writeAsStringSync('Después del pull.\n');
      await _git(['commit', '-am', 'Después'], seed);
      await _git(['push'], seed);

      await session.ensureFresh('x/uno');

      expect(
        File(
          '${uno.directory}/content/analysis/normed/def/es.tex',
        ).readAsStringSync(),
        contains('Después del pull'),
      );
    });

    test('con las dos historias por su lado no toca nada, y lo dice', () async {
      // Juntarlas es un merge, y eso no lo decide un guardado.
      File(
        '${uno.directory}/content/analysis/normed/def/es.tex',
      ).writeAsStringSync('Mío.\n');
      await _git(['commit', '-am', 'Mío'], uno.directory);

      final seed = '${root.path}/uno-seed';
      File('$seed/didacta.yaml').writeAsStringSync('name: uno\n# suyo\n');
      await _git(['commit', '-am', 'Suyo'], seed);
      await _git(['push'], seed);

      await session.ensureFresh('x/uno');

      expect(
        File(
          '${uno.directory}/content/analysis/normed/def/es.tex',
        ).readAsStringSync(),
        'Mío.\n',
        reason: 'lo local no se pisa',
      );
      expect('${session.driftOf('x/uno')}', contains('no está al día'));
    });

    test('guardar sigue funcionando cuando no se puede comprobar', () async {
      // Un commit a un clon del propio disco no necesita red. Perder trabajo
      // para proteger una sincronización que se hará después sería el peor
      // cambio posible, así que lo que falla es la comprobación y no el
      // guardado.
      var asked = 0;
      final gateway = CloneGateway(
        clone: LocalClone(directory: uno.directory),
        token: '',
        author: (name: 'Javier', email: 'javier@uv.es'),
        pushOnCommit: false,
        beforeWrite: () async {
          asked += 1;
          throw const SocketException('sin red');
        },
      );
      final sha = (await gateway.read(
        'content/analysis/normed/def/es.tex',
      )).sha;

      await gateway.save(
        path: 'content/analysis/normed/def/es.tex',
        text: 'Escrito sin poder comprobar.\n',
        sha: sha,
        message: 'Sin red',
      );

      expect(asked, 1, reason: 'lo intentó');
      expect(
        File(
          '${uno.directory}/content/analysis/normed/def/es.tex',
        ).readAsStringSync(),
        contains('Escrito sin poder comprobar'),
      );
    });

    test('y lo que no se pudo comprobar queda dicho', () async {
      // Sin remoto al que traer, la comprobación falla y se apunta. No es un
      // error de guardar: es una advertencia sobre lo que hay debajo.
      await Directory(uno.remote).delete(recursive: true);
      await session.ensureFresh('x/uno');
      expect(session.driftOf('x/uno'), isNotNull);
    });
  });

  test('un clon al que esta cuenta no llega se rechaza', () async {
    // Que la carpeta esté en este disco no dice nada de quién la puso ahí:
    // puede ser el clon de otra persona, o el de una cuenta anterior. Lo que
    // decide es GitHub.
    final fresh = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    )..reaches = const {'x/otro'};
    await fresh.start();

    await expectLater(
      fresh.addExistingRepository(uno.directory),
      throwsA(
        isA<CloneException>().having(
          (e) => e.message,
          'motivo',
          allOf(contains('x/uno'), contains('no llegas')),
        ),
      ),
    );
    expect(fresh.needsRepository, isTrue, reason: 'no se ha añadido');
  });

  test('sin poder preguntar a GitHub no se añade a ciegas', () async {
    // Añadir es la operación que fija con qué se va a trabajar, y hacerlo sin
    // saber si se puede sincronizar es abrir algo que quizá nunca podrá
    // enviarse. Se hace una vez y con red; lo ya añadido abre sin ella.
    final fresh = _OfflineSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    );
    await fresh.start();

    await expectLater(
      fresh.addExistingRepository(uno.directory),
      throwsA(isA<CloneException>()),
    );
    expect(fresh.needsRepository, isTrue);
  });

  test('entrar con otra cuenta cierra lo que esa cuenta no alcanza', () async {
    // La carpeta se queda en el disco: perder el acceso a un repositorio no
    // es motivo para borrarlo de la máquina de nadie.
    final fresh = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(
        repos: Workspace([
          ContentRepo(owner: 'x', name: 'uno', directory: uno.directory),
          ContentRepo(owner: 'x', name: 'dos', directory: dos.directory),
        ]).toJson(),
      ),
    );
    await fresh.start();
    expect(fresh.workspace.repos, hasLength(2));

    fresh.reaches = const {'x/uno'};
    await fresh.signIn('gho_otra_cuenta');

    expect(fresh.workspace.repos.map((r) => r.id), ['x/uno']);
    expect(
      Directory(dos.directory).existsSync(),
      isTrue,
      reason: 'la carpeta se queda',
    );
  });

  test('una carpeta que no es un clon se rechaza diciendo por qué', () async {
    final fresh = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    );
    await fresh.start();
    await expectLater(
      fresh.addExistingRepository(root.path),
      throwsA(isA<CloneException>()),
    );
  });

  test('cada repositorio tiene su color, y solo cuando hay varios', () async {
    expect(session.colourOf('x/uno'), 0xFF346E34);
    expect(session.colourOf('x/dos'), 0xFF2D5FA0);

    // Con uno solo no hay con qué confundirlo, así que no se marca nada.
    final alone = LocalSession(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(
        repos: Workspace([
          ContentRepo(owner: 'x', name: 'uno', directory: uno.directory),
        ]).toJson(),
      ),
    );
    await alone.start();
    expect(alone.colourOf('x/uno'), isNull);
  });
}

Future<String> _shaOf(Session session, String repo, String path) async {
  final file = await session.gatewayFor(repo).read(path);
  return file.sha;
}

/// Una sesión que no puede hablar con GitHub.
class _OfflineSession extends LocalSession {
  _OfflineSession({
    required super.catalogueSource,
    required super.tokenStore,
    super.preferences,
  });

  @override
  Future<GitHubRepo?> accessTo(String owner, String name) async =>
      throw const SocketException('sin red');
}
