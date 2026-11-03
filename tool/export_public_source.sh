#!/usr/bin/env bash
# Builds the public source snapshot of KNX Monitor (GPLv3) from HEAD: every
# tracked file except what stays private (tool/public_source/private.txt:
# backend, account, Betriebslösung, home planner, notes for Claude). The
# release workflows stay public on purpose: they show how the images are built
# and can only publish from the main repository with its permissions. Checks
# the result for secrets and that it builds without the private parts. Pushes
# nothing: publishing is a separate, deliberate step, see
# tool/sync_public_source.sh.
#
#   tool/export_public_source.sh <empty target directory> [--no-build]
set -euo pipefail
cd "$(dirname "$0")/.."

target=${1:?usage: $0 <empty target directory> [--no-build]}
build=1
[ "${2:-}" = --no-build ] && build=0
mkdir -p "$target"
[ -z "$(ls -A "$target")" ] || { echo "$target is not empty" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || echo "note: uncommitted changes are not part of the snapshot" >&2

# What stays private, and the stubs that replace private code the open app
# calls: tool/public_source/.
list=tool/public_source/private.txt
stubs=tool/public_source/stubs
git archive --format=tar HEAD | tar -x -C "$target"
# Both from the snapshot, so they match HEAD.
PRIVATE=()
while IFS= read -r line; do
  case "$line" in '' | '#'*) continue ;; esac
  PRIVATE+=("$line")
done <"$target/$list"
for p in "${PRIVATE[@]}"; do rm -rf "${target:?}/${p:?}"; done
# Asset folders that stay private leave the asset list too.
for p in "${PRIVATE[@]}"; do
  case "$p" in assets/*) sed -i.bak "\#^ *- ${p%/}/\$#d" "$target/pubspec.yaml" && rm "$target/pubspec.yaml.bak" ;; esac
done
# Stubs: same interface, everything off. Copied without the .stub suffix.
(cd "$target/$stubs" && find . -name '*.stub' -type f) | while IFS= read -r f; do
  dest="$target/${f#./}"
  mkdir -p "$(dirname "$dest")"
  cp "$target/$stubs/$f" "${dest%.stub}"
done
# Texts of the private parts leave the translations as well.
(cd "$target" && python3 -I tool/public_source/strip_l10n.py && flutter gen-l10n >/dev/null)
echo "snapshot of $(git rev-parse --short HEAD): $(find "$target" -type f | wc -l | tr -d ' ') files in $target"

fail=0
say() { printf '%s\n' "$*"; }

say "Secrets"
# Patterns for keys and tokens of the services KNX Monitor uses. A hit stops
# the release until it is removed and the secret rotated.
if grep -rnIE 'BEGIN ((RSA|EC|OPENSSH) )?PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_|sk_(live|test)_[A-Za-z0-9]{10,}|AIza[0-9A-Za-z_-]{35}|eyJhbGciOi[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|pdl_(live|sdbx)_|appl_[A-Za-z0-9]{20,}|goog_[A-Za-z0-9]{20,}|sb_secret_' \
  --exclude='*.lock' --exclude=export_public_source.sh "$target"; then
  say "  secrets found"
  fail=1
fi
if find "$target" -type f \( -iname '*.jks' -o -iname '*.keystore' -o -iname '*.p12' -o -iname '*.p8' \
  -o -iname '*.pem' -o -iname '*.mobileprovision' -o -iname 'key.properties' -o -iname '.env' \) | grep .; then
  say "  key files found"
  fail=1
fi
if command -v gitleaks >/dev/null; then
  gitleaks dir --no-banner --config "$target/tool/public_source/gitleaks.toml" "$target" || fail=1
else
  say "  gitleaks not installed, only the patterns above were checked"
fi

say "Private references in scripts and workflows"
# Scripts must not need what stays private; comments elsewhere may mention it.
for p in "${PRIVATE[@]}"; do
  [ "$p" = CLAUDE.md ] || [ "$p" = .claude ] && continue
  case $p in *.*) pattern=$p ;; *) pattern=$p/ ;; esac
  grep -rlF --exclude=export_public_source.sh --exclude='*.md' --exclude=private.txt "$pattern" "$target/.github" "$target/tool" "$target/box" 2>/dev/null |
    sed "s#^#  refers to $p: #" || true
done

if [ "$build" = 1 ]; then
  say "Build without private parts"
  # Without the private parts some screens look different (no home planner
  # entry): the goldens of the public snapshot show the public app.
  (cd "$target" && flutter pub get >/dev/null && flutter test --tags golden --update-goldens >/dev/null &&
    git init -q && git add -A && git -c user.name=export -c user.email=export@localhost commit -qm snapshot &&
    tool/release.sh verify) || fail=1
fi

if [ "$fail" != 0 ]; then
  say "snapshot NOT ok"
  exit 1
fi
say "snapshot ok"
