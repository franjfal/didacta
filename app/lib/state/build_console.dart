/// El registro de una compilación, mientras corre.
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
/// **Se guarda entero, no un resumen.** Los diagnósticos parseados siguen
/// donde estaban, en las tarjetas de resultado, y son la respuesta a «¿qué
/// ha fallado?». Esto es la respuesta a la otra pregunta --«¿qué está
/// haciendo?»-- y esa no se contesta con una selección: el aviso que importa
/// suele ser justo el que un filtro habría tirado.
///
/// **Sobrevive a la ventana que lo enseña.** Cerrar el modal no para la
/// compilación ni borra lo que dijo; se vuelve a abrir y ahí sigue. Esa es la
/// razón de que esto viva en la sesión y no en un widget.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

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
  bool _ok = true;
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

  /// Si la última compilación salió bien.
  ///
  /// Lo pregunta la ventana para decidir si se quita de en medio: cuando ha
  /// ido bien lo que se quiere ver es el PDF, y cuando no, el registro es
  /// justo lo que hace falta leer.
  bool get ok => _ok;

  /// Lo que se tardó, una vez terminada.
  Duration? get took => _took;

  /// Cuánto lleva, o cuánto tardó.
  Duration get elapsed =>
      _took ??
      (_startedAt == null
          ? Duration.zero
          : DateTime.now().difference(_startedAt!));

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
  void start(String title, {int total = 0}) {
    _lines.clear();
    _dropped = 0;
    _title = title;
    _running = true;
    _ok = true;
    _startedAt = DateTime.now();
    _took = null;
    _failure = null;
    _total = total;
    _done = 0;
    _step = '';
    _notifyNow();
  }

  /// Cuántas piezas tiene el trabajo, si se sabe.
  ///
  /// Cero es «una sola cosa, y no hay nada que contar»: compilar una versión
  /// tarda diez segundos y una barra de progreso de un solo tramo no dice
  /// nada. Compilar un curso entero son cuarenta minutos, y ahí saber que van
  /// nueve de treinta y ocho es la diferencia entre esperar y no saber si se
  /// ha colgado.
  int get total => _total;
  int _total = 0;

  int get done => _done;
  int _done = 0;

  /// Qué se está compilando ahora mismo.
  String get step => _step;
  String _step = '';

  /// Empieza una pieza del trabajo.
  void startStep(String what) {
    _step = what;
    _notifyNow();
  }

  /// Termina una pieza. Lo que sube la barra.
  void finishStep() {
    _done += 1;
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

  /// Se acabó.
  ///
  /// [ok] es si salió lo que se pedía; [failure], solo cuando no se pudo ni
  /// lanzar el motor. Son dos cosas distintas: que LaTeX no compile es un
  /// resultado, y que el proceso no arranque no lo es.
  void finish({bool ok = true, Object? failure}) {
    _running = false;
    _ok = ok && failure == null;
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
