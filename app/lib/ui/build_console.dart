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
import 'package:flutter/services.dart';

import '../state/build_console.dart';
import 'theme.dart';

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
      if (mounted) Navigator.of(context).maybePop();
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
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                            itemCount:
                                console.lines.length +
                                (console.dropped > 0 ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (console.dropped > 0) {
                                if (index == 0) {
                                  return _ConsoleLine(
                                    '… se han descartado las primeras '
                                    '${console.dropped} líneas',
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
    if (line.startsWith('!') || line.contains('Emergency stop')) {
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
    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(bottom: BorderSide(color: didactaRule)),
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
            Icon(
              console.failure == null
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 17,
              color: console.failure == null
                  ? didactaAccentDark
                  : didactaTeacher,
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  console.title.isEmpty ? 'Compilación' : console.title,
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
                        ? 'En marcha · ${seconds.toStringAsFixed(0)} s'
                        : 'Terminada en ${seconds.toStringAsFixed(1)} s',
                    if (console.total > 0)
                      '${console.done} de ${console.total}',
                    if (console.running && console.step.isNotEmpty)
                      console.step,
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
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
                      backgroundColor: didactaRule,
                      color: console.ok ? didactaAccentDark : didactaTeacher,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const Key('console-close'),
            tooltip: console.running
                ? 'Ocultar. La compilación sigue'
                : 'Cerrar',
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
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(top: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            console.isEmpty ? console.about : '${console.lines.length} líneas',
            style: const TextStyle(fontSize: 11.5, color: didactaMuted),
          ),
        ),
        // Solo cuando se ha dejado de seguir: mientras va detrás de la
        // última línea, un botón que dice «ir al final» no hace nada.
        if (!following)
          TextButton.icon(
            key: const Key('console-follow'),
            icon: const Icon(Icons.vertical_align_bottom, size: 16),
            label: const Text('Seguir el final'),
            style: TextButton.styleFrom(
              foregroundColor: didactaMuted,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onFollow,
          ),
        TextButton.icon(
          key: const Key('console-copy'),
          icon: const Icon(Icons.copy_all_outlined, size: 16),
          label: const Text('Copiar'),
          style: TextButton.styleFrom(
            foregroundColor: didactaMuted,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: console.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: console.text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Registro copiado.')),
                  );
                },
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(console.running ? 'Ocultar' : 'Cerrar'),
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
