# `api/` — el borde autenticado

Un Worker de Cloudflare. Tres cosas, en este orden, en cada petición que no
sea pública:

1. **quién es** — verifica el ID token de Firebase (`src/firebase.ts`);
2. **puede** — aplica la política que lleva el propio repositorio de contenido
   (`src/policy.ts`);
3. **hazlo** — habla con GitHub con un token que el navegador nunca ve
   (`src/github.ts`).

El orden *es* el diseño. La identidad se establece antes de consultar la
política, y la política antes de que nada toque GitHub, así que no hay camino
al repositorio que se salte una comprobación. Hay tests que lo comprueban
justamente así: verifican que **GitHub no se llama** cuando una comprobación
falla.

## Por qué el token de GitHub está aquí y no en la app

Un navegador no puede guardar un secreto. Cualquier cosa que llegue al
frontend la puede leer quien abra las herramientas de desarrollo. El token
vive como secreto del Worker, solo se pone en una cabecera de salida, y no se
devuelve, ni se registra, ni aparece en ningún error.

Lo que **sí** está en la app es la configuración web de Firebase, y no es un
secreto: una API key de Firebase identifica el proyecto, no autoriza nada. Lo
que protege el material son los proveedores de acceso habilitados, los dominios
autorizados, y `access.json`.

## La superficie de la API

Deliberadamente mínima. Cada ruta es una operación con nombre sobre una ruta
dentro de **un** repositorio; nada reenvía una ruta arbitraria de la API de
GitHub, y nada toma el repositorio de quien llama — un proxy que acepta el
repositorio del cliente es un proxy abierto a todo lo que el token alcance.

| | |
|---|---|
| `GET /v1/health` | si el Worker está configurado (sin revelar nada) |
| `GET /v1/me` | quién soy y qué puedo |
| `GET /v1/file?path=` | leer un fichero |
| `PUT /v1/file` | escribir un fichero (compare-and-set con el `sha`) |
| `GET /v1/policy` | la política (solo admin: es una lista de direcciones) |

## Desplegar

```bash
cd api
npm install
npx wrangler login                      # abre el navegador, es tu sesión
npx wrangler secret put GITHUB_TOKEN    # lo pide por stdin; no lo pongas en un fichero
npx wrangler deploy
```

El token de GitHub debe ser un **fine-grained personal access token** limitado
a `franjfal/didacta_db` con permiso `Contents: Read and write` y nada más. Un
token clásico con `repo` alcanza todos tus repositorios, y este Worker no
necesita ninguno más.

Después, en `wrangler.jsonc`, añade el origen de la app publicada a
`ALLOWED_ORIGINS`. Nunca `*`: esta API responde con material privado y acepta
escrituras, así que un comodín dejaría que cualquier página que visite una
persona con sesión leyera su repositorio.

## Comprobar

```bash
npm test        # 102 tests
npm run typecheck
```

Los tests de `firebase.test.ts` generan un par de claves RSA de verdad y firman
tokens de verdad, así que la comprobación de firma se ejerce en serio. Cada
ataque que cubren está nombrado: `alg: none`, HS256 con la clave pública,
token de otro proyecto, token caducado, payload manipulado.
