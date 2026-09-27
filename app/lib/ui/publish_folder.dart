/// La carpeta de reparto: exportar a un sitio que se sincroniza solo.
///
/// Mucha gente reparte así: una carpeta de OneDrive, Drive o Nextcloud
/// compartida con los estudiantes, o enlazada desde el aula virtual. Exportar
/// ahí cada semana era elegir la misma carpeta cada vez; con esto, «Publicar»
/// en el curso deja los PDF en `<carpeta>/<asignatura> <año>` y el programa
/// de sincronización hace el resto.
///
/// **Opcional y apagada de salida**, en Ajustes → Guardar y sincronizar. Es
/// una ruta de este ordenador, así que no viaja con las preferencias: en otro
/// la carpeta sincronizada está en otro sitio, o no está.
library;

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Dónde publica «Publicar» un curso: una carpeta por curso, con el nombre
/// que se lee en la lista de la carpeta sincronizada.
String publishTargetFor(String folder, String courseTitle, String year) {
  final clean = courseTitle
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '$folder/${clean.isEmpty ? 'curso' : clean} $year';
}

/// La tarjeta de Ajustes.
class PublishFolderSection extends StatefulWidget {
  const PublishFolderSection({super.key, required this.session});

  final Session session;

  @override
  State<PublishFolderSection> createState() => _PublishFolderSectionState();
}

class _PublishFolderSectionState extends State<PublishFolderSection> {
  String? _folder;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final found = await widget.session.preferences.publishFolder();
    if (mounted) {
      setState(() {
        _folder = found;
        _loaded = true;
      });
    }
  }

  Future<void> _choose() async {
    final chosen = await getDirectoryPath(
      initialDirectory: _folder,
      confirmButtonText: tr('Usar esta carpeta'),
    );
    if (chosen == null) return;
    await widget.session.preferences.setPublishFolder(chosen);
    await _load();
  }

  Future<void> _clear() async {
    await widget.session.preferences.setPublishFolder(null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Una carpeta que sincroniza OneDrive, Drive o Nextcloud, y que '
                  'ven tus estudiantes. Con ella, cada curso académico tiene '
                  '«Publicar» en su «…»: exporta lo del estudiante a una '
                  'carpeta con su nombre dentro de esta, sin preguntar dónde, y '
                  'el programa de sincronización hace el resto.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              Text(
                !_loaded
                    ? tr('Leyendo…')
                    : folder ?? tr('Sin carpeta de reparto.'),
                key: const Key('publish-folder-path'),
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.muted,
                  fontFamily: folder == null ? null : 'monospace',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('publish-folder-choose'),
                    icon: const Icon(Icons.folder_open_outlined, size: 15),
                    label: Text(
                      folder == null
                          ? tr('Elegir la carpeta…')
                          : tr('Cambiarla…'),
                    ),
                    onPressed: _loaded ? _choose : null,
                  ),
                  if (folder != null)
                    TextButton(
                      key: const Key('publish-folder-clear'),
                      onPressed: _clear,
                      child: Text(tr('Dejar de usarla')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
