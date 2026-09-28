/// El terminal de un trabajo largo, en una ventana.
///
/// Lo que la herramienta va escribiendo, según lo escribe: qué fichero está
/// leyendo LaTeX, cuántos objetos lleva contados git. La alternativa que
/// había era un botón gris, y un minuto de eso no se distingue de un cuelgue
/// --se vuelve a pulsar, que es lo que hace cualquiera--.
///
/// Se enseña entero y sin filtrar. Los diagnósticos ya parseados siguen en
/// las tarjetas de resultado, que contestan a «¿qué ha fallado?»; esta
/// ventana contesta a «¿qué está haciendo?», y esa no se contesta con una
/// selección de líneas.
///
/// Cerrarla no para nada: el registro vive en la sesión --[BuildConsole]-- y
/// se puede volver a abrir mientras corre y después.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../state/build_console.dart';
import '../state/session.dart';
import '../data/compiler.dart';
import 'diagnostic_list.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Abre el terminal del trabajo que esté corriendo.
///
/// No bloquea: el trabajo sigue por su cuenta y cerrar esto no lo para.
/// Se puede volver a abrir mientras corre y después, que es lo que permite
/// quitarlo de en medio sin perder nada.
///
/// [autoClose] es para la ventana que acompaña a una compilación recién
/// lanzada: se quita sola en cuanto esa compilación acaba bien, porque lo que
/// se quiere entonces es el PDF y no el registro. Se queda si algo falló, que
/// es cuando el registro es justo lo que hay que leer. Consultando el
/// registro de una compilación anterior va en falso: ahí cerrar lo decide
/// quien lo abrió.
Future<void> showBuildConsole(
  BuildContext context,
  BuildConsole console, {
  bool autoClose = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (_) => BuildConsoleDialog(console: console, autoClose: autoClose),
);

class BuildConsoleDialog extends StatefulWidget {
  const BuildConsoleDialog({
    super.key,
    required this.console,
    this.autoClose = false,
  });

  final BuildConsole console;

  /// Si se cierra sola cuando la compilación acaba bien.
  final bool autoClose;

  @override
  State<BuildConsoleDialog> createState() => _BuildConsoleDialogState();
}

class _BuildConsoleDialogState extends State<BuildConsoleDialog> {
  final ScrollController _scroll = ScrollController();

  /// Si la ventana va detrás de la última línea.
  ///
  /// Deja de ir en cuanto alguien sube a leer algo, y vuelve a ir cuando baja
  /// del todo. Un visor que te arrastra al final mientras lees el error que
  /// acabas de encontrar es peor que no tener visor.
  bool _follow = true;

  /// Para que el reloj de la cabecera avance con la compilación parada en un
  /// `latexmk` que no escribe nada.
  Timer? _tick;

  /// Si se ha pedido el registro entero con la interfaz Esencial.
  bool _details = false;

  @override
  void initState() {
    super.initState();
    widget.console.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.console.running) setState(() {});
    });
    _closeIfDone();
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.console.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _closeIfDone();
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Se quita de en medio cuando la compilación ha ido bien.
  ///
  /// Porque lo que se quiere después de compilar es el PDF, y un modal que
  /// hay que cerrar cada vez acaba siendo un clic de peaje. Si ha fallado se
  /// queda: ahí el registro es lo que hay que leer, y buscarlo después sería
  /// exactamente lo que esto viene a evitar.
  ///
  /// Tampoco se cierra si quien mira ha subido a leer algo. Cerrar la
  /// ventana en mitad de una línea que se estaba leyendo es la misma falta
  /// de educación que arrastrarla al final.
  ///
  /// Se comprueba también al abrir, y no solo cuando el registro avisa: una
  /// compilación que latexmk resuelve con «todo está al día» termina antes
  /// de que esta ventana llegue a existir, y entonces el aviso de que
  /// terminó no lo oye nadie.
  void _closeIfDone() {
    if (!widget.autoClose || !_follow) return;
    final console = widget.console;
    if (console.running || !console.ok) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(Navigator.of(context).maybePop());
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    final position = notification.metrics;
    // Un margen, y no la igualdad: el salto al final deja décimas de píxel
    // de diferencia, y sin holgura el seguimiento se apagaría solo.
    final atBottom = position.pixels >= position.maxScrollExtent - 24;
    if (atBottom != _follow) setState(() => _follow = atBottom);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final console = widget.console;
    final size = MediaQuery.sizeOf(context);
    // Con la interfaz Esencial, lo que está haciendo en una línea y cómo ha
    // acabado; el registro entero, detrás de «Ver detalles». Salvo si ha
    // fallado sin errores ya sacados --un `git pull` que no entra, un motor
    // que no arranca--: entonces el porqué está en el registro, y se enseña.
    final failedBare =
        !console.running &&
        !console.ok &&
        !console.stopped &&
        console.problems.isEmpty;
    final plain =
        !_details &&
        !failedBare &&
        !(_sessionIn(context)?.completeInterface ?? true);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      child: SizedBox(
        width: size.width * 0.82,
        height: size.height * 0.78,
        child: Column(
          children: [
            _Header(console: console),
            // Los errores de un lote, cada uno con su documento y a dónde
            // lleva, encima del registro: son lo que hay que arreglar.
            if (!console.running && console.problems.isNotEmpty)
              _Problems(console: console),
            if (plain)
              Expanded(
                child: _Plain(
                  console: console,
                  onDetails: () => setState(() => _details = true),
                ),
              )
            else
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: _terminalBack,
                  child: console.isEmpty
                      ? _Waiting(console.opening)
                      : NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: SelectionArea(
                            child: ListView.builder(
                              key: const Key('build-console-lines'),
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                14,
                                14,
                              ),
                              itemCount:
                                  console.lines.length +
                                  (console.dropped > 0 ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (console.dropped > 0) {
                                  if (index == 0) {
                                    return _ConsoleLine(
                                      tr(
                                        '… se han descartado las primeras '
                                        '{0} líneas',
                                        [console.dropped],
                                      ),
                                      tone: _terminalDim,
                                    );
                                  }
                                  index -= 1;
                                }
                                return _ConsoleLine(console.lines[index]);
                              },
                            ),
                          ),
                        ),
                ),
              ),
            _Footer(console: console, following: _follow, onFollow: _toBottom),
          ],
        ),
      ),
    );
  }

  void _toBottom() {
    setState(() => _follow = true);
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }
}

/// Lo que se ve con la interfaz Esencial en lugar del registro.
///
/// Contesta a «¿qué está haciendo?» sin las mil líneas: el paso en curso y la
/// última línea que ha escrito, que es lo que dice que no se ha colgado. Por
/// dónde va un lote ya lo dice la cabecera. Y al acabar, cómo ha ido.
class _Plain extends StatelessWidget {
  const _Plain({required this.console, required this.onDetails});

  final BuildConsole console;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final last = console.lines.isEmpty ? console.opening : console.lines.last;
    final String headline;
    if (console.running) {
      headline = console.step.isNotEmpty ? console.step : console.title;
    } else if (console.stopped) {
      headline = tr('Detenida.');
    } else if (console.ok) {
      headline = console.summary ?? tr('Ha salido bien.');
    } else {
      headline =
          console.summary ?? tr('No ha salido: los errores están arriba.');
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('console-plain'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!console.running)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Icon(
                    console.ok
                        ? Icons.check_circle_outline
                        : console.stopped
                        ? Icons.stop_circle_outlined
                        : Icons.error_outline,
                    size: 28,
                    color: console.ok
                        ? context.palette.accentDark
                        : context.palette.muted,
                  ),
                ),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (console.running) ...[
                const SizedBox(height: 12),
                Text(
                  last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: context.palette.muted,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                key: const Key('console-details'),
                onPressed: onDetails,
                child: Text(tr('Ver detalles')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Problems extends StatelessWidget {
  const _Problems({required this.console});

  final BuildConsole console;

  static int _failed(Map<String, List<CompileDiagnostic>> groups) =>
      groups.values.where((list) => list.any((d) => d.isError)).length;

  /// «Con errores: 2 salidas · 3 que se salen de la página».
  static String _heading(Map<String, List<CompileDiagnostic>> groups) {
    final errors = _failed(groups);
    final overflowing = groups.length - errors;
    String outputs(int n) => n == 1 ? tr('1 salida') : tr('{0} salidas', [n]);
    return [
      if (errors > 0) tr('Con errores: {0}', [outputs(errors)]),
      if (overflowing > 0)
        errors > 0
            ? (overflowing == 1
                  ? tr('1 que se sale de la página')
                  : tr('{0} que se salen de la página', [overflowing]))
            : tr('Se salen de la página: {0}', [outputs(overflowing)]),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final session = _sessionIn(context);
    final groups = <String, List<CompileDiagnostic>>{};
    for (final problem in console.problems) {
      (groups[problem.what] ??= []).add(problem.diagnostic);
    }
    return Container(
      key: const Key('console-problems'),
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _heading(groups),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _failed(groups) > 0
                    ? context.palette.teacher
                    : context.palette.ex,
              ),
            ),
            const SizedBox(height: 6),
            for (final entry in groups.entries) ...[
              Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              if (session == null)
                for (final diagnostic in entry.value)
                  SelectableText(
                    diagnostic.plain,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: context.palette.teacher,
                    ),
                  )
              else
                DiagnosticList(
                  diagnostics: entry.value,
                  session: session,
                  shown: 3,
                  onOpen: () => Navigator.of(context).maybePop(),
                ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// El fondo del terminal.
///
/// Oscuro, contra el resto de la aplicación, que es clara. No por estética:
/// esto es salida de una herramienta, no contenido, y que se distinga de un
/// vistazo de un documento es lo que hace que nadie la confunda con uno.
const Color _terminalBack = Color(0xFF1B1E24);
const Color _terminalText = Color(0xFFD7DAE0);
const Color _terminalDim = Color(0xFF7C8394);
const Color _terminalMark = Color(0xFF7FC08A);
const Color _terminalBad = Color(0xFFE08A8A);
const Color _terminalWarn = Color(0xFFD9B26A);

/// Una línea del registro, coloreada por lo poco que se puede saber de ella.
///
/// El coloreado es deliberadamente pobre: las cabeceras que pone Didacta, los
/// errores de LaTeX --que empiezan por `!`-- y los avisos. Todo lo demás sale
/// tal cual. Interpretar más sería adivinar, y una línea teñida de rojo que
/// no era un error hace que las que sí lo son dejen de creerse.
final RegExp _fileLineError = RegExp(r'\.(tex|sty|cls|def):\d+: ');

class _ConsoleLine extends StatelessWidget {
  const _ConsoleLine(this.text, {this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colour = tone ?? _colourOf(text);
    return Text(
      text.isEmpty ? ' ' : text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.35,
        fontFamily: 'monospace',
        color: colour,
        fontWeight: text.startsWith('===') ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }

  static Color _colourOf(String line) {
    if (line.startsWith('===')) return _terminalMark;
    if (line.startsWith('--- FAIL')) return _terminalBad;
    if (line.startsWith('---')) return _terminalDim;
    if (line.startsWith(r'$ ')) return _terminalDim;
    // Con `-file-line-error` un error ya no empieza por `!`: es
    // `ruta.tex:42: mensaje`.
    if (line.startsWith('!') ||
        line.contains('Emergency stop') ||
        _fileLineError.hasMatch(line)) {
      return _terminalBad;
    }
    if (line.contains('Warning:') || line.startsWith('Latexmk: ')) {
      return _terminalWarn;
    }
    return _terminalText;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.console});

  final BuildConsole console;

  @override
  Widget build(BuildContext context) {
    final seconds = console.elapsed.inMilliseconds / 1000;
    // Parar desde aquí también: es donde se está mirando cuando se decide
    // que no hacía falta.
    final stopper = console.running ? _sessionIn(context) : null;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Row(
        children: [
          if (console.running)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            // Por [BuildConsole.ok] y no por [BuildConsole.failure]: `failure`
            // es que el motor no llegó a arrancar, y un LaTeX que falla
            // termina «bien» en ese sentido. Mirando eso, la marca salía verde
            // encima de un registro lleno de errores.
            Icon(
              console.ok ? Icons.check_circle_outline : Icons.error_outline,
              key: Key(console.ok ? 'console-ok' : 'console-failed'),
              size: 17,
              color: console.ok
                  ? context.palette.accentDark
                  : context.palette.teacher,
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  console.title.isEmpty ? tr('Compilación') : console.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  [
                    // El estado primero: es lo que se mira de reojo mientras
                    // se hace otra cosa.
                    console.running
                        ? tr('En marcha · {0} s', [seconds.toStringAsFixed(0)])
                        : console.stopped
                        ? tr('Detenida a los {0} s', [
                            seconds.toStringAsFixed(0),
                          ])
                        : console.ok
                        ? tr('Terminada en {0} s', [seconds.toStringAsFixed(1)])
                        : tr(
                            'Terminada con errores en '
                            '{0} s',
                            [seconds.toStringAsFixed(1)],
                          ),
                    if (!console.running && console.summary != null)
                      console.summary!
                    else if (console.total > 0)
                      tr('{0} de {1}', [console.done, console.total]),
                    if (console.running && console.step.isNotEmpty)
                      console.step,
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
                // La barra solo cuando hay varias piezas que contar. Con una,
                // un tramo entero que se llena de golpe al acabar no dice
                // nada que no diga ya el reloj.
                if (console.total > 1) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      key: const Key('console-progress'),
                      minHeight: 4,
                      value: console.done / console.total,
                      backgroundColor: context.palette.rule,
                      color: console.ok
                          ? context.palette.accentDark
                          : context.palette.teacher,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Parar desde aquí también: es donde se está mirando cuando se
          // decide que no hacía falta.
          if (stopper != null)
            TextButton(
              key: const Key('console-stop'),
              style: TextButton.styleFrom(
                foregroundColor: context.palette.teacher,
              ),
              onPressed: stopper.stoppingBuild ? null : stopper.stopBuilds,
              child: Text(
                stopper.stoppingBuild ? tr('Deteniendo…') : tr('Detener'),
              ),
            ),
          IconButton(
            key: const Key('console-close'),
            tooltip: console.running
                ? tr('Ocultar. La compilación sigue')
                : tr('Cerrar'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.console,
    required this.following,
    required this.onFollow,
  });

  final BuildConsole console;
  final bool following;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.palette.panel,
      border: Border(top: BorderSide(color: context.palette.rule)),
    ),
    padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            console.isEmpty
                ? console.about
                : tr('{0} líneas', [console.lines.length]),
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
          ),
        ),
        // Solo cuando se ha dejado de seguir: mientras va detrás de la
        // última línea, un botón que dice «ir al final» no hace nada.
        if (!following)
          TextButton.icon(
            key: const Key('console-follow'),
            icon: const Icon(Icons.vertical_align_bottom, size: 16),
            label: Text(tr('Seguir el final')),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.muted,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onFollow,
          ),
        TextButton.icon(
          key: const Key('console-copy'),
          icon: const Icon(Icons.copy_all_outlined, size: 16),
          label: Text(tr('Copiar')),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.muted,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: console.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: console.text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('Registro copiado.'))),
                  );
                },
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(console.running ? tr('Ocultar') : tr('Cerrar')),
        ),
      ],
    ),
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontFamily: 'monospace',
          color: _terminalDim,
        ),
      ),
    ),
  );
}

/// La sesión, si la ventana está dentro de la aplicación: suelta, en una
/// prueba, no la hay, y entonces no se ofrece parar.
Session? _sessionIn(BuildContext context) {
  try {
    return Provider.of<Session>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
