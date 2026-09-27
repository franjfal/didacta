/// Cómo se trabaja: cómo se guarda, cómo se compila, qué paneles se ven y
/// qué interfaz se enseña.
///
/// Era una docena de campos sueltos de la sesión, cada uno con su lectura al
/// arrancar, su setter y su aviso. Aparte porque no dependen de nada --ni del
/// catálogo ni de los repositorios--, solo de las preferencias, y porque **se
/// avisan solos**: plegar el panel de una lección o cambiar la versión que se
/// ojea no tiene por qué redibujar la biblioteca entera. Quien enseña uno de
/// estos ajustes escucha esto; la sesión los sigue ofreciendo con los mismos
/// nombres.
library;

import 'package:flutter/foundation.dart';

import '../data/preferences.dart';

class WorkSettings extends ChangeNotifier {
  WorkSettings(this.preferences);

  final Preferences preferences;

  bool _pushOnCommit = true;
  bool _commitOnSave = true;

  /// Si guardar un fichero lo deja confirmado.
  ///
  /// La pantalla lo pregunta para saber qué decir al terminar y para enseñar
  /// el botón de confirmar solo cuando hace falta.
  bool get commitOnSave => _commitOnSave;

  /// Si lo confirmado se envía solo a GitHub.
  bool get pushOnCommit => _pushOnCommit;

  /// Vuelve a leer las dos de guardar. Las pasarelas se hacen con ellas, así
  /// que se leen cada vez que se abren los repositorios.
  Future<void> readSaving() async {
    _pushOnCommit = await preferences.pushOnCommit();
    _commitOnSave = await preferences.commitOnSave();
  }

  bool _reviewBeforeSave = false;

  /// Si guardar enseña el diff y pide el mensaje antes, en lugar de guardar
  /// con el mensaje propuesto. Ver [Preferences.reviewBeforeSave].
  bool get reviewBeforeSave => _reviewBeforeSave;

  Future<void> setReviewBeforeSave(bool value) async {
    if (_reviewBeforeSave == value) return;
    _reviewBeforeSave = value;
    notifyListeners();
    await preferences.setReviewBeforeSave(value);
  }

  bool _completeInterface = false;

  /// Si la interfaz es la Completa --todo a la vista-- o la Esencial, que es
  /// la de salida. Ver [Preferences.completeInterface].
  bool get completeInterface => _completeInterface;

  Future<void> setCompleteInterface(bool value) async {
    if (_completeInterface == value) return;
    _completeInterface = value;
    notifyListeners();
    await preferences.setCompleteInterface(value);
  }

  int _buildJobs = 0;

  /// Cuántas salidas de un documento se compilan a la vez; 0, las que diga
  /// el motor. Ver [Preferences.buildJobs].
  int get buildJobs => _buildJobs;

  Future<void> setBuildJobs(int value) async {
    final jobs = value.clamp(0, 8);
    if (_buildJobs == jobs) return;
    _buildJobs = jobs;
    notifyListeners();
    await preferences.setBuildJobs(jobs);
  }

  bool _overfullLines = false;

  /// Si se avisa de las líneas que se salen por la derecha en los apuntes.
  /// De las diapositivas que se salen por abajo se avisa siempre. Ver
  /// [Preferences.overfullLines].
  bool get overfullLines => _overfullLines;

  Future<void> setOverfullLines(bool value) async {
    if (_overfullLines == value) return;
    _overfullLines = value;
    notifyListeners();
    await preferences.setOverfullLines(value);
  }

  bool _accessiblePdf = false;

  /// PDF accesibles: los apuntes, las hojas y los exámenes etiquetados, con
  /// su estructura, su idioma y el texto alternativo de las figuras, para
  /// quien los lee con un lector de pantalla. Las diapositivas no: LaTeX
  /// todavía no sabe etiquetar beamer. Ver [Preferences.accessiblePdf].
  bool get accessiblePdf => _accessiblePdf;

  Future<void> setAccessiblePdf(bool value) async {
    if (_accessiblePdf == value) return;
    _accessiblePdf = value;
    notifyListeners();
    await preferences.setAccessiblePdf(value);
  }

  bool _quickBuild = false;

  /// La vista rápida: un documento, compilado desde su panel, en una sola
  /// pasada. Los lotes --un tema, un curso, lo desactualizado-- compilan
  /// siempre enteros: son lo que se reparte. Ver [Preferences.quickBuild].
  bool get quickBuild => _quickBuild;

  Future<void> setQuickBuild(bool value) async {
    if (_quickBuild == value) return;
    _quickBuild = value;
    notifyListeners();
    await preferences.setQuickBuild(value);
  }

  bool _notifyWhenBuilt = false;

  /// Un aviso del sistema al terminar de compilar, para quien se ha ido a
  /// otra ventana mientras tanto. Ver `BuildService`.
  bool get notifyWhenBuilt => _notifyWhenBuilt;

  Future<void> setNotifyWhenBuilt(bool value) async {
    if (_notifyWhenBuilt == value) return;
    _notifyWhenBuilt = value;
    notifyListeners();
    await preferences.setNotifyWhenBuilt(value);
  }

  bool _unitPanel = true;

  /// Si el panel de la derecha de una unidad está desplegado.
  bool get unitPanelVisible => _unitPanel;

  Future<void> setUnitPanelVisible(bool value) async {
    if (_unitPanel == value) return;
    _unitPanel = value;
    notifyListeners();
    await preferences.setUnitPanelVisible(value);
  }

  bool _split = false;

  /// Si los idiomas de una unidad se editan lado a lado.
  bool get splitEditors => _split;

  Future<void> setSplitEditors(bool value) async {
    if (_split == value) return;
    _split = value;
    notifyListeners();
    await preferences.setSplitEditors(value);
  }

  /// La versión que se abre al ojear una unidad desde la biblioteca.
  ///
  /// Una sola y elegida arriba, no una por unidad: quien prepara una clase
  /// está mirando diapositivas toda la tarde, y elegirlo en cada tarjeta
  /// sería el mismo clic dos mil veces.
  String get previewProfile => _previewProfile;
  String _previewProfile = 'slides';

  Future<void> setPreviewProfile(String id) async {
    _previewProfile = id;
    notifyListeners();
    await preferences.setPreviewProfile(id);
  }

  String _clientId = '';

  /// El Client ID de la OAuth App con la que se entra.
  String get githubClientId => _clientId;

  /// Guarda el Client ID de la OAuth App con la que se entra.
  Future<void> setGithubClientId(String value) async {
    _clientId = value.trim();
    await preferences.setGithubClientId(_clientId);
    notifyListeners();
  }

  String _cloneBase = '';

  /// Dónde se clonan los repositorios nuevos.
  String get cloneBase => _cloneBase;

  Future<void> setCloneBase(String path) async {
    _cloneBase = path;
    await preferences.setCloneBase(path);
    notifyListeners();
  }

  /// Todo, al arrancar.
  Future<void> restore() async {
    _clientId = await preferences.githubClientId() ?? '';
    _cloneBase = await preferences.cloneBase() ?? '';
    _previewProfile = await preferences.previewProfile() ?? _previewProfile;
    _unitPanel = await preferences.unitPanelVisible();
    _split = await preferences.splitEditors();
    await restoreWorking();
  }

  /// Lo que decide cómo se guarda y se compila: lo que una prueba de
  /// pantalla necesita leído sin pasar por el arranque.
  Future<void> restoreWorking() async {
    await readSaving();
    _reviewBeforeSave = await preferences.reviewBeforeSave();
    _completeInterface = await preferences.completeInterface();
    _buildJobs = await preferences.buildJobs();
    _overfullLines = await preferences.overfullLines();
    _accessiblePdf = await preferences.accessiblePdf();
    _quickBuild = await preferences.quickBuild();
    _notifyWhenBuilt = await preferences.notifyWhenBuilt();
  }
}
