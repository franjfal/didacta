/// Lo que se ve de las actualizaciones: una tarjeta en Ajustes y un aviso.
///
/// Con la misma regla que el resto de Didacta: **no se molesta a nadie sin
/// motivo.** Si no hay versión nueva, la tarjeta dice la versión instalada y
/// poco más; el aviso solo aparece cuando de verdad hay algo que instalar, y
/// se puede dejar para luego sin que vuelva a saltar en la misma sesión.
///
/// Y sin jerga. Aquí no salen ni «SHA-256», ni «asset», ni «manifiesto»: eso
/// es de cómo está hecho, no de lo que alguien tiene que decidir. Lo único
/// que hay que decidir es si se actualiza ahora o luego.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/update_service.dart';
import 'theme.dart';

/// La tarjeta de Ajustes → Actualizaciones.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateService>();
    final info = updates.info;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact(label: 'Versión instalada', value: info.describe),
              _Fact(
                label: 'Última comprobación',
                value: _when(updates.lastCheck),
              ),
              const SizedBox(height: 12),

              // Cómo fue la anterior, si hubo una. Lo primero, porque es lo
              // único de esta tarjeta que responde a algo que ya pasó.
              if (updates.outcome != null) ...[
                _Outcome(
                  outcome: updates.outcome!,
                  onDismiss: updates.dismissOutcome,
                ),
                const SizedBox(height: 10),
              ],

              if (updates.hasUpdate) ...[
                Note(
                  'Hay una versión nueva de Didacta: '
                  '${updates.newVersion}.',
                  tone: didactaAccentDark,
                ),
                const SizedBox(height: 10),
              ],

              if (updates.stage == UpdateStage.upToDate && !updates.hasUpdate)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Estás al día.',
                    style: TextStyle(fontSize: 12.5, color: didactaMuted),
                  ),
                ),

              if (updates.problem != null) ...[
                Note('${updates.problem}', tone: didactaTeacher),
                const SizedBox(height: 10),
              ],

              // El motivo por el que aquí no se puede instalar sola, cuando
              // lo hay: un AppImage que no lo es, o una web. Se dice antes de
              // que alguien pulse y no después.
              if (updates.cannotInstallReason != null) ...[
                Note(updates.cannotInstallReason!),
                const SizedBox(height: 10),
              ],

              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const Key('check-for-updates'),
                    onPressed: updates.stage == UpdateStage.checking
                        ? null
                        : () => updates.checkForUpdates(),
                    icon: updates.stage == UpdateStage.checking
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(
                      updates.stage == UpdateStage.checking
                          ? 'Comprobando…'
                          : 'Buscar actualizaciones',
                    ),
                  ),
                  if (updates.hasUpdate && updates.canInstall)
                    FilledButton.icon(
                      key: const Key('install-update'),
                      icon: const Icon(Icons.download, size: 16),
                      label: Text('Actualizar a ${updates.newVersion}'),
                      onPressed: () => showUpdateDialog(context),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime? value) {
    if (value == null) return 'Todavía no se ha comprobado';
    final now = DateTime.now();
    final days = now.difference(value).inDays;
    final stamp =
        '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
    if (days <= 0) return 'Hoy';
    if (days == 1) return 'Ayer';
    return '$stamp (hace $days días)';
  }
}

/// Lo que pasó con la actualización anterior.
///
/// Que saliera bien se dice una vez y se puede cerrar; que saliera mal hay
/// que decirlo con lo que hay que hacer, porque alguien puede estar creyendo
/// que tiene una versión que no tiene.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.outcome, required this.onDismiss});

  final UpdateOutcome outcome;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: outcome.succeeded
            ? Note(
                'Didacta se ha actualizado a la ${outcome.installed}.',
                tone: didactaAccentDark,
              )
            : Note(
                'La actualización a la ${outcome.installed} no se completó: '
                'sigues con la ${outcome.running}, que funciona igual que '
                'antes. Vuelve a intentarlo, y si sigue sin salir, descarga '
                'el instalador.',
                tone: didactaTeacher,
              ),
      ),
      InkResponse(
        key: const Key('dismiss-update-outcome'),
        onTap: onDismiss,
        radius: 16,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.close, size: 15, color: didactaMuted),
        ),
      ),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: didactaMuted),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    ),
  );
}

/// El aviso de que hay una versión nueva.
///
/// Se abre desde Ajustes y también solo, cuando la comprobación de fondo
/// encuentra algo. No se puede cerrar tocando fuera mientras descarga: irse a
/// mitad de una descarga y no saber si sigue o no es peor que esperar.
Future<void> showUpdateDialog(BuildContext context) {
  final updates = context.read<UpdateService>();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _UpdateDialog(),
  ).whenComplete(() {
    // Si se cierra con algo descargado y sin instalar, se tira: dejarlo
    // ocupando disco a la espera de una decisión que ya se tomó no ayuda.
    if (updates.stage == UpdateStage.ready) updates.later();
  });
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateService>();
    final published = updates.manifest;

    if (published == null || !updates.hasUpdate) {
      return AlertDialog(
        title: const Text('Didacta está al día'),
        content: Text('Tienes la versión ${updates.info.version}.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    }

    final downloading = updates.stage == UpdateStage.downloading;
    final ready = updates.stage == UpdateStage.ready;
    final installing = updates.stage == UpdateStage.installing;
    final asset = updates.asset;

    return AlertDialog(
      title: const Text('Hay una versión nueva de Didacta'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Fact(
              label: 'Versión instalada',
              value: updates.info.version.toString(),
            ),
            _Fact(label: 'Nueva versión', value: '${updates.newVersion}'),
            if (asset != null && asset.size > 0)
              _Fact(label: 'Descarga', value: _size(asset.size)),
            const SizedBox(height: 14),

            if (published.releaseNotes.trim().isNotEmpty) ...[
              const Text(
                'Novedades',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: _ReleaseNotes(text: published.releaseNotes),
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (downloading) ...[
              LinearProgressIndicator(value: updates.progress?.fraction),
              const SizedBox(height: 6),
              Text(
                _progressLabel(updates),
                style: const TextStyle(fontSize: 12, color: didactaMuted),
              ),
            ],

            if (ready)
              const Note(
                'Ya está descargada y comprobada. Al continuar, Didacta se '
                'cerrará un momento y volverá a abrirse con la versión nueva.',
                tone: didactaAccentDark,
              ),

            if (installing)
              const Note(
                'Cerrando Didacta para instalar la versión nueva…',
                tone: didactaAccentDark,
              ),

            if (updates.problem != null) ...[
              const SizedBox(height: 8),
              Note('${updates.problem}', tone: didactaTeacher),
              const SizedBox(height: 4),
              const Text(
                'Tu versión sigue instalada y funciona igual.',
                style: TextStyle(fontSize: 12, color: didactaMuted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (downloading)
          TextButton(
            key: const Key('cancel-update'),
            onPressed: updates.cancel,
            child: const Text('Cancelar'),
          )
        else if (!installing) ...[
          TextButton(
            key: const Key('update-later'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            key: const Key('update-now'),
            onPressed: ready
                ? updates.installUpdate
                : () => updates.downloadUpdate(),
            child: Text(ready ? 'Cerrar e instalar' : 'Actualizar ahora'),
          ),
        ],
      ],
    );
  }

  static String _progressLabel(UpdateService updates) {
    final progress = updates.progress;
    if (progress == null) return 'Descargando…';
    if (progress.total <= 0) return 'Descargando ${_size(progress.received)}…';
    return 'Descargando ${_size(progress.received)} de '
        '${_size(progress.total)}';
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} kB';
    return '$bytes bytes';
  }
}

/// Las notas de versión, que son una lista de viñetas y poco más.
///
/// Sin un renderizador de Markdown: lo que se escribe en el CHANGELOG son
/// líneas que empiezan por `-`, y traer una dependencia entera para pintar
/// viñetas sería pagar mucho por poco. Lo que no reconoce lo enseña tal cual,
/// que es lo peor que puede pasar.
class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in lines) _line(line)],
    );
  }

  Widget _line(String line) {
    final trimmed = line.trim();
    // Un encabezado de sección del CHANGELOG, por si se cuela.
    if (trimmed.startsWith('#')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          trimmed.replaceAll(RegExp(r'^#+\s*'), ''),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('·  ', style: TextStyle(fontSize: 13, height: 1.4)),
            Expanded(
              child: Text(
                trimmed.substring(2),
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(trimmed, style: const TextStyle(fontSize: 13, height: 1.4)),
    );
  }
}

/// El aviso discreto de arriba, cuando la comprobación de fondo encuentra
/// algo y nadie ha ido a Ajustes.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateService>();
    if (!updates.showBanner) return const SizedBox.shrink();
    return Material(
      color: didactaAccentDark.withValues(alpha: 0.10),
      child: InkWell(
        onTap: () => showUpdateDialog(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hay una versión nueva de Didacta (${updates.newVersion}). '
                  'Tienes la ${updates.info.version}.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('open-update-dialog'),
                onPressed: () => showUpdateDialog(context),
                child: const Text('Ver'),
              ),
              // Sin `IconButton` ni `Tooltip`: esta franja vive por encima
              // del Navigator, donde no hay Overlay.
              InkResponse(
                key: const Key('dismiss-update-banner'),
                onTap: updates.dismissBanner,
                radius: 16,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 15, color: didactaMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
