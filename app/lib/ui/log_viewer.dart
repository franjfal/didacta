/// «Ver log completo»: todo lo que dijo una compilación, para buscar en ello.
///
/// Las tarjetas de resultado contestan a «¿qué ha fallado?» con los
/// diagnósticos que el motor ya sabe leer. Casi siempre basta; cuando no
/// --un paquete que se queja con un mensaje raro, un error que el motor no
/// sabe atribuir, algo que solo se entiende con las veinte líneas de antes--
/// hace falta el registro entero, y hasta ahora había que ir a buscar el
/// `.log` a la carpeta de compilación.
///
/// Esto lo enseña sin salir de la aplicación: la salida de la compilación
/// (lo que escribieron latexmk y LaTeX por la consola) y el `.log` de cada
/// versión que falló, con números de línea, los errores marcados, un
/// buscador, saltos de error en error y el primero de verdad arriba, con su
/// fichero y su línea. Y se guarda como texto para abrirlo en otro sitio o
/// mandárselo a alguien.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/compiler.dart';
import '../state/build_console.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Una de las cosas que se pueden leer: la salida de la compilación, ya en
/// memoria, o un `.log` del disco.
class LogSource {
  const LogSource({required this.label, this.lines, this.path});

  /// Lo que dice la pestaña: «Salida de la compilación», «Libro · es · .log».
  final String label;

  /// Las líneas, si ya se tienen.
  final List<String>? lines;

  /// O de dónde leerlas.
  final String? path;
}

/// Lo que se puede leer de un trabajo terminado: el `.log` de cada versión
/// que falló, primero --es donde están los errores--, y después la salida
/// de la compilación entera.
List<LogSource> logSourcesFor({
  required Iterable<({String? what, CompileOutput output})> outputs,
  List<String> transcript = const [],
}) {
  // El documento solo si son varios: con uno, repetirlo en cada pestaña
  // las hace tan anchas que no caben, y no distingue nada.
  final several = outputs.map((entry) => entry.what).toSet().length > 1;
  return _sourcesFor(outputs, transcript, several);
}

List<LogSource> _sourcesFor(
  Iterable<({String? what, CompileOutput output})> outputs,
  List<String> transcript,
  bool several,
) => [
  for (final entry in outputs)
    if (!entry.output.ok && entry.output.log != null)
      LogSource(
        label: [
          if (several) ?entry.what,
          entry.output.profile,
          entry.output.language,
          '.log',
        ].join(' · '),
        path: entry.output.log,
      ),
  if (transcript.isNotEmpty)
    LogSource(label: tr('Salida de la compilación'), lines: transcript),
];

/// Lo mismo, para lo que haya en la consola de compilación.
List<LogSource> logSourcesOf(BuildConsole console) =>
    logSourcesFor(outputs: console.outputs, transcript: console.lines);

/// Abre el visor. [errors] son los diagnósticos que ya sacó el motor: el
/// primero de verdad es el que se enseña arriba.
Future<void> showLogViewer(
  BuildContext context, {
  required List<LogSource> sources,
  List<CompileDiagnostic> errors = const [],
  String? title,
}) => showDialog<void>(
  context: context,
  builder: (_) => LogViewerDialog(
    sources: sources,
    errors: errors,
    title: title ?? tr('Log completo'),
  ),
);

/// El primer error que importa de [diagnostics].
///
/// Los que salen detrás de otro --«Emergency stop», «Fatal error occurred»,
/// «no output PDF file produced»-- no cuentan: son la consecuencia, y
/// ponerlos arriba manda a buscar donde no está el problema.
CompileDiagnostic? firstRealError(Iterable<CompileDiagnostic> diagnostics) {
  CompileDiagnostic? fallback;
  for (final diagnostic in diagnostics) {
    if (!diagnostic.isError) continue;
    fallback ??= diagnostic;
    if (!_isAftermath(diagnostic.message)) return diagnostic;
  }
  return fallback;
}

bool _isAftermath(String message) {
  final lower = message.toLowerCase();
  return lower.contains('emergency stop') ||
      lower.contains('fatal error occurred') ||
      lower.contains('no output pdf file produced') ||
      lower.startsWith('==>');
}

/// Qué es una línea del registro.
enum LogLineKind { plain, error, warning, header }

final RegExp _fileLineError = RegExp(
  r'^(?:\./)?([^:\s][^:]*\.(?:tex|sty|cls|def|ldf|ltx)):(\d+): ',
);

/// Lo que se marca: los errores de LaTeX --que empiezan por `!` o, con
/// `-file-line-error`, por `fichero:línea:`--, los avisos y las cabeceras
/// que pone Didacta. Lo demás, tal cual: teñir de rojo lo que no es un error
/// hace que se deje de creer a lo que sí.
LogLineKind classifyLogLine(String line) {
  if (line.startsWith('===')) return LogLineKind.header;
  if (line.startsWith('! ') ||
      line == '!' ||
      line.startsWith('--- FAIL') ||
      _fileLineError.hasMatch(line)) {
    return LogLineKind.error;
  }
  if (line.contains('Warning:') || line.startsWith('Latexmk: ')) {
    return LogLineKind.warning;
  }
  return LogLineKind.plain;
}

/// Dónde empieza cada error de [lines]: los que van seguidos cuentan una
/// vez, y los que son consecuencia de otro (`Emergency stop`) no cuentan.
List<int> errorStarts(List<String> lines) {
  final found = <int>[];
  var previous = false;
  for (var i = 0; i < lines.length; i += 1) {
    final error = classifyLogLine(lines[i]) == LogLineKind.error;
    if (error && !previous && !_isAftermath(lines[i])) found.add(i);
    previous = error;
  }
  return found;
}

/// La línea de [lines] en la que está [diagnostic], o null.
int? lineOfDiagnostic(List<String> lines, CompileDiagnostic diagnostic) {
  final message = diagnostic.message.trim();
  if (message.isEmpty) return null;
  final probe = message.length > 60 ? message.substring(0, 60) : message;
  for (var i = 0; i < lines.length; i += 1) {
    if (lines[i].contains(probe)) return i;
  }
  return null;
}

/// Fichero y línea de un error leído del registro, cuando no hay
/// diagnóstico: `fichero.tex:42:` o la `l.42` que LaTeX escribe debajo.
({String? file, int? line}) whereIsLogError(List<String> lines, int index) {
  final located = _fileLineError.firstMatch(lines[index]);
  if (located != null) {
    return (file: located.group(1), line: int.tryParse(located.group(2)!));
  }
  for (final next in lines.skip(index + 1).take(12)) {
    final match = RegExp(r'^l\.(\d+)').firstMatch(next);
    if (match != null) return (file: null, line: int.parse(match.group(1)!));
  }
  return (file: null, line: null);
}

class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({
    super.key,
    required this.sources,
    required this.title,
    this.errors = const [],
  });

  final List<LogSource> sources;
  final List<CompileDiagnostic> errors;
  final String title;

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  static const double _rowHeight = 17;

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final TextEditingController _query = TextEditingController();
  final FocusNode _search = FocusNode();

  /// Lo leído de cada fuente, por su posición.
  final Map<int, List<String>> _loaded = {};
  final Map<int, Object> _failed = {};

  int _source = 0;
  List<int> _errors = const [];
  int _error = -1;
  List<int> _matches = const [];
  int _match = -1;

  /// La línea que se acaba de saltar, para marcarla.
  int? _focused;

  @override
  void initState() {
    super.initState();
    _query.addListener(_searchChanged);
    unawaited(_open(0));
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    _query.dispose();
    _search.dispose();
    super.dispose();
  }

  List<String>? get _lines => _loaded[_source];

  Future<void> _open(int index) async {
    setState(() {
      _source = index;
      _focused = null;
      _error = -1;
    });
    if (!_loaded.containsKey(index) && !_failed.containsKey(index)) {
      final source = widget.sources.isEmpty ? null : widget.sources[index];
      try {
        final List<String> lines;
        if (source?.lines != null) {
          lines = source!.lines!;
        } else if (source?.path != null) {
          // Sin exigir UTF-8: el log de LaTeX escribe los acentos con la
          // codificación del fichero que leía, y un carácter raro no puede
          // impedir leer el resto.
          final bytes = await XFile(source!.path!).readAsBytes();
          lines = const LineSplitter().convert(
            utf8.decode(bytes, allowMalformed: true),
          );
        } else {
          lines = const [];
        }
        _loaded[index] = lines;
      } catch (error) {
        _failed[index] = error;
      }
    }
    if (!mounted || _source != index) return;
    setState(() {
      _errors = errorStarts(_lines ?? const []);
      _recount();
    });
    // Al abrir, al primer error: es a lo que se viene.
    final first = _firstErrorLine();
    if (first != null) _jumpTo(first);
  }

  CompileDiagnostic? get _firstDiagnostic => firstRealError(widget.errors);

  int? _firstErrorLine() {
    final lines = _lines;
    if (lines == null || lines.isEmpty) return null;
    final diagnostic = _firstDiagnostic;
    if (diagnostic != null) {
      final at = lineOfDiagnostic(lines, diagnostic);
      if (at != null) return at;
    }
    return _errors.isEmpty ? null : _errors.first;
  }

  void _searchChanged() {
    setState(_recount);
    if (_matches.isNotEmpty) _jumpTo(_matches[_match]);
  }

  void _recount() {
    final query = _query.text.toLowerCase();
    final lines = _lines ?? const <String>[];
    _matches = query.isEmpty
        ? const []
        : [
            for (var i = 0; i < lines.length; i += 1)
              if (lines[i].toLowerCase().contains(query)) i,
          ];
    _match = _matches.isEmpty ? -1 : 0;
  }

  void _step(int by) {
    if (_matches.isEmpty) return;
    setState(() {
      _match = (_match + by) % _matches.length;
      if (_match < 0) _match += _matches.length;
    });
    _jumpTo(_matches[_match]);
  }

  void _stepError(int by) {
    if (_errors.isEmpty) return;
    setState(() {
      _error = _error < 0
          ? (by > 0 ? 0 : _errors.length - 1)
          : (_error + by) % _errors.length;
      if (_error < 0) _error += _errors.length;
    });
    _jumpTo(_errors[_error]);
  }

  /// Lleva la línea [index] a la vista, con tres de contexto por encima.
  void _jumpTo(int index) {
    setState(() => _focused = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_vertical.hasClients) return;
      final target = math.max(0, index - 3) * _rowHeight;
      _vertical.jumpTo(
        target.clamp(0.0, _vertical.position.maxScrollExtent).toDouble(),
      );
    });
  }

  /// Todo en un texto: cada fuente con su cabecera.
  Future<String> _everything() async {
    final parts = <String>[];
    for (var i = 0; i < widget.sources.length; i += 1) {
      if (!_loaded.containsKey(i) && !_failed.containsKey(i)) {
        final source = widget.sources[i];
        if (source.lines != null) {
          _loaded[i] = source.lines!;
        } else if (source.path != null) {
          try {
            final bytes = await XFile(source.path!).readAsBytes();
            _loaded[i] = const LineSplitter().convert(
              utf8.decode(bytes, allowMalformed: true),
            );
          } catch (error) {
            _failed[i] = error;
          }
        }
      }
      parts
        ..add('===== ${widget.sources[i].label} =====')
        ..addAll(_loaded[i] ?? [tr('(no se ha podido leer)')])
        ..add('');
    }
    return parts.join('\n');
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final where = await getSaveLocation(
      suggestedName: 'didacta-compilacion.log',
      acceptedTypeGroups: [
        XTypeGroup(label: tr('Texto'), extensions: const ['log', 'txt']),
      ],
      confirmButtonText: tr('Guardar'),
    );
    if (where == null) return;
    try {
      final text = await _everything();
      await XFile.fromData(
        utf8.encode(text),
        mimeType: 'text/plain',
        name: 'didacta-compilacion.log',
      ).saveTo(where.path);
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Guardado en {0}.', [where.path]))),
      );
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('No se ha podido guardar: {0}', [error]))),
      );
    }
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: await _everything()));
    messenger?.showSnackBar(SnackBar(content: Text(tr('Log copiado.'))));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _search.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _search.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f3): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
            _step(-1),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        child: SizedBox(
          width: size.width * 0.86,
          height: size.height * 0.84,
          child: Column(
            children: [
              _header(context),
              _toolbar(context),
              if (_firstDiagnostic != null || _errors.isNotEmpty)
                _firstErrorBanner(context),
              Expanded(child: _body(context)),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.palette.panel,
      border: Border(bottom: BorderSide(color: context.palette.rule)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
    child: Row(
      children: [
        Icon(Icons.article_outlined, size: 17, color: context.palette.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const Key('log-close'),
          tooltip: tr('Cerrar'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _toolbar(BuildContext context) {
    final searching = _query.text.isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.sources.length > 1)
            SegmentedButton<int>(
              key: const Key('log-sources'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (var i = 0; i < widget.sources.length; i += 1)
                  ButtonSegment(
                    value: i,
                    label: Text(
                      widget.sources[i].label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              selected: {_source},
              onSelectionChanged: (chosen) => _open(chosen.first),
            ),
          SizedBox(
            width: 260,
            child: TextField(
              key: const Key('log-search'),
              controller: _query,
              focusNode: _search,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 17),
                hintText: tr('Buscar en el log'),
                suffixText: searching
                    ? (_matches.isEmpty
                          ? tr('sin resultados')
                          : tr('{0} de {1}', [_match + 1, _matches.length]))
                    : null,
              ),
              onSubmitted: (_) {
                _step(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
                _search.requestFocus();
              },
            ),
          ),
          if (searching) ...[
            IconButton(
              key: const Key('log-match-previous'),
              tooltip: tr('Anterior'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              onPressed: _matches.isEmpty ? null : () => _step(-1),
            ),
            IconButton(
              key: const Key('log-match-next'),
              tooltip: tr('Siguiente'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              onPressed: _matches.isEmpty ? null : () => _step(1),
            ),
          ],
          // Saltar de error en error: en un log de tres mil líneas, los
          // errores son cinco, y son lo único que hay que leer.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errors.isEmpty
                    ? tr('Sin errores marcados')
                    : _error < 0
                    ? (_errors.length == 1
                          ? tr('1 error')
                          : tr('{0} errores', [_errors.length]))
                    : tr('Error {0} de {1}', [_error + 1, _errors.length]),
                key: const Key('log-error-count'),
                style: TextStyle(
                  fontSize: 12,
                  color: _errors.isEmpty
                      ? context.palette.muted
                      : context.palette.teacher,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                key: const Key('log-error-previous'),
                tooltip: tr('Error anterior'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: _errors.isEmpty ? null : () => _stepError(-1),
              ),
              IconButton(
                key: const Key('log-error-next'),
                tooltip: tr('Error siguiente'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward, size: 16),
                onPressed: _errors.isEmpty ? null : () => _stepError(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// El primer error de verdad, con su fichero y su línea, y un botón para
  /// ir a él.
  Widget _firstErrorBanner(BuildContext context) {
    final diagnostic = _firstDiagnostic;
    final lines = _lines ?? const <String>[];
    String? file;
    int? line;
    String message;
    String? context0;
    if (diagnostic != null) {
      file = diagnostic.path ?? diagnostic.file;
      line = diagnostic.line;
      message = diagnostic.message;
      context0 = diagnostic.context;
    } else {
      final at = _errors.first;
      final where = whereIsLogError(lines, at);
      file = where.file;
      line = where.line;
      message = lines[at].startsWith('! ') ? lines[at].substring(2) : lines[at];
    }
    final place = [
      if (file != null && file.isNotEmpty) file,
      if (line != null) tr('línea {0}', [line]),
    ].join(' · ');
    final target = _firstErrorLine();
    return Container(
      key: const Key('log-first-error'),
      width: double.infinity,
      color: context.palette.tint(context.palette.teacher),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 17, color: context.palette.teacher),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.isEmpty
                      ? tr('Primer error')
                      : tr('Primer error: {0}', [place]),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.palette.teacher,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  [
                    message,
                    if (context0 != null && context0.isNotEmpty) context0,
                  ].join('  ←  '),
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (target != null)
            TextButton(
              key: const Key('log-first-error-go'),
              onPressed: () {
                setState(() => _error = _errors.indexOf(target));
                _jumpTo(target);
              },
              child: Text(tr('Ir al error')),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final back = context.palette.terminal;
    if (widget.sources.isEmpty) {
      return Container(
        color: back,
        alignment: Alignment.center,
        child: Text(
          tr('Esta compilación no ha dejado registro.'),
          style: const TextStyle(color: _dim, fontSize: 12.5),
        ),
      );
    }
    if (_failed[_source] case final error?) {
      return Container(
        color: back,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          tr('No se ha podido leer {0}: {1}', [
            widget.sources[_source].path ?? '',
            error,
          ]),
          style: const TextStyle(color: _bad, fontSize: 12.5),
        ),
      );
    }
    final lines = _lines;
    if (lines == null) {
      return Container(
        color: back,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    final digits = '${lines.length}'.length;
    final gutter = digits * 7.4 + 18;
    final longest = lines.fold<int>(0, (most, l) => math.max(most, l.length));
    final query = _query.text.toLowerCase();
    final current = _match >= 0 && _match < _matches.length
        ? _matches[_match]
        : null;
    return Container(
      color: back,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(
            constraints.maxWidth,
            gutter + 14 + longest * 7.0,
          );
          return Scrollbar(
            controller: _horizontal,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: SelectionArea(
                  child: ListView.builder(
                    key: const Key('log-lines'),
                    controller: _vertical,
                    itemExtent: _rowHeight,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: lines.length,
                    itemBuilder: (context, index) => _LogRow(
                      number: index + 1,
                      text: lines[index],
                      gutter: gutter,
                      query: query,
                      focused: index == _focused,
                      currentMatch: index == current,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.palette.panel,
      border: Border(top: BorderSide(color: context.palette.rule)),
    ),
    padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            [
              if (_lines != null) tr('{0} líneas', [_lines!.length]),
              if (widget.sources.isNotEmpty &&
                  widget.sources[_source].path != null)
                widget.sources[_source].path!,
            ].join(' · '),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
          ),
        ),
        TextButton.icon(
          key: const Key('log-copy'),
          icon: const Icon(Icons.copy_all_outlined, size: 16),
          label: Text(tr('Copiar')),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.muted,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: widget.sources.isEmpty ? null : _copy,
        ),
        TextButton.icon(
          key: const Key('log-save'),
          icon: const Icon(Icons.download_outlined, size: 16),
          label: Text(tr('Descargar…')),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.muted,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: widget.sources.isEmpty ? null : _save,
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cerrar')),
        ),
      ],
    ),
  );
}

// Sobre el fondo de terminal, que es oscuro en los dos modos: los mismos
// tonos que la consola de compilación.
const Color _dim = Color(0xFF7C8394);
const Color _bad = Color(0xFFE08A8A);
const Color _warn = Color(0xFFD9B26A);
const Color _mark = Color(0xFF7FC08A);
const Color _found = Color(0x66D9B26A);
const Color _foundHere = Color(0xCCD9B26A);

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.number,
    required this.text,
    required this.gutter,
    required this.query,
    required this.focused,
    required this.currentMatch,
  });

  final int number;
  final String text;
  final double gutter;
  final String query;
  final bool focused;
  final bool currentMatch;

  @override
  Widget build(BuildContext context) {
    final kind = classifyLogLine(text);
    final colour = switch (kind) {
      LogLineKind.error => _bad,
      LogLineKind.warning => _warn,
      LogLineKind.header => _mark,
      LogLineKind.plain => didactaOnTerminal,
    };
    const style = TextStyle(
      fontSize: 11.5,
      height: 1.35,
      fontFamily: 'monospace',
    );
    return Container(
      // La línea a la que se acaba de saltar, en neutro: el rojo es de los
      // errores, y una búsqueda puede caer en cualquier sitio.
      color: focused
          ? const Color(0x24FFFFFF)
          : kind == LogLineKind.error
          ? const Color(0x1AE08A8A)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // El número no se selecciona: copiar un trozo del log tiene que
          // dar el log, no el log con números delante.
          SelectionContainer.disabled(
            child: SizedBox(
              width: gutter,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '$number',
                  textAlign: TextAlign.right,
                  style: style.copyWith(color: _dim),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              _spans(colour, kind),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: style.copyWith(
                color: colour,
                fontWeight: kind == LogLineKind.header
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// La línea, con lo buscado resaltado.
  TextSpan _spans(Color colour, LogLineKind kind) {
    final shown = text.isEmpty ? ' ' : text;
    if (query.isEmpty) return TextSpan(text: shown);
    final lower = shown.toLowerCase();
    final spans = <InlineSpan>[];
    var from = 0;
    while (true) {
      final at = lower.indexOf(query, from);
      if (at < 0) break;
      if (at > from) spans.add(TextSpan(text: shown.substring(from, at)));
      spans.add(
        TextSpan(
          text: shown.substring(at, at + query.length),
          style: TextStyle(
            backgroundColor: currentMatch ? _foundHere : _found,
            color: currentMatch ? const Color(0xFF1B1E24) : null,
          ),
        ),
      );
      from = at + query.length;
    }
    if (from < shown.length) spans.add(TextSpan(text: shown.substring(from)));
    return TextSpan(children: spans);
  }
}
