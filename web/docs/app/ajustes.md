---
title: Ajustes
description: La cuenta, los repositorios, LaTeX, la traducción y las actualizaciones.
---

# Ajustes

![La pantalla de ajustes](../img/app/ajustes.png)

## Tu cuenta de GitHub

Quién ha entrado, y los botones de salir o cambiar de cuenta.

El token vive en el **llavero del sistema** --Keychain, Credential Manager,
Secret Service-- y nunca en un fichero de configuración ni en un log. Salir lo
borra de ahí.

[:octicons-arrow-right-24: Cómo funciona el acceso](../empezar/primer-repositorio.md#1-entrar-en-github)

## Los repositorios

Los que están abiertos, cada uno con:

- **su carpeta** en el disco;
- **su color**, el que lo identifica en toda la aplicación;
- **cómo está respecto a GitHub**: cuántos commits por enviar, cuántos por
  traer, si hay cambios sin guardar;
- botones para traer, enviar y quitarlo de la lista.

Quitarlo de la lista **no borra la carpeta**. Es dejar de abrirlo.

Se añaden desde GitHub --Didacta lista los que alcanza tu cuenta-- o eligiendo
una carpeta que ya esté clonada.

**Dónde se clonan** se elige aquí. Por defecto, `~/Didacta`.

## Las preferencias que viajan

Algunas preferencias --qué asignaturas son favoritas, qué temas están
plegados-- son de la persona, no de la máquina, y se pueden guardar en uno de
tus repositorios para encontrarlas igual en el ordenador de casa.

Se **elige** cuál, y no se decide por ti, porque no hay ninguna elección
evidente: cada uno tiene los repositorios que tiene. Sin elegir ninguno, todo
sigue funcionando en esta máquina.

## Compilación

Dos rutas, y Didacta busca las dos sola:

**El motor** --el repositorio de Didacta, el que lleva `cli/didacta`. Hay un
botón para descargarlo si no lo tienes.

**La distribución de TeX.** Si no la encuentra, la pantalla dice **dónde ha
mirado**, que es lo que permite arreglarlo.

[:octicons-arrow-right-24: La distribución de TeX](../empezar/latex.md)

## Traducción

La clave del traductor automático, que vive en el llavero y no se vuelve a
enseñar, con su botón de probar.

[:octicons-arrow-right-24: Traducción automática](traduccion.md#traduccion-automatica)

## El servidor MCP

El interruptor, y en qué repositorios puede escribir.

[:octicons-arrow-right-24: El servidor MCP](mcp.md)

## Actualizaciones

Qué versión tienes, cuándo se miró por última vez y un botón para mirar ahora.

### Cómo funciona

Didacta mira **una vez por semana**, en segundo plano, después de que la
aplicación esté en pie. Ni al arrancar --retrasaría la primera pantalla por
una petición que a nadie le urge-- ni cada vez, que es cómo un aviso útil se
convierte en ruido que se cierra sin leer.

**Si no hay nada nuevo, no dice nada.**

Cuando la hay, aparece una franja arriba que se puede dejar para luego.
Cerrarla no es decir que no: la versión sigue estando y Ajustes la sigue
ofreciendo. Lo que no vuelve es la franja, hasta que se publique otra versión
distinta.

### Lo que pasa al actualizar

```
1. descargar, con progreso y cancelable
2. comprobar el SHA-256   ← si no cuadra, se borra y no se instala. Nunca.
3. comprobar el tamaño
4. extraer y comprobar que dentro hay una aplicación de verdad
5. comprobar la firma, si la versión instalada estaba firmada
6. escribir el script de sustitución
   ── hasta aquí, la instalación que funciona no se ha tocado ──
7. cerrar Didacta
8. el script sustituye, con copia de seguridad
9. relanzar
```

La versión anterior **se aparta, no se borra**, y solo desaparece cuando la
nueva está en su sitio y se ha comprobado que arranca. Si algo falla entre
medias, vuelve la de antes.

Y al arrancar, Didacta compara lo que se estaba instalando con lo que de
verdad está corriendo, y lo dice. Sin eso, una sustitución que falló y se
restauró sería indistinguible de una que salió.

### Cuando no se puede

Se dice **antes** de descargar nada:

- una Didacta en `/Aplicaciones` con una cuenta que no es administradora;
- un Linux donde Didacta no viene de un AppImage --manda el gestor de
  paquetes;
- sin conexión, o con GitHub caído.

Ninguno de esos casos impide usar Didacta. Buscar actualizaciones nunca puede
quitarte la aplicación.

[:octicons-arrow-right-24: Cómo se publica una versión](../proyecto/distribucion.md)
