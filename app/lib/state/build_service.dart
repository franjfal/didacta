/// Compilar: la cola de compilaciones, compilar documentos en tanda y lo que
/// hay compilado.
///
/// Era una parte de la sesión. Aparte porque tiene su propio estado --lo que
/// espera en la cola, si se ha pedido parar, qué hay ya compilado-- y de la
/// sesión solo necesita lo que cualquier pantalla le pide: el motor de cada
/// repositorio, el catálogo y el registro de compilar. La sesión la sigue
/// ofreciendo con los mismos nombres.
///
/// **Avisa sola**, no por la sesión: que empiece o acabe una compilación, o
/// que cambie lo compilado, le importa a la tira de abajo, a los botones de
/// compilar y a las marcas de «compilado» de la biblioteca, no a todas las
/// pantallas. Quien enseña algo de esto la escucha a ella.
library;

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../data/diagnostics.dart';
import '../data/compiler.dart';
import '../model/notification.dart';
import 'build_console.dart';

import 'session.dart';
import '../l10n/tr.dart';

class BuildService extends ChangeNotifier {
  BuildService(this.session);

  final Session session;

  /// Qué hay compilado, por unidad.
  ///
  /// En la sesión y no en la pantalla porque la pregunta la hace la
  /// biblioteca --¿cuáles puedo ojear?-- y la respuesta vale para toda la
  /// aplicación: compilar una unidad la cambia, y la lista tiene que
  /// enterarse sin volver a preguntarle al motor por las dos mil.
  Map<String, List<ExistingOutput>> get built => _built;
  Map<String, List<ExistingOutput>> _built = const {};

  /// Si ya se ha preguntado. Distinto de «no hay nada compilado».
  bool get builtKnown => _builtKnown;
  bool _builtKnown = false;

  /// Lo compilado que se sabía deja de valer al entrar o salir de una
  /// congelación: los atajos de ver el PDF tienen que decir lo que hay en el
  /// árbol que se está mirando. Se vuelve a preguntar cuando alguien lo
  /// necesite, como la primera vez.
  void forget() {
    _built = const {};
    _builtKnown = false;
  }

  /// Para un test: lo compilado, sin motor que lo diga.
  void setForTest(Map<String, List<ExistingOutput>> built) {
    _built = built;
    _builtKnown = true;
    notifyListeners();
  }

  /// La última compilación encolada: la siguiente espera a que acabe.
  Future<void> _buildTail = Future.value();
  int _queued = 0;
  bool _stopping = false;

  /// Cada «Detener» es una generación nueva: lo que estaba esperando en la
  /// cola cuando se pulsó ya no se compila.
  int _stopGeneration = 0;

  /// Cuántas compilaciones esperan a que acabe la que está en marcha.
  int get queued => _queued;

  /// Si se ha pedido parar. Quien compila lo mira al fallar --un error
  /// después de «Detener» no es un fallo-- y un lote, entre pieza y pieza.
  bool get stopping => _stopping;

  /// Compila [job] cuando acaben las compilaciones anteriores.
  ///
  /// Una detrás de otra y no a la vez: dos compilaciones a la vez se pisan la
  /// consola --que es una-- y, si son del mismo documento, la carpeta de
  /// salida. Lo que se pulsa mientras otra compila espera su turno, y el
  /// indicador de abajo dice cuántas hay esperando.
  ///
  /// [job] recibe la consola ya empezada con [title] y [total]. Si lanza
  /// después de «Detener», no es un error: se da por detenida y devuelve
  /// null. Lo que se había encolado y se detuvo antes de empezar, también.
  Future<T?> run<T>(
    String title,
    Future<T> Function(BuildConsole console) job, {
    int total = 0,
  }) {
    final generation = _stopGeneration;
    _queued += 1;
    notifyListeners();
    final done = Completer<T?>();
    _buildTail = _buildTail.then((_) async {
      _queued -= 1;
      if (generation != _stopGeneration) {
        notifyListeners();
        done.complete(null);
        return;
      }
      _stopping = false;
      session.buildConsole.start(title, total: total);
      notifyListeners();
      try {
        final result = await job(session.buildConsole);
        if (session.buildConsole.running) {
          session.buildConsole.finish(ok: !_stopping, stopped: _stopping);
        }
        done.complete(_stopping ? null : result);
      } catch (error, stack) {
        if (_stopping) {
          if (session.buildConsole.running) {
            session.buildConsole.finish(stopped: true);
          }
          done.complete(null);
        } else {
          if (session.buildConsole.running) {
            session.buildConsole.finish(failure: error);
          }
          done.completeError(error, stack);
        }
      } finally {
        _stopping = false;
        notifyListeners();
        _tellIfAway();
      }
    });
    return done.future;
  }

  /// Si se ha pedido, un aviso del sistema al terminar.
  ///
  /// Solo con Didacta detrás de otra ventana: es para quien se ha ido a
  /// hacer otra cosa mientras compila un curso entero, y con la aplicación
  /// delante el resultado ya está en la pantalla.
  void _tellIfAway() {
    if (!session.notifyWhenBuilt) return;
    final notifier = session.notifier;
    if (!notifier.supported || notifier.appInFront) return;
    final console = session.buildConsole;
    final notice = buildNotice(
      what: console.title,
      ok: console.ok,
      stopped: console.stopped,
      summary: console.summary,
    );
    if (notice == null) return;
    unawaited(notifier.show(title: notice.title, body: notice.body));
  }

  /// «Detener»: para lo que se está compilando y vacía la cola.
  Future<void> stop() async {
    if (!session.buildConsole.running && _queued == 0) return;
    _stopGeneration += 1;
    _stopping = session.buildConsole.running;
    notifyListeners();
    // En todos los repositorios: el motor que compila puede ser de
    // cualquiera, y los procesos se paran por lo que son, no por quién los
    // lanzó.
    final compilers = LinkedHashSet<Compiler>.identity()
      ..addAll(
        [
          session.liveCompiler(),
          for (final repo in session.openedWorkspace.repos)
            session.compiler(repo: repo.id),
        ].whereType<Compiler>(),
      );
    for (final compiler in compilers) {
      try {
        await compiler.stopCompiling();
      } catch (caught, trace) {
        Diagnostics.instance.note('session.stopBuilds', caught, trace);
        // Si uno no se deja parar, los demás sí.
      }
    }
  }

  /// Compila varios documentos, todas sus versiones, contándolo por el
  /// camino.
  ///
  /// Un documento a la vez y no todos de golpe: LaTeX come un núcleo entero y
  /// lanzar ocho a la vez no acaba antes, solo deja el ordenador inservible
  /// mientras tanto. El orden es el de la lista, que es el orden en que se
  /// dan, así que lo primero que se compila es lo primero que se busca.
  ///
  /// Devuelve cuántos documentos salieron enteros. No lanza: un documento que
  /// no compila es un resultado --sale en el registro con su error-- y parar
  /// el lote por él dejaría los demás sin hacer. Al acabar, el resumen dice
  /// cuántos salieron bien y cuántos no; detenido, cuántos se hicieron.
  ///
  /// [languages] son los idiomas en los que compilar. Vacío es «el suyo», que
  /// es lo que hace el motor por su cuenta y lo que se quiere casi siempre:
  /// quien compila un tema para la clase del jueves lo quiere en el idioma en
  /// el que va a darla, no en los tres.
  ///
  /// Las versiones, las que declara cada documento --las marcadas por el
  /// motor--; [everyVersion], todas las que admite. Antes eran siempre todas:
  /// siete salidas por tema cuando se quería una.
  ///
  /// Con [only], de cada documento solo esas salidas --versión e idioma--: es
  /// «Compilar lo desactualizado», que rehace lo que ha cambiado y deja lo
  /// demás como está.
  Future<int> buildDocuments(
    List<({String repo, String course, String year, String id, String title})>
    documents, {
    required String title,
    List<String> languages = const [],
    bool everyVersion = false,
    Map<String, List<({String profile, String language})>>? only,
  }) async {
    final ok = await run(title, total: documents.length, (console) async {
      var ok = 0;
      var failed = 0;
      for (final document in documents) {
        if (_stopping) break;
        final compiler = session.compiler(repo: document.repo);
        final reference = '${document.course}@${document.year}/${document.id}';
        console.startStep(document.title);
        if (compiler == null) {
          console.add('--- sin motor para $reference');
          failed += 1;
          console.finishStep();
          continue;
        }
        try {
          final pairs = only?[document.id];
          final List<CompileOutput> results;
          if (pairs != null) {
            // Por idioma: cada llamada compila sus versiones × sus idiomas,
            // y juntar dos idiomas compilaría también lo que no está viejo.
            results = [];
            for (final language in {for (final pair in pairs) pair.language}) {
              if (_stopping) break;
              results.addAll(
                await compiler.compileDocument(
                  document: reference,
                  profiles: [
                    for (final pair in pairs)
                      if (pair.language == language) pair.profile,
                  ],
                  languages: [language],
                  onOutput: console.add,
                ),
              );
            }
          } else {
            final profiles = await compiler.documentProfiles(reference);
            final own = [
              for (final profile in profiles)
                if (profile.byDefault) profile.id,
            ];
            results = await compiler.compileDocument(
              document: reference,
              profiles: everyVersion || own.isEmpty
                  ? [for (final profile in profiles) profile.id]
                  : own,
              languages: languages,
              onOutput: console.add,
            );
          }
          if (_stopping) break;
          if (results.isNotEmpty && results.every((result) => result.ok)) {
            ok += 1;
          } else {
            failed += 1;
            // Los errores, guardados con el documento: en el registro de un
            // curso entero quedan enterrados, y en la consola salen aparte
            // con a dónde llevan.
            for (final result in results) {
              if (result.ok) continue;
              console.addProblems(
                '${document.title} · ${result.profile} · ${result.language}',
                result.errorDiagnostics,
              );
            }
          }
          // Lo que compila pero no cabe: una diapositiva cortada no la ve
          // nadie hasta que se proyecta.
          for (final result in results) {
            if (!result.ok) continue;
            console.addProblems(
              '${document.title} · ${result.profile} · ${result.language}',
              result.overflowDiagnostics,
            );
          }
        } catch (error) {
          if (_stopping) break;
          console.add('--- $reference: $error');
          console.addProblems(document.title, [
            CompileDiagnostic(severity: 'error', message: '$error'),
          ]);
          failed += 1;
        }
        console.finishStep();
      }
      final done = ok + failed;
      console.finish(
        ok: failed == 0 && !_stopping,
        stopped: _stopping,
        summary: _stopping
            ? tr('Detenida: {0} de {1} hechos', [done, documents.length])
            : failed == 0
            ? tr('{0}, ninguno con errores', [
                ok == 1 ? tr('1 bien') : tr('{0} bien', [ok]),
              ])
            : tr('{0} bien, {1} con errores', [ok, failed]),
      );
      return ok;
    });
    await refreshBuilt();
    return ok ?? 0;
  }

  /// Vuelve a preguntar qué hay compilado.
  ///
  /// Silencioso a propósito: no saberlo quita un atajo, no una pantalla, y
  /// un error aquí no puede impedir listar la biblioteca.
  Future<void> refreshBuilt() async {
    final compiler = session.compiler();
    if (compiler == null) {
      _builtKnown = true;
      return;
    }
    try {
      _built = await compiler.builtOutputs();
    } catch (error) {
      _built = const {};
    }
    _builtKnown = true;
    notifyListeners();
  }
}
