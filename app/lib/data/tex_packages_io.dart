/// Los paquetes de LaTeX, con `tlmgr` o con MiKTeX, en escritorio.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/tex_packages.dart';
import '../model/toolchain.dart' show describeTexDirectory;
import 'compiler_io.dart' show texAwarePath, texDirectories;
import 'tex_packages.dart';
import 'toolchain_io.dart' show findIn, currentHost, toolDirectories;
import '../l10n/tr.dart';

bool get supported => true;

TexPackages makeTexPackages({String? texPath}) =>
    _ProcessTexPackages(texPath: texPath);

class _ProcessTexPackages implements TexPackages {
  _ProcessTexPackages({this.texPath});

  final String? texPath;

  /// Dónde buscar los programas de TeX: primero los del PATH con el que se
  /// compila --así el gestor es el de la distribución que compila, y no el
  /// de otra que también esté--, luego los sitios de siempre.
  List<String> get _directories => [
    ...toolDirectories(texPath: texPath),
    ...texDirectories(configured: texPath),
  ];

  Map<String, String> get _environment => {
    'NO_COLOR': '1',
    'TERM': 'dumb',
    'PATH': texAwarePath(configured: texPath),
  };

  @override
  Future<TexPackageManager> manager() async {
    final directories = _directories;
    // La carpeta del pdflatex con el que se compila manda: si en ella hay un
    // gestor, es el suyo.
    final latex = findIn(['latexmk', 'pdflatex'], directories);
    final ordered = [?latex?.directory, ...directories];

    final miktex = findIn(['miktex', 'mpm'], [?latex?.directory]);
    final tlmgr = findIn(['tlmgr'], [?latex?.directory]);
    if (miktex != null && tlmgr == null) {
      return TexPackageManager(
        kind: TexManagerKind.miktex,
        program: miktex.path,
        distribution: 'MiKTeX',
      );
    }

    final found = tlmgr ?? findIn(['tlmgr'], ordered);
    if (found == null) {
      final other = findIn(['miktex', 'mpm'], ordered);
      if (other != null) {
        return TexPackageManager(
          kind: TexManagerKind.miktex,
          program: other.path,
          distribution: 'MiKTeX',
        );
      }
      return TexPackageManager.none;
    }

    final root = await _texmfRoot(found.directory);
    final distribution = describeTexDirectory(_resolved(found.directory)).name;
    if (Platform.isLinux && isSystemTexRoot(root)) {
      return TexPackageManager(
        kind: TexManagerKind.system,
        program: found.path,
        root: root,
        distribution: distribution,
      );
    }
    return TexPackageManager(
      kind: TexManagerKind.tlmgr,
      program: found.path,
      root: root,
      needsAdmin: root != null && !_writable(root),
      distribution: distribution,
    );
  }

  /// La raíz de la distribución, preguntada a su `kpsewhich`.
  Future<String?> _texmfRoot(String directory) async {
    final kpsewhich = findIn(['kpsewhich'], [directory]);
    if (kpsewhich == null) return null;
    try {
      final result = await Process.run(kpsewhich.path, [
        '-var-value=TEXMFROOT',
      ], environment: _environment).timeout(const Duration(seconds: 10));
      final root = '${result.stdout}'.trim();
      return result.exitCode == 0 && root.isNotEmpty ? root : null;
    } on ProcessException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// Si se puede escribir en el árbol de [root]: se prueba escribiendo, que
  /// es la única respuesta fiable --los permisos dicen de quién es la
  /// carpeta, no si este usuario puede--.
  bool _writable(String root) {
    final tlpkg = Directory('$root${Platform.pathSeparator}tlpkg');
    if (!tlpkg.existsSync()) return true;
    final probe = File(
      '${tlpkg.path}${Platform.pathSeparator}.didacta-permiso-$pid',
    );
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  String _resolved(String directory) {
    try {
      return Directory(directory).resolveSymbolicLinksSync();
    } on FileSystemException {
      return directory;
    }
  }

  @override
  Future<String?> locate(String file) async {
    if (!isSafePackageName(file)) return null;
    final kpsewhich = findIn(['kpsewhich'], _directories);
    if (kpsewhich == null) return null;
    try {
      final result = await Process.run(kpsewhich.path, [
        file,
      ], environment: _environment).timeout(const Duration(seconds: 15));
      final path = '${result.stdout}'.trim();
      return result.exitCode == 0 && path.isNotEmpty ? path : null;
    } on ProcessException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<String?> packageFor(
    String file,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  }) async {
    if (!isSafePackageName(file)) return null;
    switch (manager.kind) {
      case TexManagerKind.miktex:
        return miktexPackageFor(file);
      case TexManagerKind.system:
      case TexManagerKind.none:
        return null;
      case TexManagerKind.tlmgr:
        // Buscar no escribe nada: no pide ser administrador.
        final run = await _run(
          manager.program!,
          ['search', '--global', '--file', '/$file'],
          onOutput: onOutput,
          timeout: const Duration(minutes: 2),
        );
        if (run.code != 0) {
          throw TexPackageException(
            explainTlmgrFailure(run.output) ??
                tr('tlmgr no ha podido buscar qué paquete trae {0}.', [file]),
            detail: run.output,
            manual: manualInstallSteps(
              manager: manager,
              host: currentHost,
              file: file,
            ),
          );
        }
        return packageFromTlmgrSearch(run.output, file);
    }
  }

  @override
  Future<void> install(
    String package,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  }) async {
    if (!isSafePackageName(package)) {
      throw TexPackageException(
        tr('«{0}» no parece el nombre de un paquete.', [package]),
      );
    }
    switch (manager.kind) {
      case TexManagerKind.system:
      case TexManagerKind.none:
        throw TexPackageException(
          tr('Esta instalación de TeX no se puede ampliar desde Didacta.'),
          manual: manualInstallSteps(
            manager: manager,
            host: currentHost,
            file: package,
            package: package,
          ),
        );
      case TexManagerKind.miktex:
        await _installMiktex(package, manager, onOutput: onOutput);
      case TexManagerKind.tlmgr:
        await _installTlmgr(package, manager, onOutput: onOutput);
    }
  }

  Future<void> _installMiktex(
    String package,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  }) async {
    final program = manager.program!;
    final name = program.split(RegExp(r'[/\\]')).last.toLowerCase();
    // `miktex packages install` es la orden nueva; `mpm` la de siempre, que
    // sigue viniendo.
    final arguments = name.startsWith('miktex')
        ? ['packages', 'install', package]
        : ['--install=$package'];
    final run = await _run(program, arguments, onOutput: onOutput);
    if (run.code != 0) {
      final lower = run.output.toLowerCase();
      throw TexPackageException(
        lower.contains('unknown package') || lower.contains('not found')
            ? tr(
                'MiKTeX no tiene un paquete que se llame «{0}». Búscalo por '
                'el nombre del fichero en la Consola de MiKTeX.',
                [package],
              )
            : lower.contains('administrator') || lower.contains('privilege')
            ? tr(
                'MiKTeX está instalado para todos los usuarios y añadirle '
                'paquetes pide ser administrador.',
              )
            : tr('MiKTeX no ha podido instalar «{0}» (código {1}).', [
                package,
                run.code,
              ]),
        detail: run.output,
        manual: manualInstallSteps(
          manager: manager,
          host: currentHost,
          file: package,
          package: package,
        ),
      );
    }
  }

  Future<void> _installTlmgr(
    String package,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  }) async {
    final tlmgr = manager.program!;
    final manual = manualInstallSteps(
      manager: manager,
      host: currentHost,
      file: package,
      package: package,
    );

    // Un ensayo primero, que no escribe nada y no pide permisos: dice si
    // tlmgr tiene que actualizarse antes --pasa en cuanto CTAN saca una
    // versión nueva de tlmgr, y entonces `install` se niega--. Así las dos
    // cosas van en una sola orden y la contraseña se pide una vez.
    onOutput?.call(tr('Comprobando con tlmgr…'));
    final rehearsal = await _run(tlmgr, [
      'install',
      '--dry-run',
      package,
    ], onOutput: onOutput);
    final steps = <List<String>>[
      if (rehearsal.output.toLowerCase().contains(
        'tlmgr itself needs to be updated',
      ))
        ['update', '--self'],
      ['install', package],
    ];
    if (steps.length > 1) {
      onOutput?.call(
        tr(
          'tlmgr pide actualizarse antes de instalar: primero «tlmgr update '
          '--self», después el paquete.',
        ),
      );
    }

    ({int code, String output}) run = (code: 0, output: '');
    final pkexec = Platform.isLinux
        ? findIn(['pkexec'], toolDirectories())
        : null;
    if (!manager.needsAdmin) {
      for (final step in steps) {
        run = await _run(tlmgr, step, onOutput: onOutput);
        if (run.code != 0) break;
      }
    } else if (Platform.isMacOS) {
      run = await _asAdministratorOnMac(
        tlmgr,
        steps,
        package: package,
        onOutput: onOutput,
      );
    } else if (pkexec != null) {
      onOutput?.call(tr('Pidiendo permiso de administrador…'));
      run = await _run(pkexec.path, [
        '/bin/sh',
        '-c',
        _shellChain(tlmgr, steps),
      ], onOutput: onOutput);
      // 126: se cerró la ventana de la contraseña; 127: no hubo forma de
      // pedirla.
      if (run.code == 126 || run.code == 127) {
        throw TexPackageException(
          tr('No se ha dado el permiso de administrador.'),
          detail: run.output,
          manual: manual,
        );
      }
    } else {
      throw TexPackageException(
        tr(
          'La carpeta de TeX ({0}) es del administrador, así que el paquete '
          'hay que instalarlo como administrador.',
          [manager.root ?? tlmgr],
        ),
        manual: manual,
      );
    }
    if (run.code != 0) {
      throw TexPackageException(
        explainTlmgrFailure(run.output) ??
            tr('tlmgr no ha podido instalar «{0}» (código {1}).', [
              package,
              run.code,
            ]),
        detail: run.output,
        manual: manual,
      );
    }
  }

  /// Las órdenes de [steps] para un shell, una detrás de otra y parando en
  /// la primera que falle. Todo entre comillas simples: lo que va dentro ya
  /// se ha mirado con [isSafePackageName], pero la ruta de tlmgr puede
  /// llevar espacios.
  static String _shellChain(String tlmgr, List<List<String>> steps) {
    String quote(String text) => "'${text.replaceAll("'", r"'\''")}'";
    return steps
        .map((step) => [tlmgr, ...step].map(quote).join(' '))
        .join(' && ');
  }

  /// tlmgr como administrador, con la ventana de contraseña de macOS. La
  /// contraseña la pide el sistema y la ve solo el sistema.
  ///
  /// `do shell script` no va contando: lo que escribe tlmgr llega entero al
  /// final, así que mientras tanto se dice qué se está esperando.
  Future<({int code, String output})> _asAdministratorOnMac(
    String tlmgr,
    List<List<String>> steps, {
    required String package,
    void Function(String line)? onOutput,
  }) async {
    String apple(String text) =>
        '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    final command = '${_shellChain(tlmgr, steps)} 2>&1';
    final prompt = tr('Didacta quiere instalar el paquete de LaTeX «{0}».', [
      package,
    ]);
    onOutput?.call(
      tr('Pidiendo permiso de administrador… (la ventana es de macOS)'),
    );
    final run = await _run('/usr/bin/osascript', [
      '-e',
      'do shell script ${apple(command)} with prompt ${apple(prompt)} '
          'with administrator privileges',
    ], onOutput: onOutput);
    if (run.code != 0 && run.output.contains('-128')) {
      throw TexPackageException(
        tr('Cancelado: no se ha dado el permiso de administrador.'),
      );
    }
    return run;
  }

  /// Lanza un proceso y va contando lo que escribe, las dos corrientes
  /// juntas. Sin entrada: un gestor que pregunte algo se quedaría esperando
  /// para siempre a una tubería que nadie escribe.
  Future<({int code, String output})> _run(
    String program,
    List<String> arguments, {
    void Function(String line)? onOutput,
    Duration timeout = const Duration(minutes: 20),
  }) async {
    final Process process;
    try {
      process = await Process.start(
        program,
        arguments,
        environment: _environment,
      );
    } on ProcessException catch (error) {
      throw TexPackageException(
        tr('No se pudo lanzar {0}.', [program]),
        detail: error.message,
      );
    }
    try {
      await process.stdin.close();
    } catch (_) {
      // Ya había terminado.
    }
    const decoder = Utf8Decoder(allowMalformed: true);
    final lines = <String>[];
    void keep(String line) {
      lines.add(line);
      onOutput?.call(line);
    }

    final reading = [
      process.stdout
          .transform(decoder)
          .transform(const LineSplitter())
          .forEach(keep),
      process.stderr
          .transform(decoder)
          .transform(const LineSplitter())
          .forEach(keep),
    ];
    int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw TexPackageException(
        tr('{0} no ha terminado en {1} minutos; lo he parado.', [
          program,
          timeout.inMinutes,
        ]),
        detail: lines.join('\n'),
      );
    }
    await Future.wait(reading);
    return (code: code, output: lines.join('\n'));
  }
}
