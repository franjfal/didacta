"""The build engine.

Turns one source document into any number of PDFs. This is the part of Didacta
that earns its keep, so a few decisions are worth stating up front.

**Out-of-tree by default.** Auxiliaries and PDFs go to a build directory, never
next to the source. Building in place is how a content repository ends up with
thousands of committed ``.aux`` and ``.log`` files, which is exactly the state
the legacy repository is in.

**SyncTeX always on.** Clicking in the PDF has to jump to the source line. It
is a hard requirement, not a nicety, so it is not a flag.

**latexmk, not a hand-rolled loop.** Cross-references, the table of contents and
the total slide count all need two or three passes, and latexmk already knows
when it has converged. Reimplementing that is a way to ship subtly wrong page
counts.

**One profile, one directory.** Two profiles of the same document share a job
name only by accident; keeping their auxiliaries apart means a parallel build
cannot corrupt itself, and a failed profile leaves the others intact.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import time

from . import profiles as profiles_mod


class BuildError(RuntimeError):
    pass


# --------------------------------------------------------------------------
# Log parsing
# --------------------------------------------------------------------------


class Diagnostic:
    """One problem LaTeX reported, located well enough to jump to."""

    __slots__ = ("severity", "file", "line", "message", "context")

    def __init__(self, severity, message, file=None, line=None, context=None):
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.context = context

    def __str__(self):
        where = self.file or ""
        if self.line:
            where += ":%d" % self.line
        head = "%s %s %s" % (self.severity, where, self.message) if where else \
               "%s %s" % (self.severity, self.message)
        # "Undefined control sequence" says nothing on its own; the context is
        # where the offending macro's name appears.
        if self.context:
            head += "  <- %s" % self.context[:120]
        return head

    def as_dict(self):
        data = {"severity": self.severity, "message": self.message}
        if self.file:
            data["file"] = self.file
        if self.line:
            data["line"] = self.line
        if self.context:
            data["context"] = self.context
        return data


_FILE_OPEN = re.compile(r"\((?:\./)?([^()\s]+\.(?:tex|sty|def|cls))")
_UNDEFINED = re.compile(r"(Reference|Citation) [`']([^']*)' on page")

#: Warnings worth showing. LaTeX emits many that nobody can act on -- an
#: underfull box on a slide is normal -- and surfacing all of them trains the
#: reader to ignore the list.
_INTERESTING_WARNINGS = (
    "Reference",
    "Citation",
    "There were undefined",
    "Label(s) may have changed",
    "No positions in optional float specifier",
    "Marginpar on page",
)


def parse_log(text):
    """Extract diagnostics from a LaTeX log.

    Tracks the file-open stack so an error gets attributed to the content file
    that caused it rather than to the wrapper. That attribution is the whole
    point: an error reported against a generated wrapper is useless.
    """
    diagnostics = []
    lines = text.split("\n")
    stack = []

    for index, line in enumerate(lines):
        for name in _FILE_OPEN.findall(line):
            stack.append(name)
        # Closing parens pop; count only those not inside a filename.
        closes = line.count(")") - line.count("(")
        for _ in range(max(closes, 0)):
            if stack:
                stack.pop()
        current = stack[-1] if stack else None

        if line.startswith("! "):
            message = line[2:].strip()
            number = None
            context = []
            for follow in lines[index + 1 : index + 10]:
                match = re.match(r"^l\.(\d+)\s*(.*)$", follow)
                if match:
                    number = int(match.group(1))
                    if match.group(2).strip():
                        context.append(match.group(2).strip())
                    break
                stripped = follow.strip()
                if not stripped:
                    continue
                if stripped.startswith("<"):
                    # `<argument> Tema 3: \chapterName` -- what was being
                    # expanded, which for an undefined control sequence is the
                    # only place the macro's name appears.
                    _tag, _, rest = stripped.partition(">")
                    if rest.strip():
                        context.append(rest.strip())
                    continue
                context.append(stripped)

            diagnostics.append(
                Diagnostic(
                    "error",
                    message,
                    file=_blame(stack, number),
                    line=number,
                    context=" ".join(context[:2]) or None,
                )
            )
        elif "LaTeX Warning:" in line or "Package" in line and "Warning:" in line:
            after = line.split("Warning:", 1)[1].strip()
            if any(marker in after for marker in _INTERESTING_WARNINGS):
                diagnostics.append(Diagnostic("warning", after, file=current))

    return diagnostics


#: A package or class, as opposed to a file the author wrote.
_MACHINERY = (".sty", ".cls", ".def", ".cfg", ".fd", ".clo", ".ldf", ".tex.gz")


def _blame(stack, number):
    """Which open file an error belongs to.

    A line number in the log comes from the input LaTeX is reading, and errors
    routinely surface deep inside a package: hyperref expands a heading to
    build the PDF bookmark, so a bad macro in a `\section` is reported against
    `nameref.sty`. Blaming the package sends the author to read TeX Live.

    So when the innermost open file is machinery, walk out to the nearest file
    that is not -- the author's document, or a unit it included.
    """
    if not stack:
        return None
    if number is None:
        return stack[-1]
    for name in reversed(stack):
        if not name.lower().endswith(_MACHINERY):
            return name
    return stack[-1]


def page_count(log_text):
    """Pages written, from the log rather than by reparsing the PDF."""
    match = re.search(r"Output written on .*?\((\d+) pages?", log_text.replace("\n", ""))
    return int(match.group(1)) if match else None


# --------------------------------------------------------------------------
# Result
# --------------------------------------------------------------------------


class BuildResult:
    __slots__ = (
        "document",
        "profile",
        "language",
        "ok",
        "pdf",
        "log",
        "pages",
        "seconds",
        "diagnostics",
        "command",
    )

    def __init__(self, document, profile, language, ok, pdf=None, log=None,
                 pages=None, seconds=0.0, diagnostics=None, command=None):
        self.document = document
        self.profile = profile
        self.language = language
        self.ok = ok
        self.pdf = pdf
        self.log = log
        self.pages = pages
        self.seconds = seconds
        self.diagnostics = diagnostics or []
        self.command = command

    @property
    def errors(self):
        return [d for d in self.diagnostics if d.severity == "error"]

    @property
    def warnings(self):
        return [d for d in self.diagnostics if d.severity == "warning"]

    def as_dict(self):
        return {
            "document": self.document,
            "profile": self.profile,
            "language": self.language,
            "ok": self.ok,
            "pdf": self.pdf,
            "pages": self.pages,
            "seconds": round(self.seconds, 1),
            "diagnostics": [d.as_dict() for d in self.diagnostics],
        }


# --------------------------------------------------------------------------
# Engine
# --------------------------------------------------------------------------


class Engine:
    """Compiles documents.

    ``latex_dir`` is Didacta's own LaTeX tree; it goes on ``TEXINPUTS`` so a
    content repository never contains a relative path to it. That single change
    removes the ``../../../../Files/`` chains the legacy layout needed, which
    had to be written with a different number of levels depending on where the
    document happened to sit.
    """

    def __init__(self, latex_dir, build_dir, engine="latexmk", verbose=False):
        self.latex_dir = os.path.abspath(latex_dir)
        self.build_dir = os.path.abspath(build_dir)
        self.engine = engine
        self.verbose = verbose
        self.profiles = profiles_mod.load(self.latex_dir)

    # -- environment -----------------------------------------------------

    def texinputs(self):
        """``TEXINPUTS`` with Didacta's LaTeX tree ahead of the distribution.

        The trailing empty entry is required: without it the standard search
        path is replaced rather than extended, and nothing at all is found.
        """
        existing = os.environ.get("TEXINPUTS", "")
        parts = [
            self.latex_dir,
            os.path.join(self.latex_dir, "lang"),
            os.path.join(self.latex_dir, "themes"),
        ]
        return os.pathsep.join([p for p in parts if os.path.isdir(p)] + [existing])

    def environment(self):
        env = dict(os.environ)
        env["TEXINPUTS"] = self.texinputs()
        # Long lines in the log keep file paths on one line, which is what the
        # log parser needs to attribute an error to a file.
        env["max_print_line"] = "10000"
        env["error_line"] = "254"
        env["half_error_line"] = "238"
        return env

    def available(self):
        """Whether the toolchain is present, with a message when it is not."""
        missing = [tool for tool in (self.engine, "pdflatex") if shutil.which(tool) is None]
        if missing:
            return False, "not installed: %s" % ", ".join(missing)
        return True, None

    # -- building --------------------------------------------------------

    def output_dir(self, document_id, profile_id, language):
        return os.path.join(
            self.build_dir,
            document_id.replace("/", "_"),
            "%s-%s" % (profile_id, language),
        )

    def build(self, source, profile, language, *, document_id=None,
              document_title=None, content_root=None, keep_aux=False,
              course_keys=None):
        """Compile one source file in one profile and one language.

        ``source`` is the path to the document's ``.tex``. ``content_root`` is
        where units live, relative to the source's directory -- passed in so
        the document does not have to know.

        ``document_title`` and ``course_keys`` come from the structure files,
        and are written to an injection file in the output directory rather
        than squeezed onto the command line. Command-line ``\def`` with braces
        and accents in it is a quoting problem waiting to happen; a file is not.
        """
        if isinstance(profile, str):
            if profile not in self.profiles:
                raise BuildError(
                    "unknown profile %r (known: %s)"
                    % (profile, ", ".join(sorted(self.profiles)))
                )
            profile = self.profiles[profile]
        if language not in profiles_mod.LANGUAGES:
            raise BuildError(
                "unknown language %r (known: %s)"
                % (language, ", ".join(profiles_mod.LANGUAGES))
            )

        source = os.path.abspath(source)
        if not os.path.isfile(source):
            raise BuildError("no such document: %s" % source)

        source_dir = os.path.dirname(source)
        source_name = os.path.basename(source)
        document_id = document_id or os.path.splitext(source_name)[0]
        title = document_title or os.path.splitext(source_name)[0]

        outdir = self.output_dir(document_id, profile.id, language)
        os.makedirs(outdir, exist_ok=True)

        job = profile.output_name(title, language)
        inject = self._write_injection(outdir, title, course_keys)
        command = self._command(
            source_name, job, outdir, profile, language, content_root, inject
        )

        if self.verbose:
            print("  $ " + " ".join(command))

        started = time.time()
        completed = subprocess.run(
            command,
            cwd=source_dir,
            env=self.environment(),
            capture_output=True,
            text=True,
            errors="replace",
        )
        elapsed = time.time() - started

        pdf = os.path.join(outdir, job + ".pdf")
        log = os.path.join(outdir, job + ".log")
        log_text = ""
        if os.path.isfile(log):
            with open(log, encoding="utf-8", errors="replace") as handle:
                log_text = handle.read()

        diagnostics = parse_log(log_text) if log_text else []
        ok = os.path.isfile(pdf) and completed.returncode == 0

        if not ok and not any(d.severity == "error" for d in diagnostics):
            # latexmk failed without LaTeX reporting anything: a missing
            # binary, a permissions problem, a killed process. Surface its own
            # message rather than an empty error list.
            detail = (completed.stderr or completed.stdout or "").strip()
            diagnostics.append(
                Diagnostic("error", detail[-400:] or "%s failed" % self.engine)
            )

        if not keep_aux and ok:
            self._prune_aux(outdir, job)

        return BuildResult(
            document=document_id,
            profile=profile.id,
            language=language,
            ok=ok,
            pdf=pdf if os.path.isfile(pdf) else None,
            log=log if os.path.isfile(log) else None,
            pages=page_count(log_text),
            seconds=elapsed,
            diagnostics=diagnostics,
            command=command,
        )

    def _write_injection(self, outdir, document_title, course_keys):
        """Write the metadata the structure files know, for LaTeX to \input.

        Returns the path, or None when there is nothing to inject.
        """
        pieces = []
        if course_keys:
            pieces.append("\\DidactaCourse{\n  %s,\n}" % course_keys.rstrip(", "))
        if document_title:
            pieces.append("\\DidactaDocument{%s}" % document_title)
        if not pieces:
            return None

        path = os.path.join(outdir, "didacta-inject.tex")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(
                "%% Generated by Didacta. Do not edit.\n"
                "%% Course and document metadata for this build, taken from\n"
                "%% course.yaml and year.yaml so the source file does not have\n"
                "%% to repeat it in every language.\n"
                + "\n".join(pieces) + "\n"
            )
        return path

    def _command(self, source_name, job, outdir, profile, language,
                 content_root, inject=None):
        pretex = profile.pretex(language, content_root)
        if inject:
            # Absolute: the working directory is the source's directory, not
            # the output directory.
            pretex += "\\def\\DidactaInjectFile{%s}" % os.path.abspath(inject)

        if self.engine == "latexmk":
            # latexmk decides how many passes are needed. `-g` forces a run
            # even when it thinks nothing changed, which matters because the
            # profile is injected on the command line and latexmk cannot see
            # that it differs from last time.
            inner = (
                "pdflatex %O -interaction=nonstopmode -synctex=1 "
                '"' + pretex + '\\input{%S}"'
            )
            return [
                "latexmk", "-pdf", "-g",
                "-interaction=nonstopmode",
                "-jobname=" + job,
                "-outdir=" + outdir,
                "-pdflatex=" + inner,
                source_name,
            ]

        # Bare pdflatex, for a quick single pass when cross-references and the
        # slide total do not matter yet.
        return [
            "pdflatex",
            "-interaction=nonstopmode",
            "-synctex=1",
            "-jobname=" + job,
            "-output-directory=" + outdir,
            pretex + "\\input{" + source_name + "}",
        ]

    #: Auxiliaries worth deleting after a successful build. The PDF and the log
    #: stay: the log is what the UI reports from, and SyncTeX is what makes the
    #: PDF clickable.
    AUX_SUFFIXES = (
        ".aux", ".toc", ".out", ".nav", ".snm", ".vrb",
        ".fls", ".fdb_latexmk", ".bbl", ".blg", ".bcf", ".run.xml",
    )

    def _prune_aux(self, outdir, job):
        for suffix in self.AUX_SUFFIXES:
            path = os.path.join(outdir, job + suffix)
            if os.path.isfile(path):
                try:
                    os.remove(path)
                except OSError:
                    pass

    # -- batches ---------------------------------------------------------

    def build_many(self, jobs, on_result=None):
        """Run a list of ``(source, profile, language, kwargs)`` jobs in order.

        Sequential on purpose. LaTeX is single-threaded and memory-hungry, and
        the useful parallelism is one process per job at the CI level, not
        threads here.
        """
        results = []
        for source, profile, language, extra in jobs:
            try:
                result = self.build(source, profile, language, **extra)
            except BuildError as exc:
                result = BuildResult(
                    document=extra.get("document_id") or os.path.basename(source),
                    profile=profile if isinstance(profile, str) else profile.id,
                    language=language,
                    ok=False,
                    diagnostics=[Diagnostic("error", str(exc))],
                )
            results.append(result)
            if on_result:
                on_result(result)
        return results

    def clean(self, document_id=None):
        """Remove build output. Never touches the content repository."""
        target = self.build_dir
        if document_id:
            target = os.path.join(self.build_dir, document_id.replace("/", "_"))
        if os.path.isdir(target):
            shutil.rmtree(target)
            return target
        return None
