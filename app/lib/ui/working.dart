/// Lo que se enseña mientras algo largo está en marcha.
///
/// Clonar un repositorio, descargar el motor o instalar una herramienta son
/// minutos, y hasta ahora esto era un círculo girando al lado de una línea
/// que no cambiaba. Un círculo gira igual con la aplicación colgada, así que
/// no dice nada; lo que sí lo dice es que la línea se mueva.
///
/// Tres cosas, de arriba abajo:
///
/// * **qué se está haciendo**, en palabras de Didacta: «Clonando
///   didacta/curso…». No se pisa con lo que escribe git, que empieza por
///   «Cloning into '.'...» y ahí ya no se sabe ni qué repositorio es;
/// * **una barra**, cuando git dice por qué porcentaje va --casi todo el rato
///   al clonar--, con la fase y lo que se lleva bajado y a qué velocidad;
/// * **cuánto lleva**, a partir de unos segundos. Es lo que queda cuando git
///   se calla un rato, que pasa: GitHub preparando el paquete, un disco lento
///   escribiendo los ficheros.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../model/git_progress.dart';
import 'theme.dart';

class Working extends StatefulWidget {
  const Working({super.key, this.step = '', this.line = ''});

  /// Qué se está haciendo, en nuestras palabras. Vacío si solo hay [line].
  final String step;

  /// Lo último que ha escrito la herramienta, tal cual.
  final String line;

  @override
  State<Working> createState() => _WorkingState();
}

class _WorkingState extends State<Working> {
  /// Cuántos segundos lleva. Vuelve a cero con cada paso: al clonar tres
  /// repositorios lo que interesa es cuánto lleva este, no los tres.
  ///
  /// Contados con el propio temporizador y no restando horas: para un reloj
  /// de segundos da lo mismo, y así en las pruebas avanza con el tiempo de
  /// mentira, que `DateTime.now()` no ve.
  int _seconds = 0;
  Timer? _tick;

  /// Por debajo de esto no se enseña: una instalación de dos segundos no
  /// necesita un reloj, y un «0:00» que aparece y desaparece es ruido.
  static const int _quiet = 3;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds += 1);
    });
  }

  @override
  void didUpdateWidget(Working old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) _seconds = 0;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final line = widget.line.trim();
    final progress = GitProgress.parse(line);

    // Sin paso, la línea hace de título: es lo que pasaba en todas partes
    // antes de esto, y lo que sigue pasando al instalar LaTeX o Python.
    final headline = step.isNotEmpty ? step : (progress?.summary ?? line);
    final detail = step.isEmpty ? '' : (progress?.summary ?? line);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: didactaInk,
                ),
              ),
            ),
            if (_seconds >= _quiet) ...[
              const SizedBox(width: 10),
              Text(
                _clock(Duration(seconds: _seconds)),
                key: const Key('working-elapsed'),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: didactaMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                key: const Key('working-bar'),
                value: progress.fraction,
                minHeight: 4,
                backgroundColor: didactaRule,
              ),
            ),
          ),
        ],
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: didactaMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// «0:42», «12:05», «1:02:33».
String _clock(Duration elapsed) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60);
  final seconds = elapsed.inSeconds.remainder(60);
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}
