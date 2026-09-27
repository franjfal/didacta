/// Qué versión es el motor, frente a la de la aplicación. En Ajustes →
/// Herramientas, debajo de dónde está.
library;

import 'package:flutter/material.dart';

import '../data/engine_pin.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class EngineVersionLine extends StatefulWidget {
  const EngineVersionLine({
    super.key,
    required this.version,
    required this.onPin,
  });

  final EngineVersion version;

  /// Ponerlo en la versión de la aplicación.
  final Future<void> Function() onPin;

  @override
  State<EngineVersionLine> createState() => _EngineVersionLineState();
}

class _EngineVersionLineState extends State<EngineVersionLine> {
  bool _busy = false;
  String? _problem;

  Future<void> _pin() async {
    final version = widget.version;
    // Un motor que no instaló Didacta es de alguien: se pregunta antes.
    if (!version.managed) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('engine-pin-confirm'),
          title: Text(tr('¿Poner el motor en la {0}?', [version.app])),
          content: Text(
            tr(
              'La carpeta del motor pasa a la versión publicada de la '
              'aplicación (`git checkout` de su etiqueta). No tiene cambios sin '
              'guardar, así que no se pierde nada; a partir de ahí Didacta lo '
              'mueve sola cada vez que se actualice.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancelar')),
            ),
            FilledButton(
              key: const Key('engine-pin-go'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Ponerlo')),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.onPin();
    } on EnginePinException catch (error) {
      _problem = error.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    final engine = version.engine;
    final String text;
    if (!version.appKnown) {
      text = engine == null
          ? tr('Motor en desarrollo{0}.', [_commit(version)])
          : tr('Motor de la {0}.', [engine]);
    } else if (version.matches) {
      text = tr('Motor de la {0}, la versión de la aplicación.', [engine]);
    } else if (engine == null) {
      text = tr(
        'Motor en desarrollo{0}, no en una versión '
        'publicada; la aplicación es la {1}.',
        [_commit(version), version.app],
      );
    } else {
      text = tr('Motor de la {0}; la aplicación es la {1}.', [
        engine,
        version.app,
      ]);
    }
    final problem = _problem ?? version.problem;
    return Column(
      key: const Key('engine-version'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              version.matches ? Icons.verified_outlined : Icons.info_outline,
              size: 15,
              color: version.matches
                  ? context.palette.accentDark
                  : context.palette.muted,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
            if (version.canPin)
              TextButton(
                key: const Key('engine-pin'),
                onPressed: _busy ? null : _pin,
                child: Text(
                  _busy
                      ? tr('Poniéndolo…')
                      : tr('Poner el de la {0}', [version.app]),
                ),
              ),
          ],
        ),
        if (!version.matches && version.appKnown && version.blocked != null)
          Padding(
            padding: const EdgeInsets.only(left: 21, top: 2),
            child: Text(
              tr('No lo muevo: {0}.', [version.blocked]),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
          ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(left: 21, top: 2),
            child: Text(
              problem,
              key: const Key('engine-pin-problem'),
              style: TextStyle(fontSize: 11.5, color: context.palette.ex),
            ),
          ),
      ],
    );
  }

  static String _commit(EngineVersion version) =>
      version.commit == null ? '' : ' (${version.commit})';
}
