/// El servidor MCP: encenderlo, apagarlo y ver qué hace.
///
/// MCP es el protocolo por el que un modelo de lenguaje usa herramientas. Con
/// esto encendido, un LLM puede leer las asignaturas, buscar en la biblioteca,
/// escribir una traducción o comprobar que lo que ha escrito compila. Sirve
/// para delegar lo que se hace a mano y no tiene gracia: traducir cincuenta
/// unidades, corregir la misma errata en las cuarenta que la repiten.
///
/// **El proceso es de la aplicación.** Podría lanzarlo el cliente --es lo que
/// hace un servidor MCP por stdio-- pero entonces no habría forma de
/// encenderlo desde Ajustes ni de enseñar qué está haciendo: nadie tendría el
/// otro extremo de la tubería. Así que la aplicación lo lanza sobre HTTP en
/// `127.0.0.1`, con el puerto que elija el sistema, y el cliente se conecta a
/// esa dirección. Cerrar Didacta apaga el servidor, que es exactamente lo que
/// se espera de un interruptor que está en Didacta.
///
/// **Y el diario es lo que lo hace aceptable.** Un servidor que escribe en los
/// ficheros de alguien sin que se pueda ver qué toca es un servidor en el que
/// no hay motivo para confiar. El motor escribe una línea de JSON por llamada
/// en su salida de error; esto la lee y la guarda, y la pantalla la enseña.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/mcp_process.dart';
import '../model/mcp.dart';

/// En qué punto está el servidor.
enum McpState {
  /// Apagado, que es como arranca.
  off,

  /// Lanzado, esperando a que diga por qué puerto escucha.
  starting,

  /// En marcha y contestando.
  running,

  /// No se pudo levantar. El motivo está en [problem].
  failed,
}

class McpService extends ChangeNotifier {
  McpService({required this.openRunner});

  /// Se pide al encender y no se guarda: el motor se configura en Ajustes, y
  /// uno guardado aquí seguiría apuntando al de antes después de cambiarlo.
  final McpRunner Function() openRunner;

  McpState _state = McpState.off;
  McpState get state => _state;

  bool get running => _state == McpState.running;

  String? _url;

  /// Dónde escucha, cuando escucha. Es lo que se pega en la configuración de
  /// un cliente.
  String? get url => _url;

  String? _problem;
  String? get problem => _problem;

  List<McpTool> _tools = const [];

  /// Lo que el servidor sabe hacer.
  ///
  /// Se pregunta al servidor en vez de tenerlo escrito aquí: quien decide qué
  /// herramientas hay es el motor, y una lista de esta parte se quedaría
  /// vieja el día que alguien añada una. Sobrevive a apagarlo, para que la
  /// referencia siga leyéndose con el servidor parado.
  List<McpTool> get tools => _tools;

  final List<McpEvent> _activity = [];

  /// Lo que ha ido haciendo, lo más reciente primero.
  List<McpEvent> get activity => List.unmodifiable(_activity);

  /// Con tope: una sesión larga son miles de llamadas, y guardarlas todas es
  /// una fuga de memoria con forma de registro.
  static const int _keep = 500;

  int get calls => _activity.where((event) => event.isCall).length;

  int get writes => _activity.where((event) => event.writes).length;

  McpSession? _session;
  StreamSubscription<String>? _journal;

  /// Enciende el servidor sobre [repositories].
  ///
  /// Los repositorios llegan ya separados en los que se pueden escribir y los
  /// que no, y esa separación se hace arriba a propósito: es una decisión de
  /// la persona, no algo que este servicio deba deducir de unos permisos de
  /// fichero.
  Future<void> start({required List<McpRepository> repositories}) async {
    if (_state == McpState.starting || _state == McpState.running) return;
    if (repositories.isEmpty) {
      _fail('No hay ningún repositorio abierto que servir.');
      return;
    }

    _state = McpState.starting;
    _problem = null;
    notifyListeners();

    try {
      final session = await openRunner().start(repositories);
      _session = session;
      _url = session.url;
      _journal = session.journal.listen(_onLine, onDone: _onDone);
      _state = McpState.running;
      _note(McpEvent.started(session.url));
      notifyListeners();
      unawaited(_loadTools());
    } catch (error) {
      _fail('$error');
    }
  }

  Future<void> stop() async {
    await _release();
    _url = null;
    if (_state != McpState.failed) _state = McpState.off;
    _note(McpEvent.stopped());
    notifyListeners();
  }

  /// Suelta el proceso sin avisar a nadie.
  ///
  /// Aparte de [stop] porque `dispose` también tiene que hacerlo, y avisar
  /// desde `dispose` es usar un `ChangeNotifier` ya desechado: Flutter lo
  /// para en seco, y el fallo aparece en los sesenta y cinco tests que montan
  /// la aplicación, no aquí.
  Future<void> _release() async {
    final session = _session;
    _session = null;
    await _journal?.cancel();
    _journal = null;
    await session?.stop();
  }

  /// Pregunta al servidor qué sabe hacer.
  Future<void> _loadTools() async {
    final session = _session;
    if (session == null) return;
    try {
      final found = await session.listTools();
      if (found.isEmpty) return;
      _tools = found;
      notifyListeners();
    } catch (_) {
      // No poder listarlas quita la referencia, no el servidor: el modelo las
      // pregunta por su cuenta y sigue funcionando igual.
    }
  }

  void _onLine(String line) {
    final event = McpEvent.parse(line);
    if (event == null) return;
    _note(event);
    notifyListeners();
  }

  void _onDone() {
    // El proceso se ha ido por su cuenta. Decirlo: un servidor que figura
    // encendido y no contesta es peor que uno apagado.
    if (_state == McpState.running) {
      _state = McpState.failed;
      _problem = 'El servidor se detuvo solo.';
      _url = null;
      _note(McpEvent.stopped());
      notifyListeners();
    }
  }

  void _note(McpEvent event) {
    _activity.insert(0, event);
    if (_activity.length > _keep) {
      _activity.removeRange(_keep, _activity.length);
    }
  }

  void _fail(String message) {
    _state = McpState.failed;
    _problem = message;
    _url = null;
    notifyListeners();
  }

  /// Lo que hay que pegar en un cliente MCP para conectarse.
  ///
  /// El de Claude y compatibles, que es el formato que entienden casi todos.
  /// Con el servidor parado no hay puerto, así que no hay nada que pegar y se
  /// dice en vez de enseñar un ejemplo que no funciona.
  String? get clientConfiguration {
    final where = _url;
    if (where == null) return null;
    return const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'didacta': {'type': 'http', 'url': where},
      },
    });
  }

  @override
  void dispose() {
    _state = McpState.off;
    _url = null;
    unawaited(_release());
    super.dispose();
  }
}
