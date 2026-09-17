/// Entrar en GitHub, que es lo que abre Didacta.
///
/// **Sin sesión no hay aplicación.** No es una restricción añadida por encima:
/// es lo que ya era cierto y la interfaz no decía. Didacta trabaja sobre
/// clones de repositorios privados, escribe commits que tienen que salir con
/// el nombre de alguien, y se reparte a quien tiene acceso al repositorio de
/// versiones. Quién puede hacer cada una de esas tres cosas lo dice GitHub, y
/// no hay ninguna que se pueda hacer sin haber entrado.
///
/// Lo que había antes era una aplicación que abría igual, enseñaba una
/// biblioteca vacía y fallaba en el primer commit -- con el agravante de que
/// un clon ya puesto en el disco se podía editar sin que nadie hubiera
/// demostrado ser nadie.
///
/// Dos cosas que conviene dejar dichas:
///
/// **La contraseña se teclea en github.com y en ningún otro sitio.** Es un
/// device flow: Didacta enseña un código, tú lo escribes allí, y lo que
/// vuelve es un token. Esta aplicación no ve nunca una contraseña, y por eso
/// puede pedir que entres sin pedirte que confíes en ella.
///
/// **Sin red también se abre, si ya entraste.** Lo que se exige es haber
/// entrado, no estar conectado. Un aula sin wifi no puede dejar a nadie sin
/// sus diapositivas, y el trabajo está en un clon del disco.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/browser.dart';
import '../data/github.dart';
import '../state/session.dart';
import 'theme.dart';

/// El formulario de entrar: el Client ID y el botón.
///
/// Un widget y no dos copias, porque se usa en dos sitios que no se pueden
/// fundir: la pantalla que tapa la aplicación cuando no hay sesión, y la
/// ficha de Ajustes de quien ya entró y quiere salir o cambiar de cuenta.
class SignInForm extends StatefulWidget {
  const SignInForm({super.key, required this.session, this.onSignedIn});

  final Session session;

  /// Qué hacer después de entrar, si hay algo que hacer.
  final VoidCallback? onSignedIn;

  @override
  State<SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<SignInForm> {
  late final TextEditingController _clientId = TextEditingController(
    text: widget.session.githubClientId,
  );
  bool _working = false;
  Object? _problem;

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final clientId = _clientId.text.trim();
    if (clientId.isEmpty) {
      setState(
        () => _problem =
            'Falta el Client ID de la OAuth App. Créala en GitHub '
            '(Settings → Developer settings → OAuth Apps) con «Enable '
            'Device Flow» marcado, y pega aquí su Client ID.',
      );
      return;
    }
    await widget.session.setGithubClientId(clientId);

    setState(() {
      _working = true;
      _problem = null;
    });
    final auth = GitHubAuth(clientId: clientId);
    try {
      final code = await auth.start();
      if (!mounted) return;

      // El código al portapapeles, y **el navegador no se abre solo**.
      //
      // Se abría, y era lo primero que pasaba: te llevaba a github.com antes
      // de que hubieras visto que hacía falta un código, así que llegabas a
      // una pantalla pidiéndote algo que no sabías que tenías. El código y el
      // enlace tienen que estar delante a la vez, y el salto lo das tú.
      //
      // El *device flow* no se puede saltar --hace falta que GitHub vea a una
      // persona autorizando en github.com, que es justo lo que hace que esta
      // aplicación no toque nunca una contraseña-- pero sí se puede contar en
      // un solo paso en vez de en dos.
      await Clipboard.setData(ClipboardData(text: code.userCode));
      if (!mounted) return;

      final waiting = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DeviceCodeDialog(code: code),
      );
      final token = await auth.waitForToken(code);
      await widget.session.signIn(token);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await waiting;
      widget.onSignedIn?.call();
    } catch (thrown) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
        setState(() => _problem = thrown);
      }
    } finally {
      auth.close();
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Donde no se puede guardar una credencial no se puede entrar, y un botón
    // que no puede funcionar es peor que su ausencia explicada. Es el caso de
    // la web: el «almacenamiento seguro» de un navegador lo lee cualquier
    // script de su origen.
    if (!widget.session.canStoreToken) {
      return const Note(
        'Aquí no se puede guardar una credencial de forma segura, así que no '
        'se puede entrar. Didacta se usa desde la aplicación de escritorio.',
        tone: didactaTeacher,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('github-client-id'),
          controller: _clientId,
          decoration: const InputDecoration(
            labelText: 'Client ID de la OAuth App',
            helperText:
                'GitHub → Settings → Developer settings → OAuth Apps, '
                'con «Enable Device Flow». Es público: no es un '
                'secreto que haya que proteger.',
            helperMaxLines: 3,
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('github-sign-in'),
          onPressed: _working ? null : _signIn,
          icon: _working
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login, size: 16),
          label: Text(_working ? 'Esperando…' : 'Entrar en GitHub'),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 12),
          Note('$_problem', tone: didactaTeacher),
        ],
      ],
    );
  }
}

/// La pantalla que hay en lugar de la aplicación cuando no hay sesión.
///
/// En lugar de, y no encima: no hay router, no hay biblioteca y no hay
/// pestañas detrás. Una aplicación que se pinta entera y pone un velo por
/// delante ha construido igual todo lo que hay debajo, y lo que hay debajo
/// son los ficheros de un repositorio privado.
class SignInGate extends StatelessWidget {
  const SignInGate({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final expired = session.signInProblem;
    return Scaffold(
      backgroundColor: didactaSurface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Didacta',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Entra en GitHub para empezar.',
                  style: TextStyle(fontSize: 14.5, color: didactaMuted),
                ),
                const SizedBox(height: 18),
                // Por qué se pide, y no sólo que se pide. Un muro sin motivo
                // se lee como un trámite; con el motivo se lee como lo que
                // es, que es de dónde salen los permisos.
                const Text(
                  'El material vive en repositorios privados y los cambios se '
                  'guardan como commits con el nombre de quien los hace. '
                  'Quién puede leer cada repositorio y quién puede escribir en '
                  'él lo dice GitHub, así que Didacta no mantiene ninguna otra '
                  'lista: la sesión es el permiso.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
                if (expired != null) ...[
                  const SizedBox(height: 16),
                  Note(
                    'La sesión que había ha dejado de valer: $expired',
                    tone: didactaTeacher,
                  ),
                ],
                const SizedBox(height: 22),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SignInForm(session: session),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'La contraseña se teclea en github.com y en ningún otro '
                  'sitio: Didacta enseña un código, tú lo autorizas allí. '
                  'Una vez dentro, se abre también sin conexión.',
                  style: TextStyle(fontSize: 12, color: didactaMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El código del device flow, mientras se espera.
///
/// **Las dos cosas a la vez**: el código delante y el botón que lleva a
/// GitHub debajo. Antes el navegador se abría primero y el código salía
/// después, así que llegabas a github.com sin saber que te iban a pedir algo
/// y tenías que volver a buscarlo. Un paso, no dos.
class _DeviceCodeDialog extends StatelessWidget {
  const _DeviceCodeDialog({required this.code});

  final DeviceCode code;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Entra en GitHub con este código'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apunta o copia el código, abre GitHub y pégalo allí. Ya está '
            'copiado al portapapeles.',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 14),
          // El código, en grande y en el centro: es lo que hay que llevarse
          // a la otra ventana.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: didactaSurface,
              border: Border.all(color: didactaRule),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: SelectableText(
                code.userCode,
                key: const Key('device-code'),
                style: const TextStyle(
                  fontSize: 30,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Se pega en ${code.verificationUri}',
            style: const TextStyle(fontSize: 11.5, color: didactaMuted),
          ),
          const SizedBox(height: 10),
          const Text(
            'Esta ventana se cierra sola en cuanto lo autorices. Tu '
            'contraseña se teclea en github.com y en ningún otro sitio.',
            style: TextStyle(fontSize: 12, color: didactaMuted, height: 1.4),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('device-copy'),
        onPressed: () => Clipboard.setData(ClipboardData(text: code.userCode)),
        child: const Text('Copiar otra vez'),
      ),
      FilledButton.icon(
        key: const Key('device-open'),
        icon: const Icon(Icons.open_in_new, size: 16),
        onPressed: () => openLink(code.verificationUri),
        label: const Text('Abrir GitHub'),
      ),
    ],
  );
}
