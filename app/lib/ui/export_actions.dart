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

import '../data/file_copy.dart';
import '../model/catalogue.dart';
import '../state/session.dart';
import 'theme.dart';

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
      const SnackBar(content: Text('Aquí no se pueden guardar ficheros.')),
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
    confirmButtonText: 'Guardar',
  );
  if (where == null) return;
  try {
    await copyFile(path, where.path);
    messenger.showSnackBar(
      SnackBar(content: Text('Guardado en ${where.path}.')),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('$error'), backgroundColor: didactaTeacher),
    );
  }
}

/// Saca a una carpeta lo que hay compilado de un documento.
///
/// Sin preguntar nada más que dónde: todas sus versiones y todos sus idiomas.
/// Elegir cuáles es lo que hace el diálogo de exportar un curso, que es donde
/// esa pregunta tiene sentido --treinta documentos-- ; aquí sería un diálogo
/// para responder «sí» a un documento.
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
      const SnackBar(content: Text('No hay motor para este repositorio.')),
    );
    return;
  }

  final destination = await getDirectoryPath(
    confirmButtonText: 'Exportar aquí',
  );
  if (destination == null) return;

  try {
    // Sin idiomas: los que declare la asignatura. Pasar aquí los que la
    // aplicación tenga encendidos exportaría de menos sin decirlo.
    final result = await compiler.exportCourse(
      where: '${course.id}@$year',
      to: destination,
      documents: [document.id],
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.copied.isEmpty
              ? 'No había nada compilado de este documento.'
              : result.missing.isEmpty
              ? '${result.copied.length} fichero(s) exportados a $destination.'
              : '${result.copied.length} exportados; ${result.missing.length} '
                    'sin compilar se han quedado fuera.',
        ),
        duration: const Duration(seconds: 7),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('$error'),
        backgroundColor: didactaTeacher,
        duration: const Duration(seconds: 8),
      ),
    );
  }
}
