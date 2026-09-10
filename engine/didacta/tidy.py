"""Removing the migration header from a `.tex`.

The migrator used to write three comment lines at the top of every unit::

    % Migrated from 00classnotes/Algebra/.../92CAS-Aplications.tex
    %
    % No preamble: Didacta supplies it.
    %%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%

Which was a mistake, and an expensive one to notice: it is the first thing
anyone sees on opening a unit to edit it, above the content, in an editor, in
2438 files. Nobody needs to be told on every file that Didacta supplies the
preamble.

The provenance is not lost. `unit.yaml` records the same source path, and the
migration is a commit. What a `.tex` holds is content.

This is a separate module rather than a script because it edits 2438 tracked
files: it has to be reviewable, testable, and exact about what it will and
will not touch. In particular it removes **only** a header it recognises at
the very top of the file, and never a comment that is part of the content.
"""

from __future__ import annotations

import os
import re

#: A line of nothing but `%`, which is how the legacy files ruled off a
#: header. Three of them followed the provenance.
_RULE = re.compile(r"^%{4,}\s*$")

#: The provenance line itself.
_MIGRATED = re.compile(r"^%\s*Migrated from\b")

#: The line that told every file the same thing.
_NO_PREAMBLE = re.compile(r"^%\s*No preamble\b")

#: An empty comment: the `%` that separated the two.
_EMPTY_COMMENT = re.compile(r"^%\s*$")


def strip_header(text):
    """Return [text] without its migration header.

    Recognises the header only at the top of the file, and only as the shapes
    the migrator wrote. Anything else -- a comment somebody added, a `%` in
    the middle of the content, a file with no header -- comes back unchanged.

    Returns the text unchanged when there is no provenance line, so this is
    safe to run twice and safe to run on hand-written units.
    """
    lines = text.split("\n")

    # Only a file whose header *starts* with the provenance is touched. A
    # `.tex` that opens with somebody's own comment is left alone: guessing
    # which comments are noise is how a tool eats someone's notes.
    first = 0
    while first < len(lines) and lines[first].strip() == "":
        first += 1
    if first >= len(lines) or not _MIGRATED.match(lines[first]):
        return text

    index = first
    while index < len(lines):
        line = lines[index]
        if (
            _MIGRATED.match(line)
            or _NO_PREAMBLE.match(line)
            or _EMPTY_COMMENT.match(line)
            or _RULE.match(line)
        ):
            index += 1
            continue
        break

    # The blank lines the header left behind go with it: the content should
    # start on line 1, not line 3.
    while index < len(lines) and lines[index].strip() == "":
        index += 1

    stripped = "\n".join(lines[index:])
    return stripped.lstrip("\n")


def tex_files(root):
    """Every unit `.tex` under the content trees, in a stable order."""
    found = []
    for area in ("content", "problems"):
        base = os.path.join(root, area)
        if not os.path.isdir(base):
            continue
        for directory, _, names in os.walk(base):
            for name in sorted(names):
                if name.endswith(".tex"):
                    found.append(os.path.join(directory, name))
    return sorted(found)


class TidyResult:
    """What tidying did, or would do."""

    __slots__ = ("changed", "unchanged", "bytes_removed", "paths")

    def __init__(self):
        self.changed = 0
        self.unchanged = 0
        self.bytes_removed = 0
        self.paths = []

    def as_dict(self):
        return {
            "changed": self.changed,
            "unchanged": self.unchanged,
            "bytesRemoved": self.bytes_removed,
        }


def tidy(root, *, apply=False, on_file=None):
    """Strips the migration header from every unit under [root].

    Writes nothing unless [apply]; without it this reports what it would do,
    which is how a bulk edit of 2438 tracked files should start.
    """
    result = TidyResult()
    for path in tex_files(root):
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        stripped = strip_header(original)
        if stripped == original:
            result.unchanged += 1
            continue
        result.changed += 1
        result.bytes_removed += len(original) - len(stripped)
        result.paths.append(os.path.relpath(path, root))
        if on_file:
            on_file(os.path.relpath(path, root))
        if apply:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(stripped)
    return result
