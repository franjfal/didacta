/// Lo que dice `didacta check --json`: cada cosa que mirar, con dónde está.
library;

import '../l10n/tr.dart';

/// Las comprobaciones que se piden aparte, con cómo se llaman.
const Map<String, String> optionalReviewChecks = {
  'formulas': 'Fórmulas distintas entre idiomas',
  'unused': 'Lecciones sin usar',
  'overfull-lines': 'Líneas que se salen en los apuntes',
  'decimals': 'Coma y punto decimal mezclados',
  'spelling': 'Palabras que el diccionario no conoce',
  'accessible': 'Lo que el PDF accesible no puede leer',
};

class ReviewFinding {
  const ReviewFinding({
    required this.check,
    required this.severity,
    required this.message,
    this.path,
    this.line,
    this.unit,
    this.language,
    this.document,
  });

  factory ReviewFinding.fromJson(Map<String, dynamic> json) => ReviewFinding(
    check: json['check'] as String? ?? '',
    severity: json['severity'] as String? ?? 'warning',
    message: json['message'] as String? ?? '',
    path: json['path'] as String?,
    line: (json['line'] as num?)?.toInt(),
    unit: json['unit'] as String?,
    language: json['language'] as String?,
    document: json['document'] as String?,
  );

  /// Qué comprobación lo encontró: `babel`, `figures`, `structure`…
  final String check;

  /// `error` (no compila), `warning` (compila mal) o `info`.
  final String severity;
  final String message;
  final String? path;
  final int? line;
  final String? unit;
  final String? language;

  /// El documento en el que se ve, `curso@año/documento`, si es de uno.
  final String? document;

  bool get isError => severity == 'error';
}

class ReviewReport {
  const ReviewReport({
    required this.findings,
    this.titles = const {},
    this.checks = const [],
  });

  factory ReviewReport.fromJson(Map<String, dynamic> json) => ReviewReport(
    findings: [
      for (final item in (json['findings'] as List? ?? const []))
        ReviewFinding.fromJson((item as Map).cast<String, dynamic>()),
    ],
    titles: {
      for (final entry in ((json['titles'] as Map?) ?? const {}).entries)
        '${entry.key}': '${entry.value}',
    },
    checks: [
      for (final check in (json['checks'] as List? ?? const [])) '$check',
    ],
  );

  final List<ReviewFinding> findings;

  /// Cómo se llama cada comprobación.
  final Map<String, String> titles;

  /// Las que se hicieron.
  final List<String> checks;

  int get errors => findings.where((f) => f.isError).length;
  int get warnings => findings.where((f) => f.severity == 'warning').length;

  /// Si hay algo que mirar antes de repartir: errores o avisos.
  bool get clean => errors == 0 && warnings == 0;

  /// Por comprobación, en el orden en que llegan.
  Map<String, List<ReviewFinding>> get byCheck {
    final found = <String, List<ReviewFinding>>{};
    for (final finding in findings) {
      (found[finding.check] ??= []).add(finding);
    }
    return found;
  }

  String titleOf(String check) =>
      tr(titles[check] ?? optionalReviewChecks[check] ?? check);
}
