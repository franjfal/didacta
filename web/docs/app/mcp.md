---
title: El servidor MCP
description: Dejar que un modelo lea --y si quieres, escriba-- tu material.
---

# El servidor MCP

Didacta puede levantar un servidor [MCP](https://modelcontextprotocol.io/) que
expone tus repositorios a un cliente de IA: Claude Desktop, Claude Code o
cualquier otro que hable el protocolo.

![La pantalla del servidor MCP](../img/app/mcp.png)

## Qué puede hacer

| Herramienta | Qué contesta |
|---|---|
| `list_repositories` | qué repositorios hay abiertos y en cuáles se puede escribir |
| `list_courses` | las asignaturas y sus cursos académicos |
| `read_course` | los temas y documentos de un curso, con sus unidades en orden |
| `search_units` | buscar por texto, categoría, tema, etiqueta o **idioma que falta** |
| `read_unit` | una unidad, en el idioma que se pida |
| `translation_status` | qué falta por traducir |
| `check` | las comprobaciones del repositorio |

Y con escritura activada, además:

| Herramienta | Qué hace |
|---|---|
| `write_unit` | escribe el contenido de una unidad en un idioma |
| `create_unit` | crea una unidad nueva |
| `set_unit_metadata` | cambia título, etiquetas o campos de `unit.yaml` |
| `build_document` | compila un documento |

La lista de la pantalla no está escrita a mano: se le pregunta al servidor por
el protocolo, así que no se puede quedar vieja el día que el motor gane una
herramienta.

## Dos interruptores, no uno

**Encenderlo** es dejar que un modelo **lea** tu material. Eso es inocuo y es
casi todo el valor: preguntar qué unidades hay sin traducir, buscar dónde se
define algo, sacar el índice de un tema.

**Dejarle escribir** es otra cosa, y se marca **repositorio a repositorio**.
Empieza sin ninguno marcado.

Nada de esto se enciende solo al abrir Didacta salvo que ya estuviera
encendido: es una decisión de la persona, no algo que se herede de una
instalación.

## Se ve lo que hace

La mitad de arriba de la pantalla es el registro en vivo: quién se ha
conectado, qué herramienta ha llamado, sobre qué y si salió bien.

Es lo que hace la diferencia entre delegar y perder el control. Un servidor que
escribe en los ficheros de alguien sin que se pueda ver qué toca no es una
herramienta en la que haya motivo para confiar.

Y todo lo que escriba pasa por donde pasa lo demás: **es un commit**, con su
autor y su mensaje, y se puede mirar en el historial y deshacer.

## Cómo se conecta un cliente

La pantalla da la dirección y el trozo de configuración que hay que pegar en
el cliente. Es lo primero que hace falta y lo único que no se puede adivinar.
