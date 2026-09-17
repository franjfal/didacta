---
title: El primer repositorio
description: Entrar en GitHub, abrir un repositorio de contenido o crear uno nuevo.
---

# Entrar y abrir el primer repositorio

Didacta no guarda material: lo guarda GitHub. La aplicación trabaja sobre
**clones locales** de tus repositorios, y cada cambio que haces es un commit.

Eso tiene una consecuencia que conviene entender desde el principio:

!!! abstract "La sesión es el permiso"

    Quién puede leer un repositorio y quién puede escribir en él lo dice
    GitHub. Didacta no mantiene ninguna otra lista de usuarios, ni tiene
    cuentas propias, ni hay nada que se pueda quedar desincronizado con la
    realidad. Si alguien deja el departamento, se le quita del repositorio y
    ya está.

## 1. Entrar en GitHub

La primera vez que abres Didacta te lo pide antes que nada.

![La pantalla de bienvenida de Didacta](../img/app/bienvenida.png)

Al pulsar **Entrar en GitHub** pasa esto:

1. Didacta enseña un código corto, tipo `ABCD-1234`, y lo copia al
   portapapeles;
2. abre `github.com/login/device` en tu navegador;
3. pegas el código y autorizas;
4. la ventana de Didacta se cierra sola.

!!! success "La contraseña se teclea en github.com y en ningún otro sitio"

    Es un *device flow*, y está elegido justamente por eso: Didacta **no ve
    nunca tu contraseña**. Lo que recibe al final es un token, que se guarda
    en el llavero del sistema --Keychain en macOS, Credential Manager en
    Windows, Secret Service en Linux-- y nunca en un fichero ni en un log.

    El permiso que se pide es `repo`, y nada más. Sin `delete_repo`, sin
    `admin`, sin `user`.

Una vez dentro, **Didacta se abre también sin conexión**. Lo que se exige es
haber entrado alguna vez, no estar conectado ahora: un aula sin wifi no puede
dejar a nadie sin sus diapositivas, y el trabajo está en un clon del disco.

## 2. Abrir un repositorio de contenido

Un *repositorio de contenido* es un repositorio de GitHub con material de
Didacta dentro: un `didacta.yaml` en la raíz, y las carpetas `content/`,
`problems/` y `courses/`.

![El paso del asistente donde se abre el primer repositorio](../img/app/bienvenida-repositorio.png)

Hay tres caminos, y el asistente de bienvenida los ofrece los tres:

=== "Ya tengo uno en GitHub"

    Didacta lista los repositorios a los que llega tu cuenta. Eliges uno --o
    varios, marcándolos-- y los clona en `~/Didacta/<nombre>`.

    Se pueden marcar varios de golpe a propósito: una asignatura puede estar
    repartida --la teoría en uno, los problemas en otro-- y quien llega nuevo
    los quiere los dos.

=== "Ya lo tengo clonado en el disco"

    Eliges la carpeta y ya está. De qué repositorio es lo dice su propio
    remoto, así que esto funciona sin pasar por GitHub.

    Es la carpeta que tiene dentro `didacta.yaml`, `content/` y `courses/`.

=== "Quiero empezar de cero"

    Crea un repositorio vacío en GitHub --sin README, sin licencia, sin
    nada-- y elígelo en la lista. Didacta verá que está vacío y se ofrecerá a
    **prepararlo**: el primer commit crea `didacta.yaml` y la estructura de
    carpetas, a tu nombre.

    Solo te pregunta el título. Lo demás son valores por defecto que luego se
    cambian en `didacta.yaml`.

[:octicons-arrow-right-24: Cómo se organiza un repositorio de contenido](../conceptos/repositorios.md)

## 3. El motor, para poder compilar

La biblioteca, el editor y el historial funcionan solo con el clon. Para
**compilar PDF** hace falta además el motor: el repositorio de Didacta, que es
el que lleva `cli/didacta` y el sistema LaTeX.

El asistente de bienvenida lo ofrece con un botón --lo clona al lado de tus
repositorios y lo deja configurado-- y también está en **Ajustes →
Compilación**. A mano es esto:

```bash
git clone https://github.com/franjfal/didacta.git ~/Didacta/didacta
```

Didacta lo busca solo al lado de tus clones, en `~/didacta` y en el PATH; si
está en otro sitio, se le dice en Ajustes.

## Varios repositorios a la vez

No hay un «repositorio activo». Didacta abre **todos los que le digas** y los
enseña juntos: la biblioteca es la suma de todos, cada uno con su color, y
cada cambio va al repositorio del que salió el fichero.

Es lo que permite el reparto que en la práctica hace falta:

- una **colección de problemas compartida**, en un repositorio al que llega
  todo el departamento;
- **los apuntes de cada uno**, en un repositorio suyo que no comparte con
  nadie;
- una **asignatura partida** entre dos, porque la teoría y las prácticas las
  llevan personas distintas.

[:octicons-arrow-right-24: Repositorios compartidos, y qué se comprueba entre ellos](../app/entre-repos.md)

## El siguiente paso

[Los primeros diez minutos](primeros-pasos.md){ .md-button .md-button--primary }
