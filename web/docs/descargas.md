---
title: Descargar
description: Los instaladores de la última versión, con sus checksums.
---

# Descargar Didacta

--8<-- "descargas.md"

## Qué hace falta además

Didacta necesita **git** y **una distribución de TeX** en la máquina, y usa
**Python 3.9 o posterior** para el motor. Lo que no lleva dentro, lo busca.

[:octicons-arrow-right-24: Instalar, con todo el detalle](empezar/index.md)

## Se actualiza sola

Una vez por semana, en segundo plano, y **pregunta antes de hacer nada**.
Comprueba el SHA-256 de lo que ha descargado antes de tocar la instalación que
funciona, y deja la versión anterior apartada hasta que la nueva arranca.

[:octicons-arrow-right-24: Cómo funciona](app/ajustes.md#actualizaciones)

## Compilar desde el código

Didacta es software libre: el código está en
[franjfal/didacta](https://github.com/franjfal/didacta) y se compila con
Flutter.

```bash
git clone https://github.com/franjfal/didacta.git
cd didacta/app
flutter pub get
flutter run -d macos     # o -d windows, o -d linux
```

[:octicons-arrow-right-24: El proyecto](proyecto/index.md)
