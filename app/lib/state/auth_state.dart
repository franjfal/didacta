/// La sesión de GitHub: el token, quién es y si se puede entrar.
///
/// Era una parte de la sesión. Aparte porque tiene reglas propias --cuándo
/// hay sesión, qué hacer si GitHub rechaza la credencial, qué vale sin red--
/// y porque solo necesita el llavero, las preferencias y una forma de
/// preguntar a GitHub. Lo que se hace **con** la sesión --abrir los
/// repositorios, quitar los que esta cuenta no alcanza-- sigue en `Session`,
/// que la ofrece con los mismos nombres.
library;

import 'dart:async';
import 'dart:convert';

import '../data/diagnostics.dart';
import '../data/github.dart';
import '../data/preferences.dart';
import '../data/secrets.dart';
import '../model/github_credential.dart';
import '../l10n/tr.dart';

/// Si hay sesión de GitHub, que es lo que decide si Didacta se abre.
///
/// Tres estados y no un booleano, porque el tercero es real y confundirlo con
/// «no» tiene consecuencias: al arrancar, leer el llavero tarda, y durante ese
/// rato la respuesta no es «no ha entrado» sino **todavía no se sabe**. Con un
/// booleano, cada arranque enseñaría la pantalla de entrar durante un
/// parpadeo antes de abrir la biblioteca.
enum SignInState {
  /// Leyendo el llavero. No se sabe.
  checking,

  /// Hay credencial guardada y GitHub no la ha rechazado.
  ///
  /// Sin red también es esto. Lo que se exige es **haber entrado**, no estar
  /// conectado: un aula sin wifi no puede dejar a nadie sin sus diapositivas,
  /// y el trabajo está en un clon del disco.
  signedIn,

  /// No hay credencial, o GitHub ha dicho que ya no vale.
  signedOut,
}

/// El llavero del sistema no contestó al pedirle el token.
///
/// Aparte de un token que GitHub rechaza porque se arregla de otra forma: no
/// hay que volver a autorizar nada en github.com, hay que conseguir que el
/// sistema deje leer --y guardar-- la credencial.
class KeychainProblem implements Exception {
  const KeychainProblem(this.cause);

  final Object cause;

  @override
  String toString() =>
      tr('No se ha podido leer el llavero del sistema ({0}).', [cause]);
}

class AuthState {
  AuthState({
    required this.tokenStore,
    required this.preferences,
    required this.whoIs,
    required this.onRejected,
    Future<GitHubCredential> Function(GitHubCredential old)? renew,
    this.onRenewed,
    DateTime Function()? now,
  }) : renew = renew ?? _cannotRenew,
       now = now ?? DateTime.now;

  static Future<GitHubCredential> _cannotRenew(GitHubCredential old) =>
      throw GitHubException(tr('No se sabe renovar esta credencial.'));

  /// Pide una credencial nueva con la de renovar de [old]. La de `Session`,
  /// que es la que sustituyen las pruebas: renovar es ir a GitHub.
  final Future<GitHubCredential> Function(GitHubCredential old) renew;

  /// Se ha renovado la credencial: quien tenga el token de antes --las
  /// pasarelas de cada clon-- tiene que coger el nuevo.
  final Future<void> Function()? onRenewed;

  /// La hora, que una prueba adelanta para que caduque sin esperar.
  final DateTime Function() now;

  /// La credencial entera: el token, y si caduca, el de renovar y cuándo.
  /// Null sin sesión. Ver `model/github_credential.dart`.
  GitHubCredential? credential;

  Timer? _renewal;

  final SecretStore tokenStore;
  final Preferences preferences;

  /// Quién tiene un token, según GitHub. La de `Session`, que es la que
  /// sustituyen las pruebas.
  final Future<GitHubUser> Function(String token) whoIs;

  /// GitHub ha dicho, con la aplicación ya abierta, que la credencial no
  /// vale: la sesión se ha cerrado y hay que volver a la puerta.
  final Future<void> Function() onRejected;

  /// El token, leído del llavero. Null sin sesión.
  String? token;

  /// Quién ha entrado en GitHub, si alguien lo ha hecho.
  ///
  /// Puede ser null habiendo sesión: es lo que pasa al abrir sin red con un
  /// token guardado de una versión anterior, que todavía no recordaba el
  /// nombre. Quien decide si se puede usar Didacta es [state], no esto.
  GitHubUser? user;

  /// Si hay sesión de GitHub. Es lo que decide si la aplicación se abre.
  SignInState state = SignInState.checking;

  /// Por qué se cerró la sesión sola, si se cerró.
  ///
  /// Se enseña en la pantalla de entrar. Que la sesión caduque y la
  /// aplicación se limite a pedir la contraseña otra vez, sin decir que antes
  /// había una, es la clase de silencio que hace pensar que algo se ha
  /// perdido.
  Object? problem;

  /// Lee el token del llavero, o nada si el llavero no contesta.
  ///
  /// Sin red de seguridad, un llavero que falla --Linux sin servicio de
  /// secretos, el permiso denegado en el aviso de macOS-- lanzaba en
  /// `start`, que se llama sin esperar: la excepción se la tragaba el
  /// manejador global y la aplicación se quedaba para siempre en la pantalla
  /// de carga. Ahora es «sin sesión», con el motivo para enseñarlo.
  Future<String?> readToken() async {
    try {
      final stored = await tokenStore.read();
      credential = stored == null || stored.isEmpty
          ? null
          : GitHubCredential.decode(stored);
      return credential?.token;
    } catch (error) {
      problem = KeychainProblem(error);
      return null;
    }
  }

  /// El token que hay, en memoria o en el llavero, sin tocar el estado: lo
  /// que usa quien necesita uno para una petición y no ha arrancado nada.
  ///
  /// **Nunca lo que hay en el llavero tal cual**: una credencial de GitHub App
  /// se guarda como JSON, y mandar el JSON como token a GitHub es un 401.
  Future<String?> storedToken() async {
    if (token != null && token!.isNotEmpty) return token;
    final stored = await tokenStore.read();
    if (stored == null || stored.isEmpty) return null;
    return GitHubCredential.decode(stored).token;
  }

  /// Si la credencial caduca pronto, pide una nueva. Devuelve si la cambió.
  ///
  /// Una de GitHub App dura ocho horas: se renueva quince minutos antes, con
  /// el de renovar, sin que nadie vuelva a entrar. Tres salidas:
  ///
  /// * renovada: se guarda y se avisa ([onRenewed]) para que las pasarelas
  ///   cojan el token nuevo;
  /// * GitHub dice que el de renovar ya no vale --seis meses sin abrir
  ///   Didacta, o la App desautorizada en github.com--: se cierra la sesión y
  ///   se dice por qué, como con un token rechazado;
  /// * sin red: se sigue con la que hay y se vuelve a intentar en unos
  ///   minutos. Lo del disco sigue valiendo; enviar esperará.
  Future<bool> renewIfDue() async {
    final current = credential;
    if (current == null || !current.dueAt(now())) {
      _schedule();
      return false;
    }
    if (current.refreshExpiredAt(now())) {
      await _forget(
        GitHubException(
          tr(
            'La sesión de GitHub ha caducado: hace más de seis meses que no se '
            'renovaba. Vuelve a entrar.',
          ),
          status: 401,
        ),
      );
      await onRejected();
      return false;
    }
    try {
      final fresh = await renew(current);
      if (!identical(credential, current)) return false;
      await tokenStore.write(fresh.encode());
      credential = fresh;
      token = fresh.token;
      _schedule();
      return true;
    } on GitHubException catch (rejected) {
      if (!rejected.rejectsCredential) {
        _schedule(retry: true);
        return false;
      }
      await _forget(rejected);
      await onRejected();
      return false;
    } catch (caught, trace) {
      Diagnostics.instance.note('auth_state.renewIfDue', caught, trace);
      _schedule(retry: true);
      return false;
    }
  }

  /// Programa la próxima renovación, o un reintento si esta no pudo ser.
  void _schedule({bool retry = false}) {
    _renewal?.cancel();
    _renewal = null;
    final at = credential?.renewAt();
    if (at == null) return;
    var delay = retry ? const Duration(minutes: 5) : at.difference(now());
    if (delay.isNegative) delay = Duration.zero;
    _renewal = Timer(delay, () async {
      if (await renewIfDue()) await onRenewed?.call();
    });
  }

  /// Deja de renovar: al salir, y cuando la sesión se tira a la basura.
  void dispose() {
    _renewal?.cancel();
    _renewal = null;
  }

  /// Decide si hay sesión, que es lo que decide si Didacta se abre.
  ///
  /// La regla, en una línea: **hay sesión si hay credencial guardada y GitHub
  /// no la ha rechazado.** Los cuatro casos que salen de ahí no son
  /// intercambiables:
  ///
  /// * sin token, no hay sesión. Es la instalación recién puesta;
  /// * con token y GitHub contestando, hay sesión y además se sabe de quién.
  ///   Se apunta, para la próxima vez que no haya red;
  /// * con token y **GitHub diciendo que no vale** --un 401, un token
  ///   revocado desde github.com-- se cierra la sesión aquí y se dice por
  ///   qué. Dejar abierta una sesión que GitHub ya no reconoce sería enseñar
  ///   un candado que no cierra;
  /// * con token y **sin poder preguntar** --sin red-- hay sesión. Lo que se
  ///   exige es haber entrado, y eso ya pasó; lo que no hay ahora es forma de
  ///   confirmarlo, que no es lo mismo. Se usa el nombre apuntado la última
  ///   vez.
  Future<void> resolve() async {
    // Una credencial que ha caducado mientras Didacta estaba cerrada se
    // renueva **antes** de preguntar a GitHub quién es: con el token de
    // ayer, la pregunta sería un 401 y cerraría una sesión que sigue viva.
    if (credential?.dueAt(now()) ?? false) {
      try {
        await renewIfDue().timeout(const Duration(seconds: 6));
      } catch (caught, trace) {
        Diagnostics.instance.note('auth_state.resolve.renew', caught, trace);
      }
      if (state == SignInState.signedOut && token == null) return;
    }
    final current = token;
    if (current == null || current.isEmpty) {
      user = null;
      state = SignInState.signedOut;
      return;
    }
    _schedule();

    if (user == null) {
      // Con quien entró la última vez, sin esperar a GitHub: arrancar
      // esperaba hasta seis segundos a que contestara, en cada arranque y
      // para saber lo que ya estaba apuntado. Se le pregunta después, sin
      // parar a nadie, y si dice que la credencial ya no vale se cierra la
      // sesión entonces.
      final saved = GitHubUser.fromJson(await preferences.githubUser());
      if (saved != null) {
        user = saved;
        state = SignInState.signedIn;
        unawaited(_confirm(current));
        return;
      }
      try {
        // Con tope: sin red, una petición puede tardar lo que tarde el DNS en
        // rendirse, y eso es tiempo con la aplicación en blanco delante de
        // alguien que ya entró. Pasado el tope se sigue con lo apuntado, que
        // es exactamente lo que hay que hacer cuando no se puede preguntar.
        final who = await whoIs(current).timeout(const Duration(seconds: 6));
        user = who;
        await preferences.setGithubUser(jsonEncode(who.toJson()));
        problem = null;
      } on GitHubException catch (rejected) {
        if (rejected.rejectsCredential) {
          await _forget(rejected);
          return;
        }
        // GitHub contestó, pero con algo que no habla de la credencial --un
        // 500 suyo--. No es motivo para echar a nadie.
        user = GitHubUser.fromJson(await preferences.githubUser());
      } catch (caught, trace) {
        Diagnostics.instance.note('auth_state.resolve', caught, trace);
        // Ni siquiera contestó: sin red. Lo que se sabe es lo de la última
        // vez, y basta para firmar los commits.
        user = GitHubUser.fromJson(await preferences.githubUser());
      }
    }
    state = SignInState.signedIn;
  }

  /// Pregunta a GitHub quién es, sin que nadie espere: para poner al día el
  /// nombre apuntado y, sobre todo, para cerrar la sesión si la credencial ya
  /// no vale.
  Future<void> _confirm(String asked) async {
    // Caducada, la pregunta sería un 401 por nada: lo que dice si la sesión
    // vale es renovarla, y eso ya lo intenta [renewIfDue].
    if (credential?.dueAt(now()) ?? false) return;
    try {
      final who = await whoIs(asked).timeout(const Duration(seconds: 20));
      if (token != asked) return;
      user = who;
      await preferences.setGithubUser(jsonEncode(who.toJson()));
      problem = null;
    } on GitHubException catch (rejected) {
      if (!rejected.rejectsCredential || token != asked) return;
      await _forget(rejected);
      await onRejected();
    } catch (caught, trace) {
      Diagnostics.instance.note('auth_state.confirm', caught, trace);
      // Sin red, o sin contestar a tiempo: sigue valiendo lo de la última
      // vez, que basta para firmar los commits.
    }
  }

  /// Cierra la sesión porque GitHub ha rechazado la credencial, y lo apunta.
  Future<void> _forget(Object why) async {
    dispose();
    await tokenStore.clear();
    await preferences.setGithubUser(null);
    credential = null;
    token = null;
    user = null;
    problem = why;
    state = SignInState.signedOut;
  }

  /// Entra con [token]. Quién es se pregunta **aquí y sin red de seguridad**:
  /// entrar es el único momento en el que se puede exigir que GitHub
  /// conteste, y un token que no se ha podido comprobar ni una vez no es una
  /// sesión. Lo que se guarda es el resultado de esa comprobación, y es lo
  /// que permite que los arranques siguientes valgan sin red.
  Future<void> signIn(String token) =>
      signInWith(GitHubCredential(token: token));

  /// Entra con una credencial entera: la de una GitHub App trae el de
  /// renovar y cuándo caduca, y se guarda con ellos.
  Future<void> signInWith(GitHubCredential fresh) async {
    final who = await whoIs(fresh.token);
    await tokenStore.write(fresh.encode());
    await preferences.setGithubUser(jsonEncode(who.toJson()));
    credential = fresh;
    token = fresh.token;
    user = who;
    state = SignInState.signedIn;
    problem = null;
    _schedule();
  }

  /// Sale. Los clones se quedan: eso lo decide quien llama.
  Future<void> signOut() async {
    dispose();
    await tokenStore.clear();
    await preferences.setGithubUser(null);
    credential = null;
    token = null;
    user = null;
    state = SignInState.signedOut;
    problem = null;
  }
}
