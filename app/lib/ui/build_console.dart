/// El terminal de una compilación, mientras corre.
///
/// Compilar es lo único que hace esta aplicación que tarda: una unidad son
/// tres segundos, un tema con veinte unidades en tres idiomas es un minuto
/// largo. Hasta ahora eso era un botón que ponía «Compilando…» y nada más, y
/// un minuto de silencio no se distingue de un cuelgue. Lo que LaTeX escribe
/// mientras tanto --qué fichero está leyendo, qué paquete está cargando, qué
/// pasada va-- es exactamente la información que falta, y ya existía: se
/// estaba tirando.
///
/// Dos decisiones que conviene dejar dichas:
///
/// **Se enseña entero, no un resumen.** Los diagnósticos parseados siguen
/// donde estaban, en las tarjetas de resultado, y son la respuesta a «¿qué
/// ha fallado?». Esto es la respuesta a la otra pregunta --«¿qué está
/// haciendo?»-- y esa no se contesta con una selección: el aviso que importa
/// suele ser justo el que un filtro habría tirado.
///
/// **El registro sobrevive al modal.** Cerrar la ventana no para la
/// compilación ni borra lo que dijo; se vuelve a abrir y ahí sigue. Esta es
/// la razón de que el estado viva en la sesión y no en el widget.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Cuántas líneas se guardan.
///
/// Una compilación normal escribe unos cientos; un tema entero en tres
/// idiomas, unos miles. El tope está para que una compilación que se
/// descontrole --un bucle de avisos de LaTeX, que existen-- no se lleve la
/// memoria por delante, y es alto de sobra para que nadie llegue a él
/// compilando de verdad.
const int _maxLines = 20000;

/// Lo que el motor va diciendo, y en qué estado está.
class BuildConsole extends ChangeNotifier {
  final List<String> _lines = [];

  /// Cuántas líneas se han caído por arriba al llegar al tope.
  int _dropped = 0;

  String _title = '';
  bool _running = false;
  DateTime? _startedAt;
  Duration? _took;
  Object? _failure;

  bool _disposed = false;
  Timer? _pulse;

  /// Las líneas, de la primera a la última.
  List<String> get lines => UnmodifiableListView(_lines);

  int get dropped => _dropped;

  /// Qué se está compilando: «este tema», «Diapositivas · es».
  String get title => _title;

  bool get running => _running;

  /// Lo que se tardó, una vez terminada.
  Duration? get took => _took;

  /// Cuánto lleva, o cuánto tardó.
  Duration get elapsed =>
      _took ??
      (_startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!));

  /// Por qué no se pudo ni lanzar, si pasó eso.
  ///
  /// Distinto de que la compilación falle: un error de LaTeX sale por el
  /// registro como todo lo demás, y esto es que el proceso no arrancó.
  Object? get failure => _failure;

  bool get isEmpty => _lines.isEmpty;

  /// Empieza una compilación: se tira lo de la anterior.
  ///
  /// Se tira a propósito. Lo que interesa es lo que está pasando ahora, y un
  /// registro acumulado entre compilaciones obliga a buscar dónde empieza la
  /// que se está mirando.
  void start(String title) {
    _lines.clear();
    _dropped = 0;
    _title = title;
    _running = true;
    _startedAt = DateTime.now();
    _took = null;
    _failure = null;
    _notifyNow();
  }

  /// Una línea del motor, tal cual la escribió.
  void add(String line) {
    if (_disposed) return;
    _lines.add(line);
    if (_lines.length > _maxLines) {
      final excess = _lines.length - _maxLines;
      _lines.removeRange(0, excess);
      _dropped += excess;
    }
    _schedule();
  }

  /// Se acabó. [failure] solo cuando no se pudo ni lanzar el motor.
  void finish({Object? failure}) {
    _running = false;
    _took = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    _failure = failure;
    if (failure != null) add('--- $failure');
    _notifyNow();
  }

  /// Todo el registro en un texto, para el portapapeles.
  String get text => _lines.join('\n');

  /// Avisar como mucho quince veces por segundo.
  ///
  /// LaTeX escribe a ráfagas de cientos de líneas, y reconstruir la ventana
  /// una vez por línea convierte el visor en el cuello de botella de la
  /// compilación que está enseñando. A este ritmo se lee igual de seguido y
  /// no cuesta nada.
  void _schedule() {
    if (_pulse != null || _disposed) return;
    _pulse = Timer(const Duration(milliseconds: 66), () {
      _pulse = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _notifyNow() {
    _pulse?.cancel();
    _pulse = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pulse?.cancel();
    _pulse = null;
    super.dispose();
  }
}

/// Abre el terminal de la compilación.
///
/// No bloquea: la compilación sigue por su cuenta y cerrar esto no la para.
/// Se puede volver a abrir mientras corre y después, que es lo que permite
/// quitarlo de en medio sin perder nada.
Future<void> showBuildConsole(BuildContext context, BuildConsole console) =>
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BuildConsoleDialog(console: console),
    );

class BuildConsoleDialog extends StatefulWidget {
  const BuildConsoleDialog({super.key, required this.console});

  final BuildConsole console;

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
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
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
                    ? const _Waiting()
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
    if (line.startsWith('$ ')) return _terminalDim;
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
              color: console.failure == null ? didactaAccentDark : didactaTeacher,
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
                  console.running
                      ? 'En marcha · ${seconds.toStringAsFixed(0)} s'
                      : 'Terminada en ${seconds.toStringAsFixed(1)} s',
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
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
            console.isEmpty
                ? 'Todo lo que escribe LaTeX, según lo escribe.'
                : '${console.lines.length} líneas',
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
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Arrancando el motor…',
        style: TextStyle(
          fontSize: 12.5,
          fontFamily: 'monospace',
          color: _terminalDim,
        ),
      ),
    ),
  );
}
