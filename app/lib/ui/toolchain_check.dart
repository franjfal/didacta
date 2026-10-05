/// «¿Está todo lo que hace falta?», con el botón para que lo esté.
///
/// La misma lista en los dos sitios donde alguien se hace esa pregunta: la
/// bienvenida --donde es un paso-- y Ajustes --donde se vuelve cuando algo ha
/// dejado de funcionar--. Una sola pantalla y no dos parecidas, porque lo que
/// se enseña es exactamente lo mismo y dos copias acaban diciendo cosas
/// distintas del mismo sistema.
///
/// Cuatro decisiones, y las cuatro salen de lo mismo: **instalar cosas de
/// terceros falla a menudo, y falla de maneras que Didacta no controla**.
///
/// **Se dice dónde está, no solo que está.** Una fila que dijera «Git ✓» no
/// sirve de nada el día que hay dos gits; con la ruta y la versión delante,
/// quien mira sabe cuál se está usando. Y cuando no aparece, se enseña dónde
/// se ha mirado: ese es el caso frecuente de verdad --está instalado en un
/// sitio que no es ninguno de los de siempre-- y sin la lista el consejo
/// «instálalo» es el equivocado.
///
/// **El botón dice lo que va a hacer antes de hacerlo.** «Instalar con
/// Homebrew», «Descargar MacTeX (~6 GB)», «Instalar las herramientas de
/// Apple». Un botón que pusiera «Instalar» a secas y se pusiera a bajar seis
/// gigas por una conexión de casa sería una emboscada.
///
/// **Lo que termina fuera se dice que termina fuera.** El instalador de Apple
/// y el de macOS se abren en su ventana y Didacta no sabe cuándo acaban. En
/// lugar de una barra falsa, la fila queda esperando y pide volver a
/// comprobar, que es lo honesto y además lo único que funciona.
///
/// **Fallar no es el final.** Cuando algo no sale, el modal trae las tres
/// cosas que hacen falta para salir del paso: qué se intentó, qué contestó, y
/// cómo se hace a mano. Más el enlace a la guía oficial, que es donde hay que
/// mandar a alguien cuando lo que sabemos no ha bastado.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/browser.dart';
import '../data/diagnostics.dart';
import '../data/toolchain.dart';
import '../model/toolchain.dart';
import '../state/session.dart';
import 'theme.dart';
import 'working.dart';
import '../l10n/tr.dart';

class ToolchainCheck extends StatefulWidget {
  const ToolchainCheck({
    super.key,
    required this.session,
    this.toolchain,
    this.onChanged,
    this.foldWhenReady = false,
  });

  final Session session;

  /// Si, con todo en su sitio y la interfaz Esencial, se enseña en una línea.
  ///
  /// En Ajustes: las rutas y las versiones contestan «¿cuál de los dos gits
  /// está usando?», que es la pregunta del día que algo va raro, y el resto
  /// de los días son cuatro filas que no dicen nada. Plegadas, con «Ver
  /// detalles». En la bienvenida no: ahí es la primera vez que se ven.
  final bool foldWhenReady;

  /// La implementación con la que se comprueba e instala.
  ///
  /// Se inyecta para poder probar esta pantalla: la de verdad lanza procesos
  /// y descarga instaladores, y eso dentro de un test de widgets --donde el
  /// reloj es falso-- no termina nunca.
  final Toolchain? toolchain;

  /// Se llama cuando algo ha cambiado de estado, para que quien la contiene
  /// vuelva a mirar lo suyo --la sección de compilar, el paso siguiente--.
  final VoidCallback? onChanged;

  @override
  State<ToolchainCheck> createState() => _ToolchainCheckState();
}

class _ToolchainCheckState extends State<ToolchainCheck> {
  late Toolchain _toolchain = widget.toolchain ?? widget.session.toolchain();

  /// Lo que se sabe de cada una. Vacío mientras se comprueba por primera vez.
  final Map<ToolId, ToolState> _states = {};

  /// Cuál se está instalando ahora, si alguna. Una cada vez: dos
  /// instaladores a la vez compitiendo por el mismo `tlmgr` es una forma
  /// nueva de romper algo que ya es frágil.
  ToolId? _installing;

  bool _checking = false;

  /// La última línea de lo que está pasando.
  String _progress = '';

  /// Qué se está haciendo, cuando [_progress] son las líneas de otro: al
  /// descargar el motor, git escribe «Cloning into '.'...» y ahí ya no pone
  /// qué se descarga.
  String _doing = '';

  /// Las que han terminado su instalación fuera de Didacta y todavía no han
  /// aparecido. Es lo que convierte «no está» en «se está instalando ahí
  /// fuera», que no es lo mismo para quien mira.
  final Set<ToolId> _handedOver = {};

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void didUpdateWidget(ToolchainCheck old) {
    super.didUpdateWidget(old);
    // El motor puede cambiar por debajo --se descarga desde aquí, o se elige
    // en Ajustes-- y la comprobación tiene que mirar el de ahora.
    if (widget.toolchain == null &&
        (old.session.enginePath != widget.session.enginePath ||
            old.session.texPath != widget.session.texPath)) {
      _toolchain = widget.session.toolchain();
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() => _checking = true);
    final List<ToolState> found;
    try {
      found = await _toolchain.inspectAll();
    } catch (caught, trace) {
      // Que nunca se quede girando: lo que no se ha podido comprobar se dice
      // en su fila, y «Volver a comprobar» vuelve a estar a mano.
      Diagnostics.instance.note('toolchain_check', caught, trace);
      if (!mounted) return;
      setState(() {
        for (final tool in didactaTools) {
          _states[tool.id] ??= ToolState(
            tool: tool,
            searched: const [],
            problem: tr('No se ha podido comprobar: {0}', [caught]),
          );
        }
        _checking = false;
      });
      widget.onChanged?.call();
      return;
    }
    if (!mounted) return;
    setState(() {
      for (final state in found) {
        _states[state.tool.id] = state;
        // Lo que ya está deja de estar «instalándose fuera»: es justo lo que
        // se estaba esperando.
        if (state.ready) _handedOver.remove(state.tool.id);
      }
      _checking = false;
    });
    widget.onChanged?.call();
  }

  /// Si falta algo. Lo mira quien contiene esta pantalla para decidir si el
  /// paso siguiente tiene sentido.
  bool get _allReady =>
      _states.length == didactaTools.length &&
      _states.values.every((state) => state.ready);

  /// Si se ha pedido ver el detalle estando plegado.
  bool _unfolded = false;

  bool get _folded =>
      widget.foldWhenReady &&
      !widget.session.completeInterface &&
      !_unfolded &&
      _installing == null &&
      _allReady &&
      _states.values.every((state) => state.notes.isEmpty);

  List<Tool> get _missing => [
    for (final tool in didactaTools)
      if (_states[tool.id]?.ready != true) tool,
  ];

  // ------------------------------------------------------------ instalar ---

  Future<void> _install(Tool tool) async {
    // El motor no pasa por la tabla de planes: lo descarga la sesión, que ya
    // sabe clonar y ya sabe recordar dónde lo ha dejado.
    if (tool.id == ToolId.engine) return _installEngine();

    final plan = await _planFor(tool);
    if (plan == null || !mounted) return;

    // Un plan manual no se «ejecuta»: se enseña. Llevarlo por el mismo
    // camino que los demás para que acabe fallando sería fabricar un error
    // donde solo hay unas instrucciones.
    if (!plan.automatic) {
      await _explain(tool, plan, message: plan.explains, failed: false);
      return;
    }

    setState(() {
      _installing = tool.id;
      _progress = plan.explains;
    });
    try {
      await _toolchain.install(
        plan,
        onOutput: (line) {
          if (mounted) setState(() => _progress = line);
        },
      );
      if (!mounted) return;
      if (plan.handsOver) _handedOver.add(tool.id);
      setState(() {
        _installing = null;
        _progress = plan.handsOver
            ? tr(
                'El instalador está abierto. Cuando termine, vuelve a comprobar.',
              )
            : tr('Instalado. Comprobando…');
      });
      await _check();
      if (!mounted) return;
      // Instalado y sigue sin aparecer. Pasa: hay instaladores que dejan el
      // programa en un sitio que no es ninguno de los de siempre. Decirlo
      // con la lista delante es mejor que un tick que miente.
      if (_states[tool.id]?.ready != true && !plan.handsOver) {
        await _explain(
          tool,
          plan,
          message: tr(
            'La instalación terminó sin errores, pero {0} sigue '
            'sin aparecer donde Didacta busca.',
            [tool.name],
          ),
        );
      }
    } on ToolInstallException catch (thrown) {
      if (!mounted) return;
      setState(() {
        _installing = null;
        _progress = '';
      });
      await _explain(
        tool,
        plan,
        message: thrown.message,
        detail: thrown.detail,
      );
    } catch (thrown) {
      if (!mounted) return;
      setState(() {
        _installing = null;
        _progress = '';
      });
      await _explain(tool, plan, message: '$thrown');
    } finally {
      if (mounted && _installing == tool.id) {
        setState(() => _installing = null);
      }
    }
  }

  /// Qué plan toca para esta herramienta, preguntando cuando hay que elegir.
  Future<InstallPlan?> _planFor(Tool tool) async {
    if (tool.id != ToolId.latex) {
      return _toolchain.choose(plansFor(tool.id, _toolchain.host));
    }
    // LaTeX se elige. Entre TinyTeX y MacTeX hay cien megas y seis gigas de
    // diferencia, y eso no lo puede decidir la aplicación por nadie.
    final option = await showDialog<LatexOption>(
      context: context,
      builder: (context) => _LatexChooser(host: _toolchain.host),
    );
    if (option == null) return null;
    // El plan de la opción elegida puede depender de algo --winget-- y
    // entonces cae en su alternativa, que es la manual con instrucciones.
    return _toolchain.choose([option.plan]);
  }

  Future<void> _installEngine() async {
    setState(() {
      _installing = ToolId.engine;
      _doing = tr('Descargando el motor…');
      _progress = '';
    });
    try {
      final where = await widget.session.installEngine(
        onProgress: (line) {
          if (mounted) setState(() => _progress = line);
        },
      );
      if (!mounted) return;
      // La sesión ya se ha quedado con la ruta nueva, así que la cadena que
      // salga de ella mirará ahí.
      _toolchain = widget.toolchain ?? widget.session.toolchain();
      setState(() {
        _installing = null;
        _doing = '';
        _progress = tr('El motor está en {0}', [where]);
      });
      await _check();
    } catch (thrown) {
      if (!mounted) return;
      setState(() {
        _installing = null;
        _doing = '';
        _progress = '';
      });
      await _explain(
        toolById(ToolId.engine),
        plansFor(ToolId.engine, _toolchain.host).first,
        message: '$thrown',
      );
    }
  }

  /// Instala lo que falte, de una en una y en orden.
  ///
  /// En orden porque las dependencias son reales: el motor se descarga **con
  /// git**, así que empezar por el motor en una máquina sin git es empezar
  /// por el fallo.
  Future<void> _installMissing() async {
    for (final tool in _missing) {
      await _install(tool);
      if (!mounted) return;
      // Si sigue faltando, parar: encadenar la siguiente instalación sobre
      // una que acaba de fallar es apilar errores.
      if (_states[tool.id]?.ready != true && !_handedOver.contains(tool.id)) {
        return;
      }
    }
  }

  Future<void> _explain(
    Tool tool,
    InstallPlan plan, {
    required String message,
    String? detail,
    bool failed = true,
  }) => showDialog<void>(
    context: context,
    builder: (context) => ToolProblemDialog(
      tool: tool,
      plan: plan,
      message: message,
      detail: detail,
      failed: failed,
      state: _states[tool.id],
      onRetry: () {
        Navigator.of(context).pop();
        unawaited(_check());
      },
    ),
  );

  // --------------------------------------------------------------- pintar ---

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session.settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    if (_folded) {
      // En una columna, como la vista entera: una tarjeta suelta se estiraría
      // hasta el alto que le den.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FoldedTools(onDetails: () => setState(() => _unfolded = true)),
        ],
      );
    }
    final missing = _missing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final tool in didactaTools)
                  _ToolRow(
                    key: Key('tool-${tool.id.name}'),
                    tool: tool,
                    state: _states[tool.id],
                    checking: _checking && _states[tool.id] == null,
                    installing: _installing == tool.id,
                    waiting: _handedOver.contains(tool.id),
                    // Nada más mientras se instala algo: dos instalaciones a
                    // la vez no es un caso que merezca existir.
                    onInstall: _installing != null || _checking
                        ? null
                        : () => _install(tool),
                    last: tool == didactaTools.last,
                  ),
              ],
            ),
          ),
        ),
        if (_installing != null) ...[
          const SizedBox(height: 10),
          Working(step: _doing, line: _progress),
        ] else if (_progress.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _progress,
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (missing.length > 1)
              FilledButton.icon(
                key: const Key('install-missing'),
                onPressed: _installing != null || _checking
                    ? null
                    : _installMissing,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(
                  tr('Instalar lo que falta ({0})', [missing.length]),
                ),
              ),
            OutlinedButton.icon(
              key: const Key('recheck-tools'),
              onPressed: _installing != null || _checking ? null : _check,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(tr('Volver a comprobar')),
            ),
          ],
        ),
        if (_allReady) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 16,
                color: context.palette.accentDark,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Está todo. Didacta puede traer material y sacar PDF.'),
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Todo en su sitio, en una línea: qué hay y cómo ver el detalle.
class _FoldedTools extends StatelessWidget {
  const _FoldedTools({required this.onDetails});

  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('tools-folded'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: context.palette.accentDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Está todo. Didacta puede traer material y sacar PDF.'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [for (final tool in didactaTools) tool.name].join(' · '),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('tools-details'),
            onPressed: onDetails,
            child: Text(tr('Ver detalles')),
          ),
        ],
      ),
    ),
  );
}

/// Una herramienta, con lo que se sabe de ella y lo que se puede hacer.
class _ToolRow extends StatelessWidget {
  const _ToolRow({
    super.key,
    required this.tool,
    required this.state,
    required this.checking,
    required this.installing,
    required this.waiting,
    required this.onInstall,
    required this.last,
  });

  final Tool tool;
  final ToolState? state;
  final bool checking;
  final bool installing;

  /// Se está instalando en una ventana que no es la nuestra.
  final bool waiting;

  final VoidCallback? onInstall;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final found = state;
    final ready = found?.ready == true;

    return Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: context.palette.rule)),
            ),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 10),
            child: _mark(context, ready, checking || installing),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tool.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (found?.version != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        found!.version!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.palette.muted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  tool.what,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: context.palette.muted,
                  ),
                ),
                // Dónde está. Es lo que contesta «¿cuál de los dos gits está
                // usando?», que es la pregunta del día que algo va raro.
                if (ready && found?.path != null) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    found!.path!,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: context.palette.muted,
                    ),
                  ),
                ],
                if (ready)
                  for (final note in found!.notes) ...[
                    const SizedBox(height: 6),
                    Note(note, tone: context.palette.muted),
                  ],
                if (!ready && found != null) ...[
                  const SizedBox(height: 6),
                  Note(
                    // El problema manda sobre el «no está»: «está en /usr/bin
                    // y no contesta» es otra cosa, y decir que falta algo que
                    // está ahí manda a instalarlo otra vez.
                    found.problem ??
                        (waiting
                            ? tr(
                                'Se está instalando fuera de Didacta. Cuando '
                                'termine, pulsa «Volver a comprobar».',
                              )
                            : tool.missing),
                    tone: waiting
                        ? context.palette.muted
                        : context.palette.teacher,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Mientras se comprueba, el botón no está y no hay nada en su
          // sitio: ya gira la marca de la izquierda, y dos ruedas por fila
          // dicen lo mismo dos veces.
          if (!checking && !ready)
            OutlinedButton(
              key: Key('install-${tool.id.name}'),
              onPressed: installing ? null : onInstall,
              child: Text(waiting ? tr('Reintentar') : tr('Instalar')),
            ),
        ],
      ),
    );
  }

  Widget _mark(BuildContext context, bool ready, bool busy) {
    if (busy) {
      return const SizedBox(
        width: 17,
        height: 17,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Icon(
      ready ? Icons.check_circle : Icons.radio_button_unchecked,
      size: 17,
      color: ready ? context.palette.accentDark : context.palette.muted,
    );
  }
}

/// Elegir distribución de TeX.
///
/// Existe porque es la única de las cuatro en la que hay una decisión de
/// verdad: cien megas sin contraseña o seis gigas con todo CTAN dentro, y la
/// respuesta correcta depende del disco, de la conexión y de si la máquina es
/// tuya. Didacta no puede saber eso, así que pregunta con los tres datos que
/// hacen falta para contestar: cuánto ocupa, si pide administrador y para
/// quién es cada una.
class _LatexChooser extends StatefulWidget {
  const _LatexChooser({required this.host});

  final Host host;

  @override
  State<_LatexChooser> createState() => _LatexChooserState();
}

class _LatexChooserState extends State<_LatexChooser> {
  late final List<LatexOption> _options = latexOptions(widget.host);
  late LatexOption _chosen = _options.firstWhere(
    (option) => option.recommended,
    orElse: () => _options.first,
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('¿Qué distribución de TeX?')),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Cualquiera de estas sirve: Didacta solo necesita latexmk y '
              'paquetes que están en CTAN. Lo que cambia es cuánto ocupa y si '
              'hace falta la contraseña de administrador.',
            ),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: context.palette.muted,
            ),
          ),
          const SizedBox(height: 14),
          for (final option in _options)
            _OptionRow(
              option: option,
              chosen: option.id == _chosen.id,
              onPick: () => setState(() => _chosen = option),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Cancelar')),
      ),
      FilledButton(
        key: const Key('latex-choose'),
        onPressed: () => Navigator.of(context).pop(_chosen),
        child: Text(_chosen.plan.label),
      ),
    ],
  );
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.chosen,
    required this.onPick,
  });

  final LatexOption option;
  final bool chosen;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('latex-${option.id}'),
    onTap: onPick,
    borderRadius: BorderRadius.circular(Radii.control),
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: chosen ? context.palette.selected : null,
        border: Border.all(
          color: chosen ? context.palette.accentDark : context.palette.rule,
        ),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 9),
            child: Icon(
              chosen
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: chosen
                  ? context.palette.accentDark
                  : context.palette.muted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wrap y no Row: «MacTeX · ~6 GB · pide la contraseña de
                // administrador» no cabe en una línea del diálogo, y una
                // fila que se desborda esconde justo el aviso que importa.
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      option.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      option.size,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.palette.muted,
                      ),
                    ),
                    if (option.needsAdmin)
                      Text(
                        tr('pide la contraseña de administrador'),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.teacher,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  option.what,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Lo que se enseña cuando una instalación no sale --o cuando no se puede
/// ni intentar.
///
/// Tres partes y en este orden: **qué ha pasado**, **qué contestó** y **cómo
/// se hace a mano**. El orden importa: quien abre esto quiere primero saber si
/// es culpa suya, y acabar con algo que pueda hacer ahora. Un modal que
/// terminara en el volcado del error dejaría a alguien mirando una pared.
///
/// Sirve para los dos casos porque el contenido útil es el mismo, pero no
/// dice lo mismo en los dos: en Linux, donde instalar pide `sudo` y Didacta
/// no lo intenta siquiera, titular «no se pudo instalar» sería anunciar un
/// fallo que no ha ocurrido. [failed] es lo que los distingue.
class ToolProblemDialog extends StatelessWidget {
  const ToolProblemDialog({
    super.key,
    required this.tool,
    required this.plan,
    required this.message,
    this.detail,
    this.state,
    this.onRetry,
    this.failed = true,
  });

  final Tool tool;
  final InstallPlan plan;
  final String message;

  /// Lo que escribió el proceso. En monoespaciada y con un botón para
  /// copiarlo: es lo que alguien va a pegar en una búsqueda o en una
  /// incidencia, y transcribirlo a mano de una captura no lo hace nadie.
  final String? detail;

  /// Lo que se sabía de la herramienta, para poder decir dónde se ha mirado.
  final ToolState? state;

  final VoidCallback? onRetry;

  /// Si se llegó a intentar y salió mal. Falso cuando aquí no hay nada que
  /// intentar y esto son solo las instrucciones.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final steps = plan.manualSteps;
    final searched = state?.searched ?? const <String>[];
    return AlertDialog(
      title: Text(
        failed
            ? tr('{0}: no se pudo instalar', [tool.name])
            : tr('{0}: cómo instalarlo', [tool.name]),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Note(
                message,
                tone: failed ? context.palette.teacher : context.palette.muted,
              ),
              if (failed) ...[
                const SizedBox(height: 12),
                Text(
                  tr('Se intentó: {0}.', [plan.label]),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.muted,
                  ),
                ),
              ],
              if (detail != null && detail!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: context.palette.panel,
                    border: Border.all(color: context.palette.rule),
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(9),
                    child: SelectableText(
                      detail!.trim(),
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: detail!.trim())),
                    icon: const Icon(Icons.copy_outlined, size: 14),
                    label: Text(tr('Copiar el detalle')),
                  ),
                ),
              ],
              if (steps.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  tr('Cómo hacerlo a mano'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('· ', style: TextStyle(fontSize: 12.5)),
                        Expanded(
                          child: SelectableText(
                            step,
                            style: const TextStyle(fontSize: 12, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              // Dónde se ha mirado. Va al final y en pequeño porque solo le
              // sirve a quien ya tiene la herramienta instalada, pero a ese
              // le sirve más que todo lo demás junto.
              if (searched.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tr(
                    '¿Ya la tienes instalada? Didacta la ha buscado en: '
                    '{0}.',
                    [searched.join(', ')],
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('open-guide'),
          onPressed: () => openLink(tool.guide),
          icon: const Icon(Icons.open_in_new, size: 15),
          label: Text(tr('La guía oficial')),
        ),
        if (onRetry != null)
          TextButton(
            key: const Key('problem-recheck'),
            onPressed: onRetry,
            child: Text(tr('Volver a comprobar')),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cerrar')),
        ),
      ],
    );
  }
}
