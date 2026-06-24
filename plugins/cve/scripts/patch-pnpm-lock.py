#!/usr/bin/env python3
"""Patch a package version in a pnpm-lock.yaml file.

Usage: patch-pnpm-lock.py <lockfile> <package> <old-version> <new-version>

Updates version references in the lockfile. Does not update integrity
hashes — run `pnpm install --frozen-lockfile` after patching to validate,
or use lockfile-only update commands when possible.
"""
import re
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(f"Usage: {sys.argv[0]} <lockfile> <package> <old> <new>")

    lockfile, pkg, old, new = sys.argv[1:5]
    path = Path(lockfile)
    text = path.read_text()

    if f"{pkg}@{new}" in text and f"{pkg}@{old}" not in text:
        print(f"already at {pkg}@{new}")
        return

    if f"{pkg}@{old}" not in text:
        raise SystemExit(f"ERROR: {pkg}@{old} not found in {lockfile}")

    text = text.replace(f"{pkg}@{old}", f"{pkg}@{new}")
    text = re.sub(rf"({re.escape(pkg)}:\s*){re.escape(old)}\b", rf"\g<1>{new}", text)
    path.write_text(text)
    print(f"patched {pkg} {old} -> {new} in {lockfile}")


if __name__ == "__main__":
    main()
