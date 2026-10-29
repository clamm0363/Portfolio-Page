"""Exercise startup twice with a local Git fixture and fake apk/nginx (no network)."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASH = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe"
GIT = shutil.which("git")


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)


def unix(path):
    return run([str(BASH), "-c", 'cygpath -u "$1"', "--", str(path)]).stdout.strip()


def main():
    assert BASH.is_file(), "Use installed Git for Windows Bash; WSL is not required."
    assert GIT
    run([str(BASH), "-n", str(ROOT / "scripts/start-site.sh")])
    (ROOT / ".local").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="startup-test-", dir=ROOT / ".local") as tmp:
        base = Path(tmp)
        repo = base / "repo"
        (repo / "assets").mkdir(parents=True)
        (repo / "nginx").mkdir()
        (repo / "index.html").write_text("<html>fixture</html>", encoding="utf-8")
        (repo / "assets/current.png").write_bytes(b"fixture-image")
        (repo / "nginx/nginx.conf").write_text("fixture config", encoding="utf-8")
        run([GIT, "init", str(repo)])
        run([GIT, "-C", str(repo), "add", "index.html", "assets", "nginx"])
        run([GIT, "-C", str(repo), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
             "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture"])
        sha = run([GIT, "-C", str(repo), "rev-parse", "HEAD"]).stdout.strip()
        html = base / "html"
        html.mkdir()
        config = base / "nginx.conf"
        scratch = base / "scratch"
        commands = base / "bin"
        commands.mkdir()
        (commands / "apk").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8", newline="\n")
        (commands / "nginx").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8", newline="\n")
        (commands / "git").write_text(
            '#!/bin/sh\nif [ "$1" = "-C" ] && [ "$3" = "remote" ]; then\n'
            'exec "$FIXTURE_REAL_GIT" -C "$2" remote add origin "$FIXTURE_REPO"\nfi\n'
            'exec "$FIXTURE_REAL_GIT" "$@"\n', encoding="utf-8", newline="\n")
        source = (ROOT / "scripts/start-site.sh").read_text(encoding="utf-8")
        source = source.replace("/tmp/portfolio-source", unix(scratch))
        source = source.replace("/usr/share/nginx/html", unix(html))
        source = source.replace("/etc/nginx/nginx.conf", unix(config))
        runner = base / "start.sh"
        runner.write_text(source, encoding="utf-8", newline="\n")
        env = os.environ.copy()
        env.update(PORTFOLIO_COMMIT=sha, FIXTURE_REAL_GIT=unix(GIT), FIXTURE_REPO=unix(repo))
        # Git Bash constructs PATH on startup; prepend fixtures inside that shell.
        cmd = [str(BASH), "-c", 'export PATH="$1:$PATH"; exec /bin/sh "$2"', "--", unix(commands), unix(runner)]
        run(cmd, env=env)
        assert (html / "index.html").read_text() == "<html>fixture</html>"
        assert json.loads((html / "release.json").read_text())["commit"] == sha
        (html / "assets/stale.png").write_bytes(b"obsolete")
        run(cmd, env=env)
        assert not (html / "assets/stale.png").exists(), "Restart must not retain removed assets"
        assert (html / "assets/current.png").read_bytes() == b"fixture-image"
        assert not scratch.exists(), "Clone directory must be cleaned"
        env["PORTFOLIO_COMMIT"] = "main"
        invalid = subprocess.run(cmd, env=env, capture_output=True, text=True)
        assert invalid.returncode != 0, "Moving/invalid refs must be rejected"
    print("PASS: shell syntax, local-only startup/restart, stale asset removal, release marker, invalid SHA rejection.")


if __name__ == "__main__":
    main()
