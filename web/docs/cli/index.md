---
title: La herramienta
description: didacta, la orden del terminal: qué hace cada subcomando.
---

# `didacta`, en el terminal

La aplicación no reimplementa nada: llama a esta misma herramienta. Todo lo
que hace Didacta se puede hacer desde aquí, y algunas cosas **solo** se pueden
hacer desde aquí.

```bash
git clone https://github.com/franjfal/didacta.git
cd mi-repositorio-de-contenido
../didacta/cli/didacta status
```

Se ejecuta desde cualquier sitio dentro de un repositorio de contenido: la
raíz se localiza subiendo hasta encontrar `didacta.yaml`, igual que hace git
con `.git`.

!!! info "Python 3.9 y ninguna dependencia"

    No hay nada que instalar con `pip`. Es deliberado: la plataforma tiene que
    poder funcionar en un runner de integración continua sin un paso de
    instalación, y en la máquina de cualquiera sin preparar un entorno.

## Mirar

```bash
didacta status              # qué hay en este repositorio
didacta profiles            # las salidas disponibles
didacta units               # la biblioteca
didacta units --category analysis --missing va
didacta translations        # qué falta traducir, por cuánto se usa
didacta built am-iii/2025-2026   # qué hay compilado de un curso
```

## Comprobar

```bash
didacta check
```

Referencias que no resuelven, perfiles que no existen, documentos que compilan
en un idioma que su contenido no tiene. Es lo que conviene ejecutar antes de
dar por bueno un curso, y lo que un repositorio de contenido debería correr en
su integración continua.

## Compilar

```bash
didacta build tema-1                 # todas sus salidas
didacta build tema-1 -p slides -l va # una salida, un idioma
didacta build --all                  # el repositorio entero
didacta build --all --list           # qué haría, sin hacerlo
didacta preview analysis/normed/definition   # una unidad suelta
```

La compilación es **fuera del árbol** y con SyncTeX: el repositorio no se
llena de `.aux`, y el PDF sabe volver a la línea del fichero fuente.

## Crear

```bash
didacta new unit analysis/normed/dual-space
didacta new unit analysis/series/convergence --kind problem
didacta new year am-iii 2026-2027
didacta copy am-iii/2025-2026 am-iii/2026-2027 --document tema-1
```

## Repartir

```bash
didacta export am-iii/2025-2026 ~/Escritorio/AM3
```

Saca los PDF ya compilados a una carpeta, en carpetas por idioma y con nombres
que se leen.

## El catálogo

```bash
didacta index
didacta index --check
```

Genera los tres JSON de `generated/` que lee la aplicación. Son **datos
derivados**: regenerarlos da los mismos bytes, y `--check` falla si están
desincronizados, que es lo que se pone en la integración continua.

## El servidor MCP

```bash
didacta mcp
```

El mismo servidor que enciende la aplicación desde Ajustes, para un cliente
que se lance a mano.

[:octicons-arrow-right-24: El servidor MCP](../app/mcp.md)

## Traer material de un sistema anterior

```bash
didacta migrate ~/Teaching ~/didacta-content
didacta migrate ~/Teaching ~/didacta-content --year 2025-2026 --apply
didacta migrate ~/Teaching ~/didacta-content --year 2025-2026 --apply --verify
```

**Sin `--apply` no escribe nada**, y en ningún caso toca el repositorio de
origen. Con `--verify` compila además cada documento migrado y lista en el
informe los que no salen, con fichero, línea y la macro culpable.

Deja un `MIGRATION-REPORT.md` con lo que no ha podido deducir: el material
antiguo no guardaba metadatos, y eso no se inventa.

## Limpiar

```bash
didacta tidy      # quita la cabecera de migración de los fuentes
didacta remove course am-iii            # cuenta lo que se llevaría
didacta remove course am-iii --apply    # y entonces lo hace
```

`remove` **sin `--apply` no borra nada**: cuenta qué se llevaría. Es la misma
cifra que enseña la aplicación antes de preguntar.
