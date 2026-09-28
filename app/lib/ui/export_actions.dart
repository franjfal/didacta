/// Llevarse lo que ya está compilado: guardarlo donde diga quien lo pide.
///
/// Compilar deja los PDF dentro del repositorio, con la forma que el motor
/// necesita para no recompilarlos dos veces. Eso está bien para trabajar y no
/// sirve para repartir: lo que se sube al aula virtual o se manda por correo
/// es un fichero con un nombre que se lee, en la carpeta donde uno lo busca
/// después.
///
/// Aquí viven los dos gestos que hacen eso, juntos porque son el mismo gesto
/// a dos tamaños --un PDF, o todo lo de un documento-- y porque salen de tres
/// pantallas distintas: el visor, el listado de un curso y la lista de
/// asignaturas. Tres copias de esto serían tres sitios donde arreglar el
/// mismo mensaje.
///
/// **Copian, no mueven.** El repositorio se queda como estaba. Y lo que no
/// esté compilado no se compila al vuelo: se dice cuánto faltaba, porque un
/// reparto al que le faltan tres PDF tiene que decirlo y no adivinarse
/// contando ficheros.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/compiler.dart';
import '../data/file_copy.dart';
import '../model/catalogue.dart';
import '../state/session.dart';
import 'problem.dart';
import 'review_panel.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Guarda una copia del PDF que se está mirando.
///
/// Pregunta el nombre y el sitio, y propone el nombre que le puso el motor
/// --«Tema 1 - Apuntes.pdf»--: ya es el nombre bueno, el mismo con el que
/// saldría si se exportara el curso entero, y quien quiera otro lo cambia en
/// el propio diálogo.
Future<void> savePdfCopy(
  BuildContext context, {
  required String path,
  String? suggested,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!canCopyFiles) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Aquí no se pueden guardar ficheros.'))),
    );
    return;
  }
  // El nombre del fichero, con separador de cualquier sistema: esto lo
  // decide el motor y la ruta puede venir de otra máquina.
  final name = suggested ?? path.split(RegExp(r'[/\\]')).last;
  final where = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ],
    confirmButtonText: tr('Guardar'),
  );
  if (where == null) return;
  try {
    await copyFile(path, where.path);
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Guardado en {0}.', [where.path]))),
    );
  } catch (error) {
    showProblemIn(messenger, error);
  }
}

/// Lo que se dice al acabar de exportar: cuánto ha salido, y qué no y por
/// qué. Lo que faltaba por compilar y lo que se ha dejado fuera a propósito
/// son dos cosas distintas y se cuentan aparte.
String exportSummary({
  required int copied,
  required int missing,
  required int withheld,
  required String to,
  String? zip,
}) {
  final parts = [
    copied == 0
        ? tr('No se ha exportado nada.')
        : tr('{0} fichero(s) exportados a {1}.', [copied, to]),
    if (zip != null && copied > 0)
      tr('Y en {0}, todo junto.', [zip.split('/').last]),
    if (missing > 0) tr('{0} sin compilar se han quedado fuera.', [missing]),
    if (withheld > 0)
      tr('{0} con soluciones o del profesor no se han incluido.', [withheld]),
  ];
  return parts.join(' ');
}

/// El nombre del .zip de un curso: «Análisis Matemático III 2025-2026.zip».
///
/// Sin lo que un sistema de ficheros no admite, que es lo único que se quita:
/// las tildes y los espacios se quedan, porque es lo que se lee al subirlo.
String zipNameFor(String courseTitle, String year) {
  final clean = courseTitle
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${clean.isEmpty ? 'curso' : clean} $year.zip';
}

/// Saca a una carpeta lo que hay compilado de un documento.
///
/// Sin preguntar nada más que dónde: todas sus versiones para estudiantes y
/// todos sus idiomas. Elegir cuáles es lo que hace el diálogo de exportar un
/// curso, que es donde esa pregunta tiene sentido --treinta documentos-- ;
/// aquí sería un diálogo para responder «sí» a un documento. Las copias del
/// profesor y las resueltas no salen de un clic: si las hay, el aviso lo dice
/// y ofrece llevárselas también.
Future<void> exportDocument(
  BuildContext context, {
  required Session session,
  required Course course,
  required String year,
  required Document document,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final compiler = session.compiler(repo: document.repo);
  if (compiler == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('No hay motor para este repositorio.'))),
    );
    return;
  }

  // Revisar antes, como al exportar el curso entero.
  final go = await reviewBeforeExport(
    context,
    session,
    repo: document.repo,
    within: ['${course.id}@$year/${document.id}'],
  );
  if (!go || !context.mounted) return;

  // La misma carpeta que al exportar el curso entero: es el mismo sitio.
  final remembered = await session.preferences.exportFolder(course.id);
  final destination = await getDirectoryPath(
    initialDirectory: remembered,
    confirmButtonText: tr('Exportar aquí'),
  );
  if (destination == null) return;
  await session.preferences.setExportFolder(course.id, destination);

  Future<void> export(ExportReach reach) async {
    // Sin idiomas: los que declare la asignatura. Pasar aquí los que la
    // aplicación tenga encendidos exportaría de menos sin decirlo.
    final result = await compiler.exportCourse(
      where: '${course.id}@$year',
      to: destination,
      documents: [document.id],
      reach: reach,
    );
    final nothing = result.copied.isEmpty && result.withheld.isEmpty;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          nothing
              ? tr('No había nada compilado de este documento.')
              : exportSummary(
                  copied: result.copied.length,
                  missing: result.missing.length,
                  withheld: result.withheld.length,
                  to: destination,
                ),
        ),
        duration: const Duration(seconds: 9),
        // Con acción, Flutter lo dejaría puesto hasta que se pulse; este se va
        // solo, a su tiempo.
        persist: false,
        action: result.withheld.isEmpty
            ? null
            : SnackBarAction(
                label: tr('Incluirlas'),
                textColor: messenger.context.palette.teacher,
                onPressed: () => export(ExportReach.teacher).catchError(
                  (Object error) => messenger.showSnackBar(
                    SnackBar(
                      content: Text('$error'),
                      backgroundColor: messenger.context.palette.teacher,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  try {
    await export(ExportReach.students);
  } catch (error) {
    showProblemIn(messenger, error);
  }
}
