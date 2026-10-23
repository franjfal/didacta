/// «Falta el paquete X»: el aviso, y el diálogo que lo instala.
///
/// Cuando una compilación para porque a LaTeX le falta un fichero de un
/// paquete --`File `tcolorbox.sty' not found`--, el motor lo dice con nombre
/// (`CompileDiagnostic.needs`) y aquí se ofrece instalarlo con el gestor de
/// la distribución: `tlmgr` o el de MiKTeX. Después, volver a compilar.
///
/// Lo que se cuida, por orden:
///
/// * **No instalar lo que ya está.** Antes de nada se le pregunta a
///   `kpsewhich`; si lo encuentra, el problema es otro --se compila con otro
///   TeX, o su base de ficheros no está al día-- y se dice eso.
/// * **Decir qué se va a instalar antes de hacerlo**: el paquete, con qué
///   gestor y si va a pedir la contraseña de administrador.
/// * **Que se vea que avanza**: lo que escribe el gestor, según lo escribe.
/// * **Cuando no se puede, decir cómo hacerlo a mano**, con las órdenes de
///   esta máquina listas para copiar.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tex_packages.dart';
import '../model/tex_packages.dart';
import '../model/toolchain.dart' show Host;
import 'theme.dart';
import '../l10n/tr.dart';

/// El aviso de que falta un paquete, con su botón. Va en la tarjeta de una
/// compilación que falló y en la consola.
class MissingPackageNote extends StatelessWidget {
  const MissingPackageNote({
    super.key,
    required this.files,
    required this.onInstall,
  });

  /// Los ficheros que faltan: `tcolorbox.sty`.
  final List<String> files;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('missing-package'),
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.palette.tint(context.palette.ex),
      border: Border.all(color: context.palette.tint(context.palette.ex, 0.3)),
      borderRadius: BorderRadius.circular(6),
    ),
    padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
    child: Row(
      children: [
        Icon(Icons.extension_outlined, size: 18, color: context.palette.ex),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            files.length == 1
                ? tr(
                    'Falta un paquete de LaTeX: el que trae «{0}». Se puede '
                    'instalar desde aquí.',
                    [files.single],
                  )
                : tr(
                    'Faltan paquetes de LaTeX: los que traen {0}. Se pueden '
                    'instalar desde aquí.',
                    [files.map((f) => '«$f»').join(', ')],
                  ),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('missing-package-install'),
          icon: const Icon(Icons.download_outlined, size: 16),
          label: Text(
            files.length == 1
                ? tr('Instalar paquete')
                : tr('Instalar paquetes'),
          ),
          onPressed: onInstall,
        ),
      ],
    ),
  );
}

/// Abre el diálogo de instalar. [onRecompile], si se puede volver a
/// compilar lo que falló: se ofrece al acabar bien.
///
/// Devuelve si se instaló algo.
Future<bool> showInstallPackages(
  BuildContext context, {
  required List<String> files,
  required TexPackages packages,
  Future<void> Function()? onRecompile,
}) async {
  final recompile = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InstallPackagesDialog(
      files: files,
      packages: packages,
      canRecompile: onRecompile != null,
    ),
  );
  if (recompile == true && onRecompile != null) await onRecompile();
  return recompile != null;
}

/// En qué punto está.
enum _Stage { checking, ready, installing, done, failed }

/// Lo que se sabe de cada fichero que falta.
class _Need {
  _Need(this.file);

  final String file;

  /// El paquete que lo trae, si se sabe.
  String? package;

  /// Dónde está, si ya está instalado.
  String? installedAt;

  /// Por qué no se ha podido saber.
  TexPackageException? problem;

  bool installed = false;
}

class InstallPackagesDialog extends StatefulWidget {
  const InstallPackagesDialog({
    super.key,
    required this.files,
    required this.packages,
    this.canRecompile = false,
  });

  final List<String> files;
  final TexPackages packages;
  final bool canRecompile;

  @override
  State<InstallPackagesDialog> createState() => _InstallPackagesDialogState();
}

class _InstallPackagesDialogState extends State<InstallPackagesDialog> {
  _Stage _stage = _Stage.checking;
  TexPackageManager _manager = TexPackageManager.none;
  late final List<_Need> _needs = [for (final f in widget.files) _Need(f)];
  final List<String> _output = [];
  final ScrollController _scroll = ScrollController();
  TexPackageException? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _say(String line) {
    if (!mounted) return;
    setState(() => _output.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// Qué gestor hay, si ya está cada fichero y qué paquete lo trae.
  Future<void> _check() async {
    final manager = await widget.packages.manager();
    if (!mounted) return;
    setState(() => _manager = manager);
    for (final need in _needs) {
      need.installedAt = await widget.packages.locate(need.file);
      if (need.installedAt != null || !manager.canInstall) continue;
      try {
        need.package = await widget.packages.packageFor(need.file, manager);
      } on TexPackageException catch (error) {
        need.problem = error;
      }
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() => _stage = _Stage.ready);
  }

  /// Los paquetes que hay que instalar, sin repetir.
  List<String> get _toInstall => [
    ...{
      for (final need in _needs)
        if (need.installedAt == null && need.package != null) need.package!,
    },
  ];

  Future<void> _install() async {
    setState(() {
      _stage = _Stage.installing;
      _failure = null;
      _output.clear();
    });
    try {
      for (final package in _toInstall) {
        _say(tr('Instalando «{0}» con {1}…', [package, _manager.label]));
        await widget.packages.install(package, _manager, onOutput: _say);
        for (final need in _needs) {
          if (need.package == package) need.installed = true;
        }
      }
      // Comprobado y no supuesto: si kpsewhich sigue sin verlo, la
      // compilación volvería a fallar igual, y es mejor decirlo aquí.
      for (final need in _needs.where((need) => need.installed)) {
        need.installedAt = await widget.packages.locate(need.file);
      }
      if (!mounted) return;
      setState(() => _stage = _Stage.done);
    } on TexPackageException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error;
        _stage = _Stage.failed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = TexPackageException('$error');
        _stage = _Stage.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final working = _stage == _Stage.checking || _stage == _Stage.installing;
    return AlertDialog(
      key: const Key('install-packages'),
      title: Text(
        widget.files.length == 1
            ? tr('Falta un paquete de LaTeX')
            : tr('Faltan paquetes de LaTeX'),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final need in _needs) _needRow(context, need),
              const SizedBox(height: 10),
              ..._explanation(context),
              if (working) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 3),
              ],
              if (_output.isNotEmpty) ...[
                const SizedBox(height: 10),
                _terminal(context),
              ],
              if (_failure case final failure?) ..._failed(context, failure),
            ],
          ),
        ),
      ),
      actions: _actions(context),
    );
  }

  Widget _needRow(BuildContext context, _Need need) {
    final String status;
    final Color tone;
    if (need.installed && need.installedAt != null) {
      status = tr('instalado');
      tone = context.palette.accentDark;
    } else if (need.installedAt != null) {
      status = tr('ya está instalado');
      tone = context.palette.accentDark;
    } else if (_stage == _Stage.checking) {
      status = tr('buscando qué paquete lo trae…');
      tone = context.palette.muted;
    } else if (need.package != null) {
      status = tr('paquete «{0}»', [need.package!]);
      tone = context.palette.ink;
    } else if (need.problem != null) {
      status = need.problem!.message;
      tone = context.palette.teacher;
    } else if (_manager.canInstall) {
      status = tr('ningún paquete de {0} lo trae', [
        _manager.distribution ?? _manager.label,
      ]);
      tone = context.palette.teacher;
    } else {
      status = tr('no se puede instalar desde aquí');
      tone = context.palette.teacher;
    }
    return Padding(
      key: Key('install-need-${need.file}'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            need.installedAt != null
                ? Icons.check_circle_outline
                : Icons.extension_outlined,
            size: 17,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: need.file,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: '  ·  '),
                  TextSpan(
                    text: status,
                    style: TextStyle(color: tone),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _explanation(BuildContext context) {
    final muted = TextStyle(fontSize: 12.5, color: context.palette.muted);
    switch (_stage) {
      case _Stage.checking:
        return [
          Text(
            tr(
              'Mirando qué distribución de TeX hay y preguntándole a su '
              'gestor de paquetes. Puede tardar unos segundos: tlmgr consulta '
              'el repositorio de CTAN.',
            ),
            style: muted,
          ),
        ];
      case _Stage.ready:
        final already = _needs.every((need) => need.installedAt != null);
        if (already) {
          return [
            Text(
              tr(
                'Lo que falta ya está en la distribución, así que instalarlo '
                'otra vez no arreglaría nada. Lo más probable es que se esté '
                'compilando con otra instalación de TeX: mira cuál en Ajustes '
                '→ Herramientas. Vuelve a compilar por si era algo pasajero.',
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            for (final need in _needs) _path(context, need.installedAt!),
          ];
        }
        if (_toInstall.isEmpty) {
          return _manualFor(context);
        }
        return [
          Text(
            _manager.distribution == null
                ? tr('Se instalará con {0}.', [_manager.label])
                : tr('Se instalará con {0} en {1}.', [
                    _manager.label,
                    _manager.distribution!,
                  ]),
            style: const TextStyle(fontSize: 12.5),
          ),
          if (_manager.needsAdmin) ...[
            const SizedBox(height: 6),
            Text(
              tr(
                'La carpeta de TeX es del administrador: el sistema te pedirá '
                'la contraseña en su propia ventana. Didacta no la ve.',
              ),
              key: const Key('install-needs-admin'),
              style: TextStyle(fontSize: 12.5, color: context.palette.ex),
            ),
          ],
        ];
      case _Stage.installing:
        return [Text(tr('Instalando…'), style: muted)];
      case _Stage.done:
        final missing = _needs.where(
          (need) => need.installed && need.installedAt == null,
        );
        return [
          Text(
            missing.isEmpty
                ? tr('Instalado. Ya se puede volver a compilar.')
                : tr(
                    'El gestor dice que ha terminado, pero LaTeX todavía no '
                    've {0}. Vuelve a compilar; si sigue fallando, mira la '
                    'salida de arriba.',
                    [missing.map((need) => need.file).join(', ')],
                  ),
            key: const Key('install-done'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: missing.isEmpty
                  ? context.palette.accentDark
                  : context.palette.ex,
            ),
          ),
        ];
      case _Stage.failed:
        return const [];
    }
  }

  /// Cuando no hay nada que instalar desde aquí: por qué, y cómo a mano.
  List<Widget> _manualFor(BuildContext context) {
    final first = _needs.firstWhere(
      (need) => need.installedAt == null,
      orElse: () => _needs.first,
    );
    final problem = first.problem;
    final reason =
        problem?.message ??
        switch (_manager.kind) {
          TexManagerKind.none => tr(
            'No he encontrado el gestor de paquetes de ninguna distribución de '
            'TeX (tlmgr o MiKTeX).',
          ),
          TexManagerKind.system => tr(
            'Este TeX es el de la distribución de Linux: sus paquetes los '
            'instala el gestor del sistema, no tlmgr.',
          ),
          _ => tr(
            'Ningún paquete de {0} trae {1}. Puede que el nombre esté mal '
            'escrito en el documento, o que sea un fichero propio y no de un '
            'paquete.',
            [_manager.distribution ?? _manager.label, first.file],
          ),
        };
    return [
      Text(reason, style: const TextStyle(fontSize: 12.5)),
      ..._steps(
        context,
        problem?.manual.isNotEmpty == true
            ? problem!.manual
            : manualInstallSteps(
                manager: _manager,
                host: _host(context),
                file: first.file,
              ),
      ),
    ];
  }

  List<Widget> _failed(BuildContext context, TexPackageException failure) => [
    const SizedBox(height: 10),
    Text(
      failure.message,
      key: const Key('install-failed'),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.palette.teacher,
      ),
    ),
    if (failure.detail.isNotEmpty && _output.isEmpty) ...[
      const SizedBox(height: 6),
      _terminalText(context, failure.detail),
    ],
    ..._steps(context, failure.manual),
  ];

  List<Widget> _steps(BuildContext context, List<String> steps) => [
    if (steps.isNotEmpty) ...[
      const SizedBox(height: 10),
      Text(
        tr('Para hacerlo a mano:'),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      for (final step in steps)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  step,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                tooltip: tr('Copiar'),
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                icon: const Icon(Icons.copy_outlined),
                // La orden, sin la etiqueta de delante («En el Terminal: »):
                // es lo que se va a pegar.
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _commandIn(step))),
              ),
            ],
          ),
        ),
    ],
  ];

  static String _commandIn(String step) {
    final colon = step.indexOf(': ');
    return colon < 0 ? step : step.substring(colon + 2);
  }

  Widget _path(BuildContext context, String path) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: SelectableText(
      path,
      style: TextStyle(
        fontSize: 11.5,
        fontFamily: 'monospace',
        color: context.palette.muted,
      ),
    ),
  );

  Widget _terminal(BuildContext context) => Container(
    height: 150,
    decoration: BoxDecoration(
      color: context.palette.terminal,
      borderRadius: BorderRadius.circular(5),
    ),
    child: ListView.builder(
      key: const Key('install-output'),
      controller: _scroll,
      padding: const EdgeInsets.all(8),
      itemCount: _output.length,
      itemBuilder: (context, index) => Text(
        _output[index],
        style: const TextStyle(
          fontSize: 11,
          height: 1.3,
          fontFamily: 'monospace',
          color: didactaOnTerminal,
        ),
      ),
    ),
  );

  Widget _terminalText(BuildContext context, String text) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxHeight: 150),
    decoration: BoxDecoration(
      color: context.palette.terminal,
      borderRadius: BorderRadius.circular(5),
    ),
    padding: const EdgeInsets.all(8),
    child: SingleChildScrollView(
      child: SelectableText(
        text,
        style: const TextStyle(
          fontSize: 11,
          height: 1.3,
          fontFamily: 'monospace',
          color: didactaOnTerminal,
        ),
      ),
    ),
  );

  List<Widget> _actions(BuildContext context) {
    switch (_stage) {
      case _Stage.checking:
      case _Stage.installing:
        return [
          TextButton(
            onPressed: null,
            child: Text(
              _stage == _Stage.checking ? tr('Buscando…') : tr('Instalando…'),
            ),
          ),
        ];
      case _Stage.ready:
        final already = _needs.every((need) => need.installedAt != null);
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              _toInstall.isEmpty && !already ? tr('Cerrar') : tr('Cancelar'),
            ),
          ),
          if (already && widget.canRecompile)
            FilledButton(
              key: const Key('install-recompile'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Volver a compilar')),
            )
          else if (_toInstall.isNotEmpty)
            FilledButton.icon(
              key: const Key('install-confirm'),
              icon: const Icon(Icons.download_outlined, size: 16),
              onPressed: _install,
              label: Text(
                _toInstall.length == 1
                    ? tr('Instalar «{0}»', [_toInstall.single])
                    : tr('Instalar {0} paquetes', [_toInstall.length]),
              ),
            ),
        ];
      case _Stage.done:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cerrar')),
          ),
          if (widget.canRecompile)
            FilledButton.icon(
              key: const Key('install-recompile'),
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: () => Navigator.of(context).pop(true),
              label: Text(tr('Volver a compilar')),
            ),
        ];
      case _Stage.failed:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cerrar')),
          ),
          if (_toInstall.isNotEmpty)
            FilledButton(
              key: const Key('install-retry'),
              onPressed: _install,
              child: Text(tr('Reintentar')),
            ),
        ];
    }
  }

  static Host _host(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.macOS => Host.macos,
        TargetPlatform.windows => Host.windows,
        _ => Host.linux,
      };
}
