/// One way to reach the content, whichever path it takes.
///
/// The app has two very different routes to the repository -- the Worker on
/// the web, a token in the OS keychain on desktop -- and exactly one of them
/// is available at a time. Every screen above this layer is written against
/// the interface, so no page contains a branch on which platform it is running
/// on. That is the whole reason this file exists.
///
/// Three things the interface insists on, because they are the rules the
/// platform is built around:
///
/// **Every change is a commit.** [commit] is the only way to write, and it
/// takes a message. There is no `save` that does something less traceable.
///
/// **A write is a compare-and-set.** [commit] takes the `sha` the content was
/// read at. If the file moved on, it fails and says so rather than
/// overwriting whoever got there first.
///
/// **Reading is authorised per path.** A gateway may refuse a read, and the
/// refusal carries a reason -- `access.json` decides, and the interface has to
/// be able to say which rule applied.
library;

import '../model/catalogue.dart';
import 'diagnostics.dart';
import 'local_clone.dart';
import '../l10n/tr.dart';

/// A file as it exists in the repository right now.
class ContentFile {
  const ContentFile({
    required this.path,
    required this.text,
    required this.sha,
  });

  final String path;
  final String text;

  /// The version this text was read at. Required to write it back.
  final String sha;

  ContentFile withText(String next) =>
      ContentFile(path: path, text: next, sha: sha);
}

/// What went wrong, in terms a person can act on.
class ContentException implements Exception {
  const ContentException(
    this.message, {
    this.kind = ContentFailure.other,
    this.cause,
  });

  final String message;
  final ContentFailure kind;

  /// El fallo de debajo, si lo hubo: casi siempre uno de git. Lo lee quien
  /// tiene que explicar qué ha pasado, que con el de git sabe más.
  final Object? cause;

  @override
  String toString() => message;
}

enum ContentFailure {
  /// Nobody is signed in, or the token has gone.
  unauthenticated,

  /// Signed in, but the policy says no. The message names the rule.
  forbidden,

  /// The file moved on since it was read. Re-read; do not retry.
  conflict,

  /// No such file.
  missing,

  /// Nothing is configured to reach the repository at all.
  unconfigured,

  other,
}

/// How the content is being reached, for the interface to show plainly.
enum GatewayKind {
  /// A clone on this machine, driven by git. Works with no network.
  clone,

  /// Nothing configured. Reads of public material may still work.
  none,
}

abstract class ContentGateway {
  const ContentGateway();

  GatewayKind get kind;

  /// A one-line description for the interface: where writes will go, and as
  /// whom. Shown rather than hidden, because "where did my change go" should
  /// never be a mystery.
  String describe();

  /// Whether writing is possible at all. False makes every editor read-only,
  /// which is better than an editor that fails on save.
  bool get canWrite;

  Future<ContentFile> read(String path);

  /// Guarda el fichero. Devuelve el sha nuevo.
  ///
  /// **Si eso es un commit o no, lo decide la configuración.** Con los
  /// commits automáticos puestos --lo normal-- esto escribe y confirma con
  /// [message], y envía si además está puesto enviar. Sin ellos, escribe en
  /// el árbol de trabajo y ya está: el cambio queda pendiente y alguien lo
  /// confirma cuando quiera, con el mensaje que quiera.
  ///
  /// Se llama `save` y no `commit` justamente por eso: un método llamado
  /// `commit` que a veces no hace commit es una trampa para quien lo lea
  /// después.
  Future<String> save({
    required String path,
    required String text,
    required String sha,
    required String message,
  });

  /// Guarda varios ficheros como **un solo cambio**.
  ///
  /// Existe por una operación concreta: mover de bloque las noventa lecciones
  /// que lo nombran. Eso es un cambio --una decisión, una frase que lo
  /// explica-- y hacerlo con noventa llamadas a [save] deja noventa commits
  /// consecutivos que dicen lo mismo, y un historial así deja de servir para
  /// ver qué cambió de verdad.
  ///
  /// La implementación de aquí es la honesta para una pasarela que solo sabe
  /// escribir de uno en uno; la del clon lo cierra en un commit.
  Future<void> saveAll({
    required List<({String path, String text, String sha})> files,
    required String message,
  }) async {
    for (final file in files) {
      await save(
        path: file.path,
        text: file.text,
        sha: file.sha,
        message: message,
      );
    }
  }

  /// Si guardar deja el cambio confirmado o solo escrito.
  ///
  /// Lo pregunta la interfaz para saber qué decir al terminar --«guardado
  /// como un commit» y «guardado, pendiente de confirmar» son dos cosas
  /// distintas-- y para enseñar el botón de confirmar solo cuando hace falta.
  bool get commitsOnSave => true;
}

/// Nothing configured: reads fail with an explanation, writes are impossible.
class UnconfiguredGateway extends ContentGateway {
  const UnconfiguredGateway([this.reason]);

  final String? reason;

  @override
  GatewayKind get kind => GatewayKind.none;

  @override
  bool get canWrite => false;

  @override
  String describe() =>
      reason ?? tr('Sin acceso configurado: no se puede leer ni escribir.');

  @override
  Future<ContentFile> read(String path) async {
    throw ContentException(describe(), kind: ContentFailure.unconfigured);
  }

  @override
  Future<String> save({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async {
    throw ContentException(describe(), kind: ContentFailure.unconfigured);
  }
}

/// Through the Worker. The web path.
class CloneGateway extends ContentGateway {
  const CloneGateway({
    required this.clone,
    required this.token,
    required this.author,
    this.pushOnCommit = true,
    this.commitOnSave = true,
    this.beforeWrite,
    this.onUnsent,
  });

  /// Si guardar confirma el cambio, o solo lo escribe.
  ///
  /// Puesto por defecto: lo que quiere casi todo el mundo es escribir y
  /// olvidarse, y un commit por guardado es un historial fino pero
  /// utilizable. Quien prefiera decidir qué contar --y contarlo una vez al
  /// terminar en vez de treinta veces mientras escribe-- lo apaga y confirma
  /// a mano.
  final bool commitOnSave;

  final LocalClone clone;

  /// Only used to authenticate a push. Never written to disk by this class,
  /// and empty is a working configuration -- see [canWrite].
  final String token;

  final ({String name, String email})? author;

  /// A commit that is not pushed is not traceable by anyone else, so this
  /// defaults to true. It exists as a setting because pushing on every
  /// keystroke-sized commit is the wrong shape for a long editing session on
  /// a bad connection, and the interface can offer "push now" instead.
  final bool pushOnCommit;

  /// Ponerse al día con GitHub antes de escribir.
  ///
  /// Lo pone la sesión, que es quien sabe cuándo se miró la última vez y por
  /// tanto si hace falta volver a preguntar. Aquí es una llamada y nada más:
  /// una pasarela que decidiera cada cuánto consultar la red sería una
  /// política escondida en la capa que solo debería saber escribir ficheros.
  ///
  /// Que falle no impide guardar. Un commit a un clon del propio disco no
  /// necesita red, y perder trabajo para proteger una sincronización que se
  /// hará después sería el peor cambio posible.
  final Future<void> Function()? beforeWrite;

  /// Qué hacer cuando se guardó pero no se pudo enviar.
  ///
  /// Guardar sale bien --lo guardado está a salvo en el clon-- y esto lo
  /// cuenta aparte, donde se ve si un repositorio está al día con GitHub.
  final void Function(UnsentException unsent)? onUnsent;

  @override
  GatewayKind get kind => GatewayKind.clone;

  /// An author is all it takes.
  ///
  /// Deliberately **not** a token: committing to a clone on your own disk
  /// needs no credential at all, and only the push does. Requiring one here
  /// would mean the offline path -- the whole reason this gateway exists --
  /// stopped working the moment nobody had pasted a token.
  @override
  bool get canWrite => author != null;

  /// Whether a commit will actually reach GitHub.
  bool get willPush => pushOnCommit && token.isNotEmpty;

  @override
  String describe() {
    final who = author == null
        ? tr('sin autor: pon un nombre y un correo para poder guardar')
        : tr('como {0} <{1}>', [author!.name, author!.email]);
    final push = token.isEmpty
        ? tr(', sin enviar a GitHub: falta entrar')
        : (pushOnCommit
              ? tr(', enviando cada cambio')
              : tr(', sin enviar al guardar'));
    return tr('Copia en tu ordenador, en {0}, {1}{2}', [
      clone.directory,
      who,
      push,
    ]);
  }

  @override
  Future<ContentFile> read(String path) async {
    try {
      final found = await clone.readFile(path);
      return ContentFile(path: path, text: found.text, sha: found.sha);
    } on CloneException catch (thrown) {
      throw ContentException(
        thrown.message,
        kind: thrown.kind == CloneFailure.missing
            ? ContentFailure.missing
            : ContentFailure.other,
        cause: thrown,
      );
    }
  }

  @override
  bool get commitsOnSave => commitOnSave;

  @override
  Future<String> save({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async {
    // Sin commits automáticos: se escribe y ya. No hace falta autor --no hay
    // nada que firmar-- así que esto funciona incluso sin haber entrado en
    // GitHub, que es el caso de quien está probando la aplicación.
    if (!commitOnSave) {
      try {
        await beforeWrite?.call();
      } catch (caught, trace) {
        Diagnostics.instance.note('content_gateway.save', caught, trace);
        // Ya lo cuenta quien puso la llamada.
      }
      try {
        return await clone.writeFile(path: path, text: text, expectedSha: sha);
      } on CloneException catch (thrown) {
        throw ContentException(
          thrown.message,
          kind: _kindOf(thrown),
          cause: thrown,
        );
      }
    }
    if (author == null) {
      throw ContentException(
        tr(
          'Para guardar en el historial hace falta un autor. Entra en GitHub antes de guardar.',
        ),
        kind: ContentFailure.unauthenticated,
      );
    }
    // Traer antes de modificar. Lo que no se puede traer no para el guardado:
    // se avisa por otro lado, y el trabajo se queda a salvo en el clon.
    try {
      await beforeWrite?.call();
    } catch (caught, trace) {
      Diagnostics.instance.note('content_gateway.save', caught, trace);
      // Ya lo cuenta quien puso la llamada.
    }
    try {
      return await clone.commitFile(
        path: path,
        text: text,
        expectedSha: sha,
        message: message,
        authorName: author!.name,
        authorEmail: author!.email,
        token: token,
        // Not attempted without a token: it would fail, and a failed push
        // reported as a failed save would make an author think their work
        // was lost when it is committed and safe.
        push: willPush,
      );
    } on UnsentException catch (unsent) {
      // Guardado. Lo que falló es el envío, y eso se dice aparte.
      onUnsent?.call(unsent);
      return unsent.sha;
    } on CloneException catch (thrown) {
      throw ContentException(
        thrown.stderr.isEmpty
            ? thrown.message
            : '${thrown.message}\n${thrown.stderr}',
        kind: _kindOf(thrown),
        cause: thrown,
      );
    }
  }

  /// Todos escritos, y un commit al final.
  ///
  /// Escribir primero y confirmar después, y no fichero a fichero, porque el
  /// cambio es uno: si algo falla a mitad, lo escrito se queda en el árbol de
  /// trabajo --visible, y recuperable con `git checkout`-- en vez de dejar
  /// medio historial con commits sueltos que no se sabe si completar o
  /// deshacer.
  @override
  Future<void> saveAll({
    required List<({String path, String text, String sha})> files,
    required String message,
  }) async {
    if (files.isEmpty) return;
    if (commitOnSave && author == null) {
      throw ContentException(
        tr(
          'Para guardar en el historial hace falta un autor. Entra en GitHub antes de guardar.',
        ),
        kind: ContentFailure.unauthenticated,
      );
    }
    try {
      await beforeWrite?.call();
    } catch (caught, trace) {
      Diagnostics.instance.note('content_gateway.saveAll', caught, trace);
      // Ya lo cuenta quien puso la llamada.
    }
    try {
      for (final file in files) {
        await clone.writeFile(
          path: file.path,
          text: file.text,
          expectedSha: file.sha,
        );
      }
      if (!commitOnSave) return;
      await clone.commitPaths(
        paths: [for (final file in files) file.path],
        message: message,
        authorName: author!.name,
        authorEmail: author!.email,
        token: token,
        push: willPush,
      );
    } on UnsentException catch (unsent) {
      // Guardado. Lo que falló es el envío, y eso se dice aparte.
      onUnsent?.call(unsent);
    } on CloneException catch (thrown) {
      throw ContentException(
        thrown.stderr.isEmpty
            ? thrown.message
            : '${thrown.message}\n${thrown.stderr}',
        kind: _kindOf(thrown),
        cause: thrown,
      );
    }
  }

  /// Qué clase de fallo es, para que la pantalla sepa si ofrecer recargar.
  /// Por su tipo y no buscando frases en el mensaje, que era como se hacía:
  /// cambiar una palabra de un mensaje cambiaba qué hacía la pantalla.
  static ContentFailure _kindOf(CloneException thrown) => switch (thrown.kind) {
    CloneFailure.conflict => ContentFailure.conflict,
    CloneFailure.missing => ContentFailure.missing,
    CloneFailure.unauthenticated => ContentFailure.unauthenticated,
    _ => ContentFailure.other,
  };
}

/// Dónde vive cada fichero de una unidad.
///
/// Aquí al lado de las pasarelas porque es el único sitio que sabe cómo una
/// ficha del catálogo se convierte en rutas del repositorio, y equivocarse
/// significa editar el fichero que no era. Las rutas son **relativas a su
/// repositorio**: con varios abiertos, la ruta sola no dice de cuál es, y por
/// eso cada unidad lleva el suyo y cada pantalla pide la pasarela de ese.
extension UnitPaths on Unit {
  String fileFor(String language) => '$path/$language.tex';

  String get metadataPath => '$path/unit.yaml';
}
