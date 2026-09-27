/// Si un PDF se ha quedado viejo, por el contenido de lo que entró en él.
///
/// El motor apunta al compilar, junto a cada PDF, la huella de cada fichero
/// que LaTeX leyó (ver `engine/didacta/inputs.py`). Esto lo lee con las mismas
/// reglas, para la pestaña del PDF: las fechas se rompen con un `git pull`, que
/// las pone al día aunque el texto sea el mismo.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'diagnostics.dart';

/// Junto al PDF, con el mismo nombre.
const String inputsSuffix = '.didacta-inputs.json';

/// Si algo de lo que entró en [pdf] ha cambiado; null si no se apuntó, y
/// entonces quien pregunta decide por las fechas.
Future<bool?> staleByInputs(String pdf) async {
  final Map<String, dynamic> data;
  final record = File('$pdf$inputsSuffix');
  // Sin registro es lo normal en un PDF de antes: se decide por las fechas.
  if (!await record.exists()) return null;
  try {
    data = jsonDecode(await record.readAsString()) as Map<String, dynamic>;
  } catch (caught, trace) {
    Diagnostics.instance.note('pdf_inputs.staleByInputs', caught, trace);
    return null;
  }
  final files = data['files'];
  if (files is! Map) return null;
  // De una sola pasada: no es lo que se reparte, cambie algo o no.
  if (data['quick'] == true) return true;
  for (final entry in files.entries) {
    final path = entry.key as String;
    final known = (entry.value as Map).cast<String, dynamic>();
    final file = File(path);
    final FileStat stat;
    try {
      stat = await file.stat();
    } catch (caught, trace) {
      Diagnostics.instance.note('pdf_inputs.stat', caught, trace);
      return true;
    }
    if (stat.type == FileSystemEntityType.notFound) return true;
    if (stat.size != known['size']) return true;
    // La fecha con holgura: la apunta Python como segundos con decimales, y
    // leída desde aquí puede no coincidir en el último microsegundo.
    final seconds = stat.modified.microsecondsSinceEpoch / 1e6;
    final recorded = (known['mtime'] as num?)?.toDouble() ?? -1;
    if ((seconds - recorded).abs() < 0.001) continue;
    try {
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest != known['sha256']) return true;
    } catch (caught, trace) {
      Diagnostics.instance.note('pdf_inputs.hash', caught, trace);
      return true;
    }
  }
  final lessons = data['lessons'];
  if (lessons is Map) {
    for (final entry in lessons.entries) {
      final directory = Directory(entry.key as String);
      final names = <String>[];
      try {
        await for (final item in directory.list()) {
          final name = item.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
          if (item is File && name.endsWith('.tex')) names.add(name);
        }
      } catch (caught, trace) {
        Diagnostics.instance.note('pdf_inputs.lessons', caught, trace);
        return true;
      }
      names.sort();
      final before = [for (final name in entry.value as List) '$name'];
      if (names.join('\n') != before.join('\n')) return true;
    }
  }
  return false;
}
