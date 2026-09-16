/// Las credenciales de traducción automática.
///
/// Aquí y no en un repositorio: son configuración privada de esta máquina, no
/// contenido. La distinción manda sobre todo lo que hace este fichero. Lo que
/// sí es contenido --a qué idiomas se traduce cada asignatura, la memoria
/// terminológica, las decisiones-- vive en el repositorio y se comparte; una
/// clave de API no sale del llavero del sistema.
///
/// La clave no se vuelve a enseñar después de guardarla. Se dice que hay una y
/// se enseñan sus últimos cuatro caracteres, lo justo para reconocer cuál de
/// las tuyas pusiste; para cambiarla se escribe otra. Un campo que devuelve la
/// clave entera es una clave en una captura de pantalla.
///
/// Y hay un botón de probar, porque una credencial mal puesta no se nota hasta
/// que alguien manda cincuenta unidades a traducir y vuelven todas con un 401.
library;

import 'package:flutter/material.dart';

import '../data/translation_secrets.dart';
import '../data/translator.dart';
import '../data/translator_http.dart';
import '../model/translation.dart';
import 'theme.dart';

class TranslationSection extends StatelessWidget {
  const TranslationSection({super.key, required this.secrets});

  final TranslationSecrets secrets;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Para traducir automáticamente hace falta una cuenta en uno de '
              'los dos. Basta con uno; con los dos puestos, cada asignatura '
              'puede usar el que prefieras.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 6),
            if (!secrets.canStoreSafely)
              const Note(
                'Aquí no hay dónde guardar una clave de forma segura. Usa la '
                'aplicación de escritorio.',
                tone: didactaEx,
              )
            else
              const Note(
                'Se guardan en el llavero del sistema, en esta máquina. No '
                'entran en ningún repositorio, ni en git, ni en las copias '
                'que exportes: son configuración tuya, no contenido.',
              ),
            const SizedBox(height: 10),
            for (final provider in TranslationProvider.values)
              _ProviderCard(provider: provider, secrets: secrets),
          ],
        ),
      ),
    ),
  );
}

class _ProviderCard extends StatefulWidget {
  const _ProviderCard({required this.provider, required this.secrets});

  final TranslationProvider provider;
  final TranslationSecrets secrets;

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  final _key = TextEditingController();
  final _region = TextEditingController();
  final _endpoint = TextEditingController();

  /// Lo que hay guardado. Solo para poder decir que hay algo y enseñar su
  /// pista: el valor de la clave no vuelve a los campos.
  Credentials _stored = const Credentials();
  bool _loaded = false;
  bool _busy = false;
  ProviderCheck? _result;

  bool get _azure => widget.provider == TranslationProvider.azure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stored = await widget.secrets.read(widget.provider);
    if (!mounted) return;
    setState(() {
      _stored = stored;
      // La región y el endpoint sí vuelven: no son secretos, y tener que
      // reescribir `westeurope` cada vez que se cambia la clave es un paso
      // de más que además se equivoca.
      _region.text = stored.region;
      _endpoint.text = stored.endpoint;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _region.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  /// Lo que hay ahora mismo entre lo guardado y lo escrito.
  Credentials get _current => Credentials(
    key: _key.text.trim().isEmpty ? _stored.key : _key.text.trim(),
    region: _region.text.trim(),
    endpoint: _endpoint.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    final id = widget.provider.id;
    final missing = _current.missing(widget.provider);

    return Container(
      key: Key('translation-$id'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: didactaSurface,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.provider.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_loaded && !_stored.isEmpty)
                Text(
                  'guardada ${_stored.hint}',
                  key: Key('translation-$id-stored'),
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('translation-$id-key'),
            controller: _key,
            obscureText: true,
            enabled: widget.secrets.canStoreSafely,
            onChanged: (_) => setState(() => _result = null),
            decoration: InputDecoration(
              labelText: 'Clave de API',
              isDense: true,
              hintText: _stored.isEmpty
                  ? null
                  : 'Hay una guardada. Escribe otra para cambiarla.',
            ),
          ),
          if (_azure) ...[
            const SizedBox(height: 8),
            TextField(
              key: Key('translation-$id-region'),
              controller: _region,
              enabled: widget.secrets.canStoreSafely,
              onChanged: (_) => setState(() => _result = null),
              decoration: const InputDecoration(
                labelText: 'Región',
                hintText: 'westeurope',
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: Key('translation-$id-endpoint'),
            controller: _endpoint,
            enabled: widget.secrets.canStoreSafely,
            onChanged: (_) => setState(() => _result = null),
            decoration: const InputDecoration(
              labelText: 'Endpoint (opcional)',
              hintText: 'Solo si usas un recurso privado',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (_result != null)
                Expanded(
                  child: Text(
                    _result!.message,
                    key: Key('translation-$id-result'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _result!.ok ? didactaAccentDark : didactaEx,
                    ),
                  ),
                )
              else if (missing != null && !_current.isEmpty)
                Expanded(
                  child: Text(
                    missing,
                    style: const TextStyle(fontSize: 11.5, color: didactaEx),
                  ),
                )
              else
                const Spacer(),
              if (!_stored.isEmpty)
                TextButton(
                  key: Key('translation-$id-clear'),
                  onPressed: _busy ? null : _clear,
                  child: const Text('Quitar'),
                ),
              TextButton(
                key: Key('translation-$id-test'),
                onPressed: _busy || !_current.complete(widget.provider)
                    ? null
                    : _test,
                child: const Text('Probar'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                key: Key('translation-$id-save'),
                onPressed:
                    _busy ||
                        !widget.secrets.canStoreSafely ||
                        !_current.complete(widget.provider)
                    ? null
                    : _save,
                child: const Text('Guardar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.secrets.write(widget.provider, _current);
      _key.clear();
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.provider.label}: guardada.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    await widget.secrets.clear(widget.provider);
    _key.clear();
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = null;
    });
    messenger.showSnackBar(
      SnackBar(content: Text('${widget.provider.label}: quitada del llavero.')),
    );
  }

  /// Prueba la credencial que hay delante, sin guardarla.
  ///
  /// Sin guardarla a propósito: probar una clave que acabas de pegar y que
  /// resulta estar mal no tiene por qué dejarla puesta.
  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final translator = translatorFor(widget.provider, _current);
    final result =
        await translator?.check() ??
        const ProviderCheck(ok: false, message: 'Falta algo por rellenar.');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }
}
