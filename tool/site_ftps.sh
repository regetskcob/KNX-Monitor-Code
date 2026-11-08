#!/usr/bin/env bash
# Uploads a built static site to the webspace at do.de over FTPS (explicit TLS)
# and sends only what changed since the last upload.
#
#   tool/site_ftps.sh <built folder> <keychain service> [--keep <dir>]... [--dry-run]
#
# Access comes from the login keychain, never from the repository or the shell
# history. One item per FTP user, the host in its comment:
#
#   security add-generic-password -s busclear-ftp -a <ftp user> -j <ftp host> -w
#
# What is on the server is described by .deploy-manifest (SHA-256 and path of
# every file) in the target folder; the .htaccess answers 404 for it. Files whose
# hash differs are uploaded, files no longer built are deleted. A folder named
# with --keep stays on the server when this build has none of its own (the social
# page, built only in the main checkout from the private store/).
#
# --dry-run prints the plan against the manifest on the server, or against an
# empty server with DRY_RUN_OFFLINE=1, and changes nothing.
#
# Needs lftp (brew install lftp). The FTP server at do.de (ProFTPD) wants TLS on
# the data channel with session reuse; lftp does that, see ftp:ssl-* below.
set -euo pipefail

src=${1:?built folder}
service=${2:?keychain service}
shift 2
keep=()
dry=false
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) keep+=("${2:?folder}"); shift 2 ;;
    --dry-run) dry=true; shift ;;
    *) echo "site_ftps: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -d "$src" ] || { echo "site_ftps: no folder $src" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Manifest of the build: "<sha256>  ./<path>", sorted by path.
(cd "$src" && find . -type f ! -name .deploy-manifest -print0 | sort -z | xargs -0 shasum -a 256) >"$work/local"

offline=${DRY_RUN_OFFLINE:-}
host="" user=""
if ! { $dry && [ -n "$offline" ]; }; then
  command -v lftp >/dev/null || { echo "site_ftps: lftp missing (brew install lftp)" >&2; exit 1; }
  meta=$(security find-generic-password -s "$service" 2>/dev/null) \
    || { echo "site_ftps: no keychain item $service (see the head of this script)" >&2; exit 1; }
  user=$(sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p' <<<"$meta")
  host=$(sed -n 's/^ *"icmt"<blob>="\(.*\)"$/\1/p' <<<"$meta")
  [ -n "$user" ] && [ -n "$host" ] || { echo "site_ftps: keychain item $service needs account and comment (host)" >&2; exit 1; }
  LFTP_PASSWORD=$(security find-generic-password -s "$service" -w)
  export LFTP_PASSWORD
fi

settings() {
  cat <<'EOF'
set cmd:fail-exit true
set net:max-retries 3
set net:timeout 30
set ftp:ssl-force true
set ftp:ssl-protect-data true
set ftp:ssl-protect-list true
set ftp:passive-mode true
set ssl:verify-certificate true
set xfer:clobber on
EOF
  printf 'open --env-password -u %q %q\n' "$user" "$host"
}

# Manifest on the server (empty on the first upload).
: >"$work/remote"
if [ -z "$offline" ]; then
  { settings; echo "get .deploy-manifest -o $work/remote"; } >"$work/fetch.lftp"
  if lftp -f "$work/fetch.lftp" >/dev/null 2>&1; then :; else : >"$work/remote"; fi
fi

# Folders to keep: their server entries go into the new manifest unchanged.
: >"$work/kept"
for k in ${keep[@]+"${keep[@]}"}; do
  if [ ! -e "$src/$k" ]; then
    grep -F "  ./$k/" "$work/remote" >>"$work/kept" || true
    echo "keeping $k/ as published"
  fi
done

path_of() { sed 's/^[0-9a-f]*  //'; }
# Upload: lines of the build that the server does not have with this hash.
comm -23 <(sort "$work/local") <(sort "$work/remote") | path_of | sort >"$work/put"
# Delete: paths on the server that the build and the kept folders no longer have.
comm -23 <(path_of <"$work/remote" | sort) <(cat "$work/local" "$work/kept" | path_of | sort) >"$work/rm"
cat "$work/local" "$work/kept" | sort -k2 >"$work/manifest"

echo "$(wc -l <"$work/put" | tr -d ' ') to upload, $(wc -l <"$work/rm" | tr -d ' ') to delete, $(wc -l <"$work/local" | tr -d ' ') files built"
if $dry; then
  sed 's/^/  put /' "$work/put"
  sed 's/^/  rm  /' "$work/rm"
  exit 0
fi

{
  settings
  # Folders first, then the files, the manifest last: an aborted upload is
  # repeated in full next time, because the old manifest still stands.
  path_of <"$work/local" | sed 's|/[^/]*$||' | grep -v '^\.$' | sort -u | while read -r d; do
    printf 'mkdir -p -f %q\n' "$d"
  done
  while read -r f; do printf 'put %q -o %q\n' "$src/$f" "$f"; done <"$work/put"
  while read -r f; do printf 'rm -f %q\n' "$f"; done <"$work/rm"
  printf 'put %q -o .deploy-manifest\n' "$work/manifest"
} >"$work/upload.lftp"
lftp -f "$work/upload.lftp"
echo "uploaded to $host"
