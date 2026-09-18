/// Comparar dos versiones de un curso, en palabras de Didacta.
///
/// El diff lo calcula git; lo que hace esta pantalla es **enseñarlo en los
/// términos del material**. git contesta `M content/analisis/.../es.tex`, y lo
/// que hace falta leer antes de una clase es «la lección *Conjuntos
/// numerables* cambió en castellano». Un diff en bruto es correcto y no se
/// puede repasar.
///
/// Dos listas y no una: a la izquierda qué cambió, agrupado por lo que es --
/// temas, lecciones, el curso --; a la derecha el diff del fichero que se
/// elija, que es el mismo visor del historial. Entrar al detalle es un clic y
/// no otra pantalla, porque la pregunta «¿y qué cambió exactamente?» llega
/// siempre en la misma frase que la anterior.
library;

import 'package:flutter/material.dart';

import '../data/local_clone.dart';
import '../model/catalogue.dart';
import '../model/course_diff.dart';
import '../model/file_history.dart';
import '../state/session.dart';
import 'diff_view.dart';
import 'theme.dart';

/// Compara dos versiones. [to] nulo es la versión actual.
Future<void> showComparison(
  BuildContext context, {
  required Session session,
  required Course course,
  required String year,
  required Freeze from,
  Freeze? to,
}) => showDialog<void>(
  context: context,
  builder: (context) => CompareDialog(
    session: session,
    course: course,
    year: year,
    from: from,
    to: to,
  ),
);

class CompareDialog extends StatefulWidget {
  const CompareDialog({
    super.key,
    required this.session,
    required this.course,
    required this.year,
    required this.from,
    this.to,
  });

  final Session session;
  final Course course;
  final String year;
  final Freeze from;

  /// Contra qué. Nulo es la versión actual, que es la comparación que más se
  /// pide: «¿qué ha cambiado desde septiembre?».
  final Freeze? to;

  @override
  State<CompareDialog> createState() => _CompareDialogState();
}

class _CompareDialogState extends State<CompareDialog> {
  CourseDiff? _diff;
  Object? _problem;
  CourseChange? _chosen;
  FileDiff? _file;
  bool _loadingFile = false;

  String? get _repo => widget.from.repo.isEmpty ? null : widget.from.repo;

  /// El commit de la izquierda y el de la derecha.
  String get _left => widget.from.commit;
  String get _right => widget.to?.commit ?? 'HEAD';

  String get _rightName => widget.to?.name ?? 'la versión actual';

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    final service = widget.session.frozenIn(_repo);
    if (service == null) {
      setState(() => _problem = 'Esto necesita el clon del repositorio.');
      return;
    }
    try {
      // El commit puede no estar en un clon shallow: abrir la congelación es
      // lo que lo trae, y comparar necesita las dos puntas.
      await service.open(widget.from);
      final other = widget.to;
      if (other != null) await service.open(other);
      final found = await service.compare(
        from: _left,
        to: _right,
        course: widget.course.id,
        year: widget.year,
      );
      if (!mounted) return;
      setState(() => _diff = found);
    } catch (thrown) {
      if (!mounted) return;
      setState(() => _problem = thrown);
    }
  }

  Future<void> _openFile(CourseChange change) async {
    setState(() {
      _chosen = change;
      _file = null;
      _loadingFile = true;
    });
    final service = widget.session.frozenIn(_repo);
    if (service == null) return;
    try {
      final diff = await service.diffOf(
        from: _left,
        to: _right,
        path: change.path,
        context: LocalClone.wholeFile,
      );
      if (!mounted) return;
      setState(() {
        _file = diff;
        _loadingFile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diff;
    return AlertDialog(
      title: Text('«${widget.from.name}» frente a $_rightName'),
      content: SizedBox(
        width: 1000,
        height: 560,
        child: _problem != null
            ? Center(
                child: Text(
                  '$_problem',
                  style: const TextStyle(fontSize: 12.5, color: didactaTeacher),
                ),
              )
            : diff == null
            ? const Center(child: CircularProgressIndicator())
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 380,
                    child: _Summary(
                      diff: diff,
                      chosen: _chosen,
                      onChoose: _openFile,
                    ),
                  ),
                  const VerticalDivider(width: 1, color: didactaRule),
                  Expanded(
                    child: _chosen == null
                        ? const DiffPlaceholder(
                            icon: Icons.difference_outlined,
                            text:
                                'Elige una fila para ver exactamente qué '
                                'cambió dentro.',
                          )
                        : _loadingFile
                        ? const Center(child: CircularProgressIndicator())
                        : DiffView(diff: _file),
                  ),
                ],
              ),
      ),
      actions: [
        if (diff != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              diff.summary,
              style: const TextStyle(fontSize: 12, color: didactaMuted),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Lo que cambió, agrupado por lo que es.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.diff,
    required this.chosen,
    required this.onChoose,
  });

  final CourseDiff diff;
  final CourseChange? chosen;
  final void Function(CourseChange change) onChoose;

  @override
  Widget build(BuildContext context) {
    if (diff.isEmpty) {
      return const DiffPlaceholder(
        icon: Icons.check,
        text: 'No hay ninguna diferencia entre las dos versiones.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(right: 12),
      children: [
        if (diff.documents.isNotEmpty) ...[
          const _GroupTitle('Temas del curso'),
          for (final change in diff.documents) _DocumentRow(change: change),
          const SizedBox(height: Space.medium),
        ],
        for (final thing in ChangedThing.values)
          if (diff.of(thing).isNotEmpty) ...[
            _GroupTitle(_names[thing]!),
            for (final change in diff.of(thing))
              _FileRow(
                change: change,
                selected:
                    identical(change, chosen) ||
                    (chosen != null && chosen!.path == change.path),
                onTap: () => onChoose(change),
              ),
            const SizedBox(height: Space.medium),
          ],
      ],
    );
  }

  static const Map<ChangedThing, String> _names = {
    ChangedThing.document: 'Ficheros de temas',
    ChangedThing.lesson: 'Lecciones',
    ChangedThing.course: 'La asignatura y su composición',
    ChangedThing.theme: 'Los bloques de temas',
    ChangedThing.freeze: 'Versiones congeladas',
    ChangedThing.other: 'Lo demás',
  };
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.7,
        fontWeight: FontWeight.w700,
        color: didactaMuted,
      ),
    ),
  );
}

/// Un tema que entró, salió o cambió.
///
/// Fila propia y no una más de ficheros porque **no sale de ninguna ruta**:
/// quitar un tema de un curso es borrar unas líneas de `year.yaml`, y desde la
/// ruta eso solo se ve como «el año cambió».
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.change});

  final DocumentChange change;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color colour, String what) = switch (change.kind) {
      TreeChangeKind.added => (Icons.add, didactaProp, 'tema nuevo'),
      TreeChangeKind.removed => (Icons.remove, didactaTeacher, 'ya no está'),
      _ => (Icons.edit_outlined, didactaThm, 'cambiado'),
    };
    final link = change.linkChanged
        ? change.isLinked
              ? change.wasLinked
                    ? 'ahora está vinculado a otro tema'
                    : 'ahora está vinculado'
              : 'ya no está vinculado'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(icon, size: 14, color: colour),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  change.title.isEmpty ? change.id : change.title,
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  [what, if (link.isNotEmpty) link].join(' · '),
                  style: TextStyle(fontSize: 11, color: colour),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.change,
    required this.selected,
    required this.onTap,
  });

  final CourseChange change;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color colour) = switch (change.kind) {
      TreeChangeKind.added => (Icons.add, didactaProp),
      TreeChangeKind.removed => (Icons.remove, didactaTeacher),
      TreeChangeKind.modified => (Icons.edit_outlined, didactaThm),
      TreeChangeKind.renamed => (Icons.drive_file_move_outlined, didactaEx),
    };
    return InkWell(
      key: Key('compare-${change.path}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.small),
      child: Container(
        color: selected ? didactaSelected : null,
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Icon(icon, size: 14, color: colour),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    change.title,
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    change.isMove && change.from.isNotEmpty
                        ? 'movido desde ${change.from}'
                        : change.detail,
                    style: const TextStyle(fontSize: 11, color: didactaMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
