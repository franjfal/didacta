---
title: Compilar
description: Sacar los PDF, ver la consola y comparar versiones dentro de la ventana.
---

# Compilar

Didacta no reimplementa nada de LaTeX: llama a `cli/didacta`, que es el mismo
camino que se usa desde el terminal. Lo que aporta es elegir, lanzar y enseñar.

!!! note "Hoy, en macOS y Linux"

    En Windows el resto de la aplicación funciona, pero los PDF hay que
    sacarlos desde el terminal.

![Elegir qué versiones y en qué idiomas](../img/app/unidad-compilar.png)

## El botón

**Compilar** saca lo que corresponda a lo que estés mirando: una unidad suelta
en su perfil de vista previa, un documento en los perfiles que tenga
declarados.

Manteniéndolo pulsado se eligen **perfiles e idiomas**. Y hay una opción de
compilar en todos los idiomas a la vez, que es lo que hace falta antes de
subir un tema al aula virtual.

## La consola

Mientras compila se puede abrir la consola, que enseña lo que el motor va
escribiendo según lo escribe: qué fichero lee, qué paquete carga, qué pasada
va.

No es adorno. La alternativa era un botón que ponía «Compilando…», y un minuto
de eso no se distingue de un cuelgue.

Se enseña **entera y sin filtrar**. Los diagnósticos ya interpretados están en
las tarjetas de resultado, que contestan a «¿qué ha fallado?»; la consola
contesta a «¿qué está haciendo?», y esa pregunta no se contesta con una
selección de líneas.

Cerrarla no para nada, y se puede volver a abrir mientras corre y después.

## El PDF, dentro

Cada salida es **una pestaña más**, al lado de los idiomas y de `unit.yaml`. Y
los idiomas del mismo perfil van en la misma pestaña, lado a lado.

Eso es lo que hace falta para el trabajo real: comparar «cómo queda en
diapositivas» con «cómo queda en libro», o el castellano con el valenciano, es
mirar dos cosas a la vez, y salir a otra aplicación para cada una rompe justo
eso.

En la barra de la pestaña está lo que vale para toda ella: pasar página en los
dos paneles a la vez, separar una versión, elegir otras. Las acciones sobre un
PDF concreto --abrirlo en el visor del sistema, enseñarlo en el Finder-- están
en su propio panel, porque con dos PDF a la vez «abrir en el visor» en la
barra no dice cuál.

El visor del sistema sigue estando, y no es redundancia: tiene pantalla
completa para pasar diapositivas de verdad, y el explorador de archivos es
desde donde se arrastra un PDF a un correo.

### Cuando un PDF se ha quedado viejo

La pestaña lo marca en ámbar. Lo que hay abierto sigue siendo un PDF de
verdad, pero es de antes del último cambio, y eso hay que saberlo **antes** de
proyectarlo en una clase.

## Cuando falla

Las tarjetas de resultado dicen, por cada salida, si salió y en cuántas
páginas. Cuando no sale, el error del log con su fichero y su línea, y un
enlace para saltar ahí.

Un idioma que falta no es un error: es un aviso. El documento se compila con
el idioma de referencia en su sitio y se dice cuál faltaba.
