"""Builds release/leAlts-<version>.zip from the committed addon files.

The version comes from ## Version in leAlts/leAlts.toc. Only files tracked by git
under leAlts/ go in, so the zip matches what's committed. Run from anywhere:
    python3 tools/make_release.py
"""
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    with open(os.path.join(ROOT, "leAlts", "leAlts.toc"), encoding="utf-8") as f:
        match = re.search(r"^## Version:\s*(\S+)", f.read(), re.M)
    if not match:
        sys.exit("No ## Version in the .toc")
    version = match.group(1)
    files = subprocess.check_output(["git", "-C", ROOT, "ls-files", "leAlts"], text=True).split()
    os.makedirs(os.path.join(ROOT, "release"), exist_ok=True)
    out = os.path.join(ROOT, "release", f"leAlts-{version}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(files):
            z.write(os.path.join(ROOT, name), name)
    print(f"{os.path.relpath(out, ROOT)}: {len(files)} files, {os.path.getsize(out)} bytes")


if __name__ == "__main__":
    main()
