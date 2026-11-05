"""Checks private.txt and public_ok.txt against the files of a commit.

Run by tool/export_public_source.sh from the repository root before anything
is removed from the snapshot:

    git ls-tree -r --name-only HEAD | python3 -I tool/public_source/check_paths.py [<folder of the lists>]

Two mistakes make private code public without anyone noticing:

1. An entry of private.txt no longer matches anything, because the file was
   renamed or moved: the new path is simply exported. Every entry must match a
   file of the commit, or be ignored by git (the store folder never enters a
   commit).
2. A new file of a private part lands outside the listed paths. Every file
   whose path names a private part (KEYWORDS) must either be private or be
   listed in public_ok.txt, after deciding that it may be public.

Entries are paths or folders; public_ok.txt also takes shell patterns
(fnmatch, `*` crosses folders). The lists are read from the given folder (the
snapshot's copy, so they match the commit), by default next to this script.
Exits 1 with the findings.
"""
from __future__ import annotations

import fnmatch
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
KEYWORDS = re.compile(
    r'cloud_sync|cloudsync|knxcloud|account|konto|team|betrieb|home_plan|paddle|licen[cs]e|web_shop|store_plan',
    re.IGNORECASE,
)


def entries(folder: pathlib.Path, name: str) -> list[str]:
    lines = (folder / name).read_text(encoding='utf-8').splitlines()
    return [line.strip().rstrip('/') for line in lines if line.strip() and not line.lstrip().startswith('#')]


def covers(entry: str, path: str) -> bool:
    if any(c in entry for c in '*?['):
        return fnmatch.fnmatchcase(path, entry)
    return path == entry or path.startswith(entry + '/')


def ignored(entry: str) -> bool:
    for candidate in (entry, entry + '/'):
        if subprocess.run(['git', 'check-ignore', '-q', '--no-index', candidate]).returncode == 0:
            return True
    return False


def main() -> int:
    folder = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE
    files = [line for line in sys.stdin.read().splitlines() if line]
    private = entries(folder, 'private.txt')
    public_ok = entries(folder, 'public_ok.txt')
    problems = []

    for entry in private:
        if any(c in entry for c in '*?['):
            problems.append(f'private.txt: no patterns, list the path itself: {entry}')
        elif not any(covers(entry, f) for f in files) and not ignored(entry):
            problems.append(f'private.txt: {entry} does not exist (renamed or moved? list the new path)')

    for entry in public_ok:
        if not any(covers(entry, f) for f in files):
            problems.append(f'public_ok.txt: {entry} does not exist (remove the entry)')

    for f in files:
        if not KEYWORDS.search(f) or any(covers(p, f) for p in private):
            continue
        if not any(covers(p, f) for p in public_ok):
            problems.append(
                f'{f}: name of a private part, but neither in private.txt nor in public_ok.txt (decide and list it)'
            )

    for line in problems:
        print(f'  {line}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
