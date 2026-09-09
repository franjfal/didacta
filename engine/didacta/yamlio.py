"""YAML reading and writing.

Didacta content carries its metadata in YAML next to it, so this has to work
on a bare Python install: the platform must be usable on a fresh machine and in
a CI runner without a pip step. PyYAML is used when present and a deliberately
small hand-rolled reader takes over when it is not.

The supported subset is exactly what the content schemas use: nested block
mappings, block sequences (including sequences of mappings), inline ``[a, b]``
lists, inline ``{k: v}`` mappings, quoted and bare scalars, comments and blank
lines. Anything outside it raises rather than being guessed at, so a
hand-edited file that drifts is reported instead of silently misread.
"""

from __future__ import annotations

import os
import re

try:  # pragma: no cover - depends on the machine
    import yaml as _pyyaml
except ImportError:  # pragma: no cover
    _pyyaml = None


class YamlError(ValueError):
    """A YAML file could not be parsed, or violates its schema."""


#: Alias kept so callers can catch one name regardless of which reader ran.
SidecarError = YamlError


# --------------------------------------------------------------------------
# Minimal YAML reader
# --------------------------------------------------------------------------

_KEY = re.compile(r"^(?P<indent>\s*)(?P<key>[^:#]+?)\s*:\s*(?P<value>.*?)\s*$")
_ITEM = re.compile(r"^(?P<indent>\s*)-\s*(?P<value>.*?)\s*$")


def _parse_scalar(text):
    """Convert a YAML scalar to a Python value.

    Quoting is checked *before* anything else, because that is what quoting is
    for: ``'2025'`` is the string and ``2025`` is the number, and a tag or an
    academic year that silently becomes an integer breaks a comparison
    somewhere far away from the file it came from.
    """
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        inner = text[1:-1]
        if text[0] == "'":
            # In single quotes the only escape YAML has is a doubled quote.
            return inner.replace("''", "'")
        return inner.replace('\\"', '"').replace("\\\\", "\\")
    if text == "" or text == "~" or text == "null":
        return None
    if text in ("true", "True", "yes"):
        return True
    if text in ("false", "False", "no"):
        return False
    if re.match(r"^-?\d+$", text):
        return int(text)
    if re.match(r"^-?\d+\.\d+$", text):
        return float(text)
    return text


def _parse_inline_list(text):
    """Parse ``[a, b, "c d"]`` into a list of scalars.

    The quotes are kept while splitting and removed by ``_parse_scalar``,
    which is the only place that knows what they mean. Stripping them here --
    as this did -- turned ``['2025']`` into the integer 2025.
    """
    inner = text[1:-1].strip()
    if not inner:
        return []
    parts = []
    current = ""
    quote = None
    for ch in inner:
        if quote:
            current += ch
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            current += ch
        elif ch == ",":
            parts.append(current.strip())
            current = ""
        else:
            current += ch
    parts.append(current.strip())
    return [_parse_scalar(p) for p in parts if p != ""]


def loads(text):
    """Parse YAML into nested dicts and lists.

    Uses PyYAML when installed; otherwise falls back to the subset reader
    below, which covers everything the Didacta schemas need.
    """
    if _pyyaml is not None:
        try:
            loaded = _pyyaml.safe_load(text)
        except Exception as exc:  # PyYAML raises several unrelated types
            raise YamlError(str(exc))
        return loaded if isinstance(loaded, (dict, list)) else {}
    return _loads_subset(text)


def load_file(path):
    """Read and parse one YAML file."""
    try:
        with open(path, encoding="utf-8") as handle:
            return loads(handle.read())
    except OSError as exc:
        raise YamlError("%s: %s" % (path, exc))


def _loads_subset(text):
    """Parse the supported YAML subset into nested dicts and lists.

    Supported, because it is all the schemas need: nested block mappings, block
    sequences (including sequences of mappings, as in ``users:``), inline
    ``[a, b]`` lists, inline ``{k: v}`` mappings, quoted and bare scalars,
    comments and blank lines.

    Anything else raises :class:`SidecarError`, so a hand-edited file that
    drifts outside the subset is reported rather than silently misread.
    """
    lines = []
    for number, raw in enumerate(text.split("\n"), start=1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#") or stripped in ("---", "..."):
            continue
        if raw.lstrip().startswith("\t") or "\t" in raw[: len(raw) - len(raw.lstrip())]:
            raise YamlError("line %d: tabs are not valid YAML indentation" % number)
        lines.append((len(raw) - len(raw.lstrip()), stripped, number))

    if not lines:
        return {}
    value, index = _parse_block(lines, 0, lines[0][0])
    if index != len(lines):
        raise YamlError("line %d: unexpected indentation" % lines[index][2])
    return value if isinstance(value, (dict, list)) else {}


def _parse_block(lines, index, indent):
    """Parse the block at ``indent`` starting at ``lines[index]``."""
    if index >= len(lines):
        return {}, index
    if lines[index][1].startswith("- ") or lines[index][1] == "-":
        return _parse_sequence(lines, index, indent)
    return _parse_mapping(lines, index, indent)


def _parse_sequence(lines, index, indent):
    items = []
    while index < len(lines):
        item_indent, content, number = lines[index]
        if item_indent < indent:
            break
        if item_indent > indent:
            raise YamlError("line %d: unexpected indentation in list" % number)
        if not (content.startswith("- ") or content == "-"):
            break
        rest = content[2:].strip() if content.startswith("- ") else ""
        index += 1

        if not rest:
            # `-` alone: the item is the nested block below it.
            if index < len(lines) and lines[index][0] > indent:
                value, index = _parse_block(lines, index, lines[index][0])
                items.append(value)
            else:
                items.append(None)
            continue

        match = _KEY.match(rest)
        if match and not rest.startswith(("[", "{", '"', "'")):
            # `- key: value`: the item is a mapping whose first pair is inline.
            # Reparse it as a mapping at a virtual indent so sibling keys on
            # following, deeper-indented lines join the same mapping.
            inner_indent = indent + 2
            synthetic = [(inner_indent, rest, number)]
            while index < len(lines) and lines[index][0] > indent:
                if lines[index][1].startswith("- ") and lines[index][0] == inner_indent:
                    break
                synthetic.append((lines[index][0], lines[index][1], lines[index][2]))
                index += 1
            value, consumed = _parse_mapping(synthetic, 0, inner_indent)
            if consumed != len(synthetic):
                raise YamlError("line %d: unexpected indentation in list item" % number)
            items.append(value)
        else:
            items.append(_parse_value(rest, number))
    return items, index


def _parse_mapping(lines, index, indent):
    mapping = {}
    while index < len(lines):
        key_indent, content, number = lines[index]
        if key_indent < indent:
            break
        if key_indent > indent:
            raise YamlError("line %d: unexpected indentation in mapping" % number)
        if content.startswith("- ") or content == "-":
            break

        match = _KEY.match(content)
        if not match:
            raise YamlError("line %d: cannot parse %r" % (number, content))
        key = match.group("key").strip().strip("\"'")
        raw_value = match.group("value")
        index += 1

        if raw_value == "":
            # Nested block. A sequence may sit at the same indent as its key,
            # which is legal YAML and used by the schemas.
            if index < len(lines) and (
                lines[index][0] > indent
                or (lines[index][0] == indent and lines[index][1].startswith(("- ", "-")))
            ):
                child_indent = lines[index][0]
                value, index = _parse_block(lines, index, child_indent)
            else:
                value = None
        else:
            value = _parse_value(raw_value, number)
        mapping[key] = value
    return mapping, index


def _parse_value(raw, number):
    if raw.startswith("[") and raw.endswith("]"):
        return _parse_inline_list(raw)
    if raw.startswith("{") and raw.endswith("}"):
        inner = raw[1:-1].strip()
        out = {}
        if inner:
            for piece in _split_inline(inner):
                if ":" not in piece:
                    raise YamlError("line %d: bad inline mapping entry %r" % (number, piece))
                key, value = piece.split(":", 1)
                out[key.strip().strip("\"'")] = _parse_scalar(value.strip())
        return out
    return _parse_scalar(raw)


def _split_inline(text):
    parts = []
    current = ""
    quote = None
    for ch in text:
        if quote:
            current += ch
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            current += ch
        elif ch == ",":
            parts.append(current.strip())
            current = ""
        else:
            current += ch
    if current.strip():
        parts.append(current.strip())
    return parts


# --------------------------------------------------------------------------
# Minimal YAML writer
# --------------------------------------------------------------------------

_PLAIN = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9 _.@/+-]*$")


def _fmt(value):
    if value is None:
        return "~"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if _PLAIN.match(text) and text.strip() == text:
        return text
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def dumps(data, indent=0):
    """Serialise nested dicts/lists back to the supported YAML subset.

    Keys are emitted in insertion order, so a read-modify-write cycle keeps the
    file stable and the git diff minimal.
    """
    out = []
    pad = "  " * indent
    for key, value in data.items():
        if isinstance(value, dict):
            if not value:
                out.append("%s%s: {}" % (pad, key))
            else:
                out.append("%s%s:" % (pad, key))
                out.append(dumps(value, indent + 1))
        elif isinstance(value, list):
            if not value:
                out.append("%s%s: []" % (pad, key))
            elif all(not isinstance(v, (dict, list)) for v in value):
                out.append("%s%s: [%s]" % (pad, key, ", ".join(_fmt(v) for v in value)))
            else:
                out.append("%s%s:" % (pad, key))
                for item in value:
                    if isinstance(item, dict):
                        rendered = dumps(item, indent + 2).split("\n")
                        out.append("%s  - %s" % (pad, rendered[0].strip()))
                        out.extend(rendered[1:])
                    else:
                        out.append("%s  - %s" % (pad, _fmt(item)))
        else:
            out.append("%s%s: %s" % (pad, key, _fmt(value)))
    return "\n".join(out)


# --------------------------------------------------------------------------
# Schema helpers
# --------------------------------------------------------------------------


def require(data, key, path, kind=None):
    """Read a required key, reporting the file when it is absent or wrong."""
    if key not in data or data[key] is None:
        raise YamlError("%s: missing required key `%s`" % (path, key))
    value = data[key]
    if kind is not None and not isinstance(value, kind):
        raise YamlError(
            "%s: `%s` should be %s, got %s"
            % (path, key, getattr(kind, "__name__", kind), type(value).__name__)
        )
    return value


def optional(data, key, default=None, kind=None, path=""):
    """Read an optional key, still checking its type when present."""
    value = data.get(key, default)
    if value is None:
        return default
    if kind is not None and not isinstance(value, kind):
        raise YamlError(
            "%s: `%s` should be %s, got %s"
            % (path, key, getattr(kind, "__name__", kind), type(value).__name__)
        )
    return value


def localised(value, languages, path="", key=""):
    """Normalise a field that may be one string or a per-language mapping.

    Titles are the common case: a unit may declare one title for every
    language, or one per language. Both are accepted and both come back as a
    ``{language: text}`` mapping so callers never have to branch.
    """
    if value is None:
        return {}
    if isinstance(value, str):
        return {code: value for code in languages}
    if isinstance(value, dict):
        unknown = [k for k in value if k not in languages]
        if unknown:
            raise YamlError(
                "%s: `%s` names unknown language(s) %s (known: %s)"
                % (path, key, unknown, ", ".join(languages))
            )
        return {k: str(v) for k, v in value.items()}
    raise YamlError("%s: `%s` should be a string or a per-language mapping" % (path, key))
