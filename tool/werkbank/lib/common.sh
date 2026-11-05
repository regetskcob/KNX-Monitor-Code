# Shared functions of the werkbank CLI. Sourced by bin/werkbank; a project's
# tool/release.sh may source it too (after wb_enter_repo / wb_load_conf the
# wb_* functions work there the same way).
# shellcheck shell=bash
# wb_version takes an optional part (name, build); calls without one are meant.
# shellcheck disable=SC2119,SC2120

# This folder: helpers next to it (play_upload.py).
WB_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Where this werkbank lives: tool/werkbank/ inside a project, or a checkout
# of the werkbank repository itself.
WB_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The project root, so every path below is relative to it: the repository
# that holds this copy (tool/werkbank/), whatever the current directory; for
# the werkbank checkout itself the repository of the current directory.
wb_enter_repo() {
  local root
  if [ "$(basename "$WB_HOME")" = werkbank ] && [ "$(basename "$(dirname "$WB_HOME")")" = tool ]; then
    root=$(cd "$WB_HOME/../.." && pwd)
  else
    root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
  fi
  cd "$root" || die "cannot enter $root"
}

# Defaults, then tool/werkbank.conf of the project. Everything in the conf is
# optional; see STANDARD.md, "werkbank.conf".
wb_load_conf() {
  WB_APP=""
  WB_TOP_EXTRA=""
  WB_MEDIA_EXTRA=""
  WB_FORMAT_PATHS=""
  WB_TEST_ARGS=""
  WB_ANALYZE_ARGS=""
  WB_SYMBOLS_DIR=""
  WB_SITE_DIRS=""
  WB_APP_TAG_PREFIX="v"
  WB_STORE_LANGS="de-DE en-US"
  WB_PLAY_PACKAGE=""
  WB_PLAY_KEY=""
  WB_PLAY_TRACK="internal"
  WB_PLAY_STATUS="completed"
  WB_DEVICETEST_TARGETS=""
  WB_PRODUCTS="app"
  WB_CHANGELOG="CHANGELOG.md"
  WB_CHANGELOG_LANGS="en de"
  WB_GH_RELEASE_REPO=""
  WB_SITES=""
  WB_RELEASE_SITES=""
  if [ -f tool/werkbank.conf ]; then
    # shellcheck disable=SC1091
    . tool/werkbank.conf
  fi
  [ -n "$WB_APP" ] || WB_APP=$(sed -n 's/^name: *//p' pubspec.yaml 2>/dev/null | head -1)
  [ -n "$WB_APP" ] || WB_APP=$(basename "$PWD")
  [ -n "$WB_SYMBOLS_DIR" ] || WB_SYMBOLS_DIR="$HOME/keys/symbols/$WB_APP"
  [ -n "$WB_PLAY_KEY" ] || WB_PLAY_KEY="$HOME/keys/$WB_APP-play.json"
  if [ -z "$WB_SITE_DIRS" ] && [ -f site/hugo.toml ]; then WB_SITE_DIRS=site; fi
  if [ -z "$WB_FORMAT_PATHS" ]; then
    local dir
    for dir in lib test integration_test test_driver; do
      if [ -d "$dir" ]; then WB_FORMAT_PATHS="${WB_FORMAT_PATHS:+$WB_FORMAT_PATHS }$dir"; fi
    done
  fi
}

# Whether the project defined the hook function $1 in its conf.
wb_has_hook() { declare -F "$1" >/dev/null; }

# Sources an env file (secrets kept outside the repository, usually
# ~/.config/<app>/<name>.env) if it exists; returns 1 if it does not.
wb_env_file() {
  [ -f "$1" ] || return 1
  # shellcheck disable=SC1090
  . "$1"
}

# ---------------------------------------------------------------------------
# Folder structure

# Top-level entries every app repository may have (STANDARD.md, "Ordnerstruktur").
WB_TOP_BASE='\.claude|\.github|\.gitignore|\.gitattributes|\.metadata|\.vscode|\.mcp\.json|CLAUDE\.md|README\.md|LICENSE|CONTRIBUTING\.md|SECURITY\.md|TRADEMARKS\.md|CHANGELOG(\.[a-z]{2})?\.md|analysis_options\.yaml|dart_test\.yaml|build\.yaml|l10n\.yaml|pubspec\.(yaml|lock)|Gemfile(\.lock)?|package(-lock)?\.json|android|ios|macos|linux|windows|tvos|watchos|web|lib|test|integration_test|test_driver|assets|docs|tool|store|site|supabase'
# Where images, PDFs, videos, models, archives and app binaries may live.
WB_MEDIA_BASE='(android|ios|macos|linux|windows|tvos|watchos|web|assets|store)/|site/(static|assets)/|docs/(images|pdf)/|(test|integration_test)/(.*/)?goldens/'
WB_MEDIA_EXT='png|jpe?g|gif|webp|heic|psd|pdf|mp4|mov|stl|step|3mf|zip|xz|aab|apk|ipa'

wb_layout() {
  local top_re="^(${WB_TOP_BASE}${WB_TOP_EXTRA:+|$WB_TOP_EXTRA})$"
  local media_re="^(${WB_MEDIA_BASE}${WB_MEDIA_EXTRA:+|$WB_MEDIA_EXTRA})"
  local files top media
  # Tracked files plus new ones not yet added (but not ignored ones), so a
  # local verify catches a misplaced file before the commit.
  files=$(git ls-files; git ls-files --others --exclude-standard)
  top=$(cut -d/ -f1 <<<"$files" | sort -u | grep -vE "$top_re" || true)
  media=$(grep -iE "\\.(${WB_MEDIA_EXT})\$" <<<"$files" | grep -vE "$media_re" || true)
  # Both lists at once, so one run shows everything to move.
  [ -z "$top" ] || printf '\033[1;31merror:\033[0m unknown top-level entries (STANDARD.md, Ordnerstruktur): %s\n' "$(tr '\n' ' ' <<<"$top")" >&2
  [ -z "$media" ] || printf '\033[1;31merror:\033[0m media outside their folders (STANDARD.md, Ordnerstruktur): %s\n' "$(tr '\n' ' ' <<<"$media")" >&2
  [ -z "$top$media" ] || exit 1
}

# ---------------------------------------------------------------------------
# Checks

# The checks of the pull request CI, run before every push. Project hooks:
# verify_quick_extra runs always (checks the CI runs too, e.g. other test
# suites), verify_extra only without --quick (builds and other slow steps).
wb_verify() {
  local quick=false
  [ "${1:-}" = --quick ] && quick=true
  say "Layout"
  wb_layout
  say "Dependencies"
  flutter pub get >/dev/null
  if [ -f l10n.yaml ]; then
    say "Translations"
    flutter gen-l10n >/dev/null
    local dir
    dir=$(sed -n 's/^output-dir: *//p' l10n.yaml)
    [ -n "$dir" ] || dir=$(sed -n 's/^arb-dir: *//p' l10n.yaml)
    [ -n "$dir" ] || dir=lib/l10n
    git diff --exit-code --quiet -- "$dir" || die "$dir out of date – run flutter gen-l10n and commit"
  fi
  say "Format"
  # shellcheck disable=SC2086
  dart format --output=none --set-exit-if-changed $WB_FORMAT_PATHS >/dev/null ||
    die "unformatted files – run dart format $WB_FORMAT_PATHS"
  say "Analyze"
  # shellcheck disable=SC2086
  flutter analyze --no-pub $WB_ANALYZE_ARGS
  say "Tests"
  # shellcheck disable=SC2086
  flutter test --no-pub $WB_TEST_ARGS
  if wb_has_hook verify_quick_extra; then
    verify_quick_extra
  fi
  if $quick; then
    say "Quick check green"
    return 0
  fi
  if wb_has_hook verify_extra; then
    verify_extra
  fi
  wb_site_check
  say "All green"
}

# ---------------------------------------------------------------------------
# Version

wb_version() {
  local v
  v=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
  [ -n "$v" ] || die "no version in pubspec.yaml"
  case "${1:-}" in
    name) echo "${v%%+*}" ;;
    build) [[ "$v" == *+* ]] && echo "${v##*+}" || echo "" ;;
    "") echo "$v" ;;
    *) die "werkbank version [name|build]" ;;
  esac
}

# ---------------------------------------------------------------------------
# Release builds

# A keytool that really runs: /usr/bin/keytool on macOS is a stub that prints
# nothing without a system Java, so a signature check would always pass.
wb_keytool() {
  local candidate
  for candidate in "${JAVA_HOME:+$JAVA_HOME/bin/keytool}" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
    "$(command -v keytool || true)"; do
    if [ -n "$candidate" ] && "$candidate" -help >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  die "no working keytool – install Android Studio or set JAVA_HOME to a JDK"
}

# Fails unless the bundle or APK $1 is signed, and not with the debug key.
wb_check_signature() {
  local keytool signer
  keytool=$(wb_keytool)
  # English output whatever the system language ("Eigentümer:" otherwise).
  signer=$("$keytool" -J-Duser.language=en -printcert -jarfile "$1" 2>&1 | sed -n 's/^Owner: //p' | head -1)
  [ -n "$signer" ] || die "$1 is not signed"
  [[ "$signer" != *"Android Debug"* ]] || die "$1 is signed with the debug key – check android/key.properties"
}

# Copies build/symbols/<platform> (from --split-debug-info) to
# $WB_SYMBOLS_DIR/<version>/<platform>: build/ is wiped by flutter clean, the
# symbols are needed to read crash reports of exactly this build.
wb_symbols() {
  local platform=$1 target
  [ -d "build/symbols/$platform" ] || return 0
  target="$WB_SYMBOLS_DIR/$(wb_version)"
  mkdir -p "$target"
  rm -rf "${target:?}/$platform"
  cp -R "build/symbols/$platform" "$target/$platform"
  say "Debug symbols kept in $target/$platform"
}

# Release file name: build/release/<app>[-<variant>]-<version>.<ext>; the
# variant tells apart several bundles of one version (phone, wear, …).
wb_release_path() { echo "build/release/$WB_APP${2:+-$2}-$(wb_version).$1"; }

# Package.resolved of the Apple platforms (SwiftPM) that differ from HEAD,
# new ones included. A store build (flutter build ipa/macos, xcodebuild archive)
# resolves the Swift packages again and may rewrite them – then the checkout is
# dirty and the next release step refuses with "uncommitted changes".
wb_resolved_changed() {
  git status --porcelain --untracked-files=all -- ':(glob)ios/**/Package.resolved' ':(glob)macos/**/Package.resolved' | cut -c4-
}

# After a store build: fails while it left a changed Package.resolved, before
# anything is uploaded or tagged. The build used exactly these versions, so they
# belong in the repository – committed via PR, then the build is repeated from
# the clean main (STANDARD.md, Release).
#
# Hooks that build and upload themselves (release_<product>, build_<platform>)
# must call it between their build and their upload: werkbank checks again only
# after the hook returns, when it can still stop the tag but no longer the
# upload. That late check passes "after-hook" and says so.
wb_resolved_guard() {
  local files
  files=$(wb_resolved_changed)
  [ -z "$files" ] && return 0
  local f outcome="nothing was uploaded or tagged"
  [ "${1:-}" = after-hook ] && outcome="nothing was tagged; if the hook uploaded without calling wb_resolved_guard first, that build is already in the store"
  while IFS= read -r f; do printf '  %s\n' "$f" >&2; done <<<"$files"
  die "the build resolved the Swift packages anew (Package.resolved above) – commit them via PR (\"Swift-Pakete wie beim Store-Build aufgelöst\"), then build again from the clean main; $outcome"
}

# Signed App Bundle. Arguments after -- go to flutter build appbundle, after
# those of the project's android_args hook.
wb_android() {
  [ "${1:-}" = -- ] && shift
  [ -f android/key.properties ] || die "android/key.properties missing – without it Gradle signs with the debug key (STANDARD.md, Schlüssel)"
  local args=()
  if wb_has_hook android_args; then
    # shellcheck disable=SC2207
    args=($(android_args))
  fi
  wb_notes_reminder
  say "App Bundle $(wb_version)"
  flutter build appbundle --release ${args[@]+"${args[@]}"} "$@"
  local aab=build/app/outputs/bundle/release/app-release.aab
  [ -f "$aab" ] || die "no bundle at $aab"
  wb_check_signature "$aab"
  wb_symbols android
  local out
  out=$(wb_release_path aab)
  mkdir -p build/release
  cp "$aab" "$out"
  say "Signed bundle: $out"
}

# IPA. --upload sends it to App Store Connect with an API key: ASC_KEY_ID,
# ASC_ISSUER_ID and the key file ASC_KEY_PATH (default
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8).
wb_ios() {
  local upload=false
  if [ "${1:-}" = --upload ]; then upload=true; shift; fi
  [ "${1:-}" = -- ] && shift
  if $upload; then wb_asc_key >/dev/null; fi
  local args=()
  if wb_has_hook ios_args; then
    # shellcheck disable=SC2207
    args=($(ios_args))
  fi
  wb_notes_reminder
  say "IPA $(wb_version)"
  rm -rf build/ios/ipa
  flutter build ipa --release ${args[@]+"${args[@]}"} "$@"
  local ipa
  ipa=$(find build/ios/ipa -maxdepth 1 -name '*.ipa' | head -1)
  [ -n "$ipa" ] || die "no IPA in build/ios/ipa"
  wb_symbols ios
  local out
  out=$(wb_release_path ipa)
  mkdir -p build/release
  cp "$ipa" "$out"
  say "IPA: $out"
  wb_resolved_guard
  if $upload; then
    say "Uploading to App Store Connect"
    API_PRIVATE_KEYS_DIR=$(dirname "$(wb_asc_key)") \
      xcrun altool --upload-app --type ios -f "$out" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  else
    say "Not uploaded – werkbank ios --upload, Transporter, or Xcode (build/ios/archive/Runner.xcarchive → Distribute App)"
  fi
}

# Takes a bundle built elsewhere (e.g. by fastlane) into build/release/: an
# AAB/APK is checked against the debug key first. $1: aab, apk or ipa, $2:
# path, $3: optional variant for the file name.
wb_collect() {
  local ext=${1:?aab, apk or ipa} src=${2:?path to the file} variant=${3:-} out
  [ -f "$src" ] || die "$src missing"
  case "$ext" in
    aab | apk) wb_check_signature "$src" ;;
    ipa) ;;
    *) die "werkbank collect aab|apk|ipa <path>" ;;
  esac
  out=$(wb_release_path "$ext" "$variant")
  mkdir -p build/release
  cp "$src" "$out"
  say "Release file: $out"
}

# Path of the App Store Connect API key; fails with what is missing.
wb_asc_key() {
  [ -n "${ASC_KEY_ID:-}" ] || die "ASC_KEY_ID missing (App Store Connect → Users and Access → Integrations → Keys)"
  [ -n "${ASC_ISSUER_ID:-}" ] || die "ASC_ISSUER_ID missing"
  local key="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
  [ -f "$key" ] || die "API key $key missing"
  [ "$(basename "$key")" = "AuthKey_$ASC_KEY_ID.p8" ] || die "altool needs the key file named AuthKey_$ASC_KEY_ID.p8, not $(basename "$key")"
  echo "$key"
}

# ---------------------------------------------------------------------------
# Store texts and uploads (STANDARD.md "Release-Texte")

# Release texts of build $1 (default: the build number of pubspec.yaml):
# TestFlight "What to test" per language and the Play release notes as one
# block for the Play Console. Fails when one is missing, still a draft, or
# too long. With --draft, missing files are created from the pull requests
# merged since the last app tag, marked ENTWURF until someone writes them.
wb_store_notes() {
  local draft=false
  if [ "${1:-}" = --draft ]; then draft=true; shift; fi
  local build=${1:-$(wb_version build)} lang file play missing=0
  [ -n "$build" ] || die "no build number in pubspec.yaml (version: 1.2.3+45)"
  play="store/android/play-notes-$build.txt"
  if $draft; then
    local since changes
    since=$(git describe --tags --abbrev=0 --match "${WB_APP_TAG_PREFIX}*" 2>/dev/null || true)
    # A GitHub merge has the pull request title as first body line, else the subject counts.
    changes=$({ git log --first-parent --merges --format='%s%x1f%b%x1e' ${since:+"$since..HEAD"} 2>/dev/null || true; } |
      awk 'BEGIN { RS = "\x1e"; FS = "\x1f" } { sub(/^\n+/, ""); if ($0 == "") next; split($2, body, "\n");
        t = body[1] != "" ? body[1] : $1; print "- " t }' | head -20)
    [ -n "$changes" ] || changes='- …'
    # Better than pull request titles: the changelog section of the language,
    # already written for users (de-DE ← CHANGELOG.de.md, en-US ← CHANGELOG.md).
    lang_changes() {
      local section
      section=$(wb_changelog_section_in "$(wb_version name)" "$(wb_changelog_file "${1%%-*}")")
      if [ -n "$section" ]; then grep -E '^- ' <<<"$section" || echo "$changes"; else echo "$changes"; fi
    }
    for lang in $WB_STORE_LANGS; do
      file="store/ios/testflight/whats_new_${build}_$lang.txt"
      [ -f "$file" ] && continue
      mkdir -p "$(dirname "$file")"
      printf 'ENTWURF – kürzen und für Tester formulieren, dann diese Zeile löschen.\n\n%s\n' "$(lang_changes "$lang")" >"$file"
      say "Draft: $file"
    done
    if [ ! -f "$play" ]; then
      mkdir -p "$(dirname "$play")"
      for lang in $WB_STORE_LANGS; do
        printf '<%s>\nENTWURF – auf 500 Zeichen kürzen\n%s\n</%s>\n' "$lang" "$(lang_changes "$lang")" "$lang"
      done >"$play"
      say "Draft: $play"
    fi
  fi
  for lang in $WB_STORE_LANGS; do
    file="store/ios/testflight/whats_new_${build}_$lang.txt"
    if [ ! -f "$file" ]; then
      warn "missing: $file"
      missing=1
    elif grep -q 'ENTWURF' "$file"; then
      warn "still a draft: $file"
      missing=1
    elif [ "$(wc -m <"$file")" -gt 4000 ]; then
      warn "$file is over 4000 characters (TestFlight)"
      missing=1
    fi
  done
  if [ ! -f "$play" ]; then
    warn "missing: $play"
    missing=1
  elif grep -q 'ENTWURF' "$play"; then
    warn "still a draft: $play"
    missing=1
  elif ! python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import play_upload; play_upload.parse_notes(open(sys.argv[2]).read(), sys.argv[3].split())' \
    "$WB_LIB" "$play" "$WB_STORE_LANGS" >/dev/null; then
    missing=1
  fi
  [ "$missing" = 0 ] || die "release texts of build $build incomplete (werkbank notes --draft creates drafts)"
  say "Release texts of build $build complete"
  cat "$play"
  if [ -z "${WB_NO_CLIPBOARD:-}" ] && command -v pbcopy >/dev/null; then
    pbcopy <"$play"
    say "Play notes in the clipboard"
  fi
}

# Every store build makes sure its release texts exist: drafts for what is
# missing, a loud warning while they are drafts. The upload refuses them then.
wb_notes_reminder() {
  if ! (WB_NO_CLIPBOARD=1 wb_store_notes --draft >/dev/null 2>&1); then
    warn "release texts of build $(wb_version build) are missing or drafts – fill store/…/*$(wb_version build)*, check with: werkbank notes"
  fi
}

# Sends an App Store archive (iOS, macOS, tvOS) to App Store Connect the way
# the Organizer's "Distribute App" does: xcodebuild signs with the Apple
# account signed in to Xcode, so no API key is needed. One retry: uploads
# break off now and then ("The network connection was lost").
wb_upload_apple() {
  local archive=${1:?path to the .xcarchive} team work
  [ -d "$archive" ] || die "$archive missing"
  team=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:Team' "$archive/Info.plist" 2>/dev/null || true)
  [ -n "$team" ] || die "no team in $archive/Info.plist – archive with signing"
  work=$(mktemp -d)
  cat >"$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
  say "Uploading $(basename "$archive") to App Store Connect (team $team)"
  local try
  for try in 1 2; do
    if xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$work/ExportOptions.plist" \
      -exportPath "$work/export" -allowProvisioningUpdates; then
      rm -rf "$work"
      say "Uploaded – TestFlight shows it after processing; the text: store/ios/testflight/"
      return 0
    fi
    [ "$try" = 1 ] && warn "upload failed, trying once more"
  done
  rm -rf "$work"
  die "upload failed twice – the archive is still there for the Organizer"
}

# Sends the App Bundle $1 (default: this version's release file) to the Play
# track $2 (default WB_PLAY_TRACK) with the release notes of this build.
# Needs a service account with access to the app (Play Console → Users and
# permissions), its JSON key at WB_PLAY_KEY, and WB_PLAY_PACKAGE.
wb_upload_play() {
  local aab=${1:-$(wb_release_path aab)} track=${2:-$WB_PLAY_TRACK}
  [ -n "$WB_PLAY_PACKAGE" ] || die "WB_PLAY_PACKAGE missing in tool/werkbank.conf (e.g. de.example.app)"
  [ -f "$WB_PLAY_KEY" ] || die "Play service account key $WB_PLAY_KEY missing (STANDARD.md, Schlüssel)"
  [ -f "$aab" ] || die "$aab missing – werkbank android first"
  wb_check_signature "$aab"
  local notes
  notes="store/android/play-notes-$(wb_version build).txt"
  [ -f "$notes" ] || die "$notes missing – werkbank notes --draft"
  grep -q ENTWURF "$notes" && die "$notes is still a draft"
  # The same checks as werkbank notes: every store language, at most 500 characters each.
  say "Uploading $(basename "$aab") to Play ($track)"
  python3 "$WB_LIB/play_upload.py" --key "$WB_PLAY_KEY" --package "$WB_PLAY_PACKAGE" --aab "$aab" \
    --track "$track" --status "$WB_PLAY_STATUS" --notes "$notes" --langs "$WB_STORE_LANGS" ${WB_DRY_RUN:+--dry-run}
}

# ---------------------------------------------------------------------------
# Landing pages (Hugo with the Horizont module, STANDARD.md "Landingpages")

# Builds every site of WB_SITE_DIRS into a throwaway folder (part of verify
# without --quick); skipped with a warning when hugo is missing.
wb_site_check() {
  local dir
  [ -n "$WB_SITE_DIRS" ] || return 0
  if ! command -v hugo >/dev/null; then
    warn "hugo missing – sites not checked"
    return 0
  fi
  for dir in $WB_SITE_DIRS; do
    say "Site $dir"
    hugo --quiet --source "$dir" --destination "$(mktemp -d)" >/dev/null
  done
}

# Builds the site in folder $1 for base URL $2 into build/site/<folder>/ and
# prints that path. Further arguments go to hugo.
wb_site_build() {
  local dir=${1:?site folder} url=${2:?base URL} out
  shift 2
  out="$PWD/build/site/$dir"
  rm -rf "$out"
  mkdir -p "$out"
  hugo --quiet --source "$dir" --minify --baseURL "$url" --destination "$out" --cleanDestinationDir "$@" >/dev/null
  echo "$out"
}

# Copies the built site $1 into the blog repository (WEBSITE_REPO, default
# ~/dev/website/regetskcob.github.io) under static/$2/, which serves it at
# www.regetskcob.de/$2/. Options: --keep <pattern> (rsync exclude, kept on the
# server side, repeatable), --push (commit and push the blog repository).
wb_site_blog() {
  local src=${1:?built site} sub=${2:?folder below static/} push=false web
  shift 2
  local keep=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) keep+=(--exclude "$2"); shift 2 ;;
      --push) push=true; shift ;;
      *) die "wb_site_blog: unknown option $1" ;;
    esac
  done
  web=${WEBSITE_REPO:-$HOME/dev/website/regetskcob.github.io}
  [ -d "$web/.git" ] || die "blog repository $web missing (WEBSITE_REPO)"
  mkdir -p "$web/static/$sub"
  rsync -a --delete ${keep[@]+"${keep[@]}"} "$src/" "$web/static/$sub/"
  say "Copied to $web/static/$sub ($(du -sh "$web/static/$sub" | cut -f1))"
  if $push; then
    git -C "$web" add "static/$sub"
    if git -C "$web" diff --cached --quiet -- "static/$sub"; then
      say "Blog repository unchanged – nothing to push"
      return 0
    fi
    git -C "$web" commit -q -m "$WB_APP: Landingpage aktualisieren"
    git -C "$web" push -q
    say "Blog repository pushed – GitHub Pages publishes it"
  fi
}

# ---------------------------------------------------------------------------
# Screenshots

# Finds the available simulator named $1 or creates it from device type $2
# with the newest runtime of family $3 (iOS, tvOS, watchOS), boots it and
# prints its UDID. Named simulators keep store shots on the same device.
wb_sim() {
  local name=${1:?name} type=${2:?device type} family=${3:-iOS} id runtime
  id=$(xcrun simctl list devices available | grep -F "    $name (" | head -1 |
    sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  if [ -z "$id" ]; then
    runtime=$(xcrun simctl list runtimes available | grep "^$family " | tail -1 | awk '{print $NF}')
    [ -n "$runtime" ] || die "no $family runtime installed (Xcode → Settings → Components)"
    id=$(xcrun simctl create "$name" "$type" "$runtime")
  fi
  xcrun simctl bootstatus "$id" -b >/dev/null
  echo "$id"
}

# ---------------------------------------------------------------------------
# Changelog (STANDARD.md "Changelog"): one format in every project

# The changelog of language $1: CHANGELOG.md for the first of
# WB_CHANGELOG_LANGS, CHANGELOG.<lang>.md for the others.
wb_changelog_file() {
  local first=${WB_CHANGELOG_LANGS%% *}
  if [ "$1" = "$first" ]; then echo "$WB_CHANGELOG"; else echo "${WB_CHANGELOG%.md}.$1.md"; fi
}

# Heading of unreleased changes per language.
wb_unreleased_heading() { case "$1" in de) echo "Unveröffentlicht" ;; *) echo "Unreleased" ;; esac; }

# The section "## <version>…" (or "## Unreleased") of changelog file $2.
wb_changelog_section_in() {
  local v=$1 file=$2
  [ -f "$file" ] || return 0
  WB_CHANGELOG=$file wb_changelog_section "$v"
}

# Checks (or with --draft prepares) the changelog of the version in
# pubspec.yaml in every language:
#   - a section "## <version> – <YYYY-MM-DD>" exists, without ENTWURF;
#   - --draft turns "## Unreleased" (collected while working) into that
#     section with today's date, or – without one – drafts it from the pull
#     requests merged since the last app tag, marked ENTWURF until written.
# Changes go into the files only; commit them in a pull request.
wb_changelog() {
  local draft=false
  if [ "${1:-}" = --draft ]; then draft=true; shift; fi
  local v=${1:-$(wb_version name)} lang file problems=0 today unrel
  today=$(date +%F)
  for lang in $WB_CHANGELOG_LANGS; do
    file=$(wb_changelog_file "$lang")
    unrel=$(wb_unreleased_heading "$lang")
    if $draft; then
      [ -f "$file" ] || printf '# %s\n\n' "$([ "$lang" = de ] && echo Änderungen || echo Changelog)" >"$file"
      if [ -z "$(wb_changelog_section_in "$v" "$file")" ]; then
        if grep -qE "^## +$unrel *$" "$file"; then
          sed -i.bak -E "s/^## +$unrel *$/## $v – $today/" "$file" && rm -f "$file.bak"
          say "$file: \"$unrel\" is now \"$v – $today\""
        else
          local since changes heading
          since=$(git describe --tags --abbrev=0 --match "${WB_APP_TAG_PREFIX}*" 2>/dev/null || true)
          changes=$({ git log --first-parent --merges --format='%s%x1f%b%x1e' ${since:+"$since..HEAD"} 2>/dev/null || true; } |
            awk 'BEGIN { RS = "\x1e"; FS = "\x1f" } { sub(/^\n+/, ""); if ($0 == "") next; split($2, body, "\n");
              t = body[1] != "" ? body[1] : $1; print "- " t }' | head -20)
          heading=$([ "$lang" = de ] && echo "### Neu" || echo "### New")
          # After the title and its intro: before the first "## ".
          awk -v sec="## $v – $today" -v head="$heading" -v body="${changes:-- …}" '
            !done && /^## / { print sec "\n\nENTWURF – in Nutzersprache umschreiben, dann diese Zeile löschen.\n\n" head "\n\n" body "\n"; done = 1 }
            { print }
            END { if (!done) print "\n" sec "\n\nENTWURF – in Nutzersprache umschreiben, dann diese Zeile löschen.\n\n" head "\n\n" body }' "$file" >"$file.tmp"
          mv "$file.tmp" "$file"
          say "$file: draft for $v from the merged pull requests"
        fi
      fi
    fi
    local section
    section=$(wb_changelog_section_in "$v" "$file")
    if [ ! -f "$file" ]; then
      warn "missing: $file"
      problems=1
    elif [ -z "$section" ]; then
      warn "$file: no section \"## $v – <date>\""
      problems=1
    elif grep -q ENTWURF <<<"$section"; then
      warn "$file: section $v is still a draft"
      problems=1
    elif ! grep -qE "^## +\[?$v\]?( \([^)]*\))? – [0-9]{4}-[0-9]{2}-[0-9]{2}" "$file"; then
      warn "$file: heading of $v should read \"## $v – YYYY-MM-DD\""
      problems=1
    fi
  done
  [ "$problems" = 0 ] || die "changelog of $v incomplete (werkbank changelog --draft)"
  say "Changelog of $v complete ($WB_CHANGELOG_LANGS)"
}

# ---------------------------------------------------------------------------
# Release (STANDARD.md "Release"): the same phases in every project

# Version of product $1: WB_VERSION_FILE_<product> (default pubspec.yaml),
# its first `version: x` or `"version": "x"`.
wb_product_version() {
  local p=${1:?product} var file v
  var="WB_VERSION_FILE_$p"
  file=${!var:-pubspec.yaml}
  [ -f "$file" ] || die "version file $file of $p missing"
  v=$(sed -nE 's/^[[:space:]]*"?version"?:[[:space:]]*"?([^",[:space:]]+)"?.*/\1/p' "$file" | head -1)
  [ -n "$v" ] || die "no version in $file"
  echo "$v"
}

# Tag prefix of product $1: WB_TAG_PREFIX_<product>, for the app WB_APP_TAG_PREFIX.
wb_tag_prefix() {
  local var="WB_TAG_PREFIX_$1"
  if [ -n "${!var:-}" ]; then echo "${!var}"; elif [ "$1" = app ]; then echo "$WB_APP_TAG_PREFIX"; else echo "$1-v"; fi
}

# Platforms of product $1: WB_PLATFORMS_<product>, else the platform folders
# for the app (ios, android, macos), else none.
wb_platforms() {
  local var="WB_PLATFORMS_$1" d out=""
  if [ -n "${!var+x}" ]; then echo "${!var}"; return; fi
  [ "$1" = app ] || return 0
  for d in ios android macos; do [ -d "$d" ] && out="$out $d"; done
  echo "${out# }"
}

# The section "## <version>" of the changelog, without its heading; empty if none.
wb_changelog_section() {
  [ -f "$WB_CHANGELOG" ] || return 0
  awk -v v="$1" '
    /^## / { if (found) exit; h = $0; sub(/^## +\[?/, "", h); split(h, w, /[] –(-]/); if (w[1] == v) { found = 1; next } }
    found { print }' "$WB_CHANGELOG" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

# Builds and uploads product $1 on its platforms – or the project's hook
# release_<product>, which then does it all (CI-built products: tag first,
# then wait for the workflow; or builds werkbank does not know).
wb_release_build() {
  local p=$1 upload=$2 platform
  if wb_has_hook "release_$p"; then
    "release_$p" "$upload"
    wb_resolved_guard after-hook
    return
  fi
  for platform in $(wb_platforms "$p"); do
    case "$platform" in
      android)
        wb_android
        if $upload; then wb_upload_play; fi
        ;;
      ios)
        wb_ios
        if $upload; then wb_upload_apple build/ios/archive/Runner.xcarchive; fi
        ;;
      *)
        wb_has_hook "build_$platform" || die "no werkbank build for $platform – define build_$platform in tool/werkbank.conf"
        "build_$platform" "$upload"
        wb_resolved_guard after-hook
        continue
        ;;
    esac
    wb_resolved_guard
  done
}

# One release, the same everywhere:
#   preflight  clean main equal to origin/main, verify, release texts and changelog there
#   build      per product and platform (or the release_<product> hook), --upload to the stores
#   tag        <prefix><version> per product, pushed – only after a successful build/upload
#   github     release with the changelog section and build/release/ files (WB_GH_RELEASE_REPO)
#   sites      WB_RELEASE_SITES deployed live
#   report     build/release/report-<version>.md: what happened, what is left by hand
# --dry-run shows the plan and changes nothing; --only <product> limits it;
# products whose tag exists are skipped (already released).
wb_release() {
  local dry=false upload=false only="" p
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=true ;;
      --upload) upload=true ;;
      --only) only=${2:?product}; shift ;;
      *) die "werkbank release [--dry-run] [--upload] [--only <product>]" ;;
    esac
    shift
  done
  local todo=() v tag
  for p in $WB_PRODUCTS; do
    [ -z "$only" ] || [ "$only" = "$p" ] || continue
    v=$(wb_product_version "$p")
    tag="$(wb_tag_prefix "$p")$v"
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
      say "$p $v: $tag exists – already released"
      continue
    fi
    todo+=("$p")
  done
  [ ${#todo[@]} -gt 0 ] || { say "Nothing to release"; return 0; }

  say "Preflight"
  local problems=()
  [ "$(git branch --show-current)" = main ] || problems+=("not on main")
  [ -z "$(wb_resolved_changed)" ] || problems+=("Package.resolved changed, probably by a store build: $(wb_resolved_changed | paste -sd ' ' -) – commit via PR (werkbank resolved)")
  [ -z "$(git status --porcelain -- . ':(exclude,glob)ios/**/Package.resolved' ':(exclude,glob)macos/**/Package.resolved')" ] || problems+=("uncommitted changes")
  git fetch -q origin main 2>/dev/null || true
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main 2>/dev/null)" ] || problems+=("main differs from origin/main")
  for p in "${todo[@]}"; do
    v=$(wb_product_version "$p")
    if ! (wb_changelog "${v%%+*}" >/dev/null 2>&1); then
      problems+=("changelog has no finished section \"## ${v%%+*} – <date>\" for $p (werkbank changelog --draft)")
    fi
    case " $(wb_platforms "$p") " in
      *" ios "* | *" android "*)
        if ! (WB_NO_CLIPBOARD=1 wb_store_notes >/dev/null 2>&1); then problems+=("release texts of $p incomplete (werkbank notes)"); fi
        ;;
    esac
  done
  if $dry; then
    for p in "${todo[@]}"; do
      v=$(wb_product_version "$p")
      say "would release $p $v: build $(wb_platforms "$p" | sed 's/^$/(release_'"$p"' hook)/')$($upload && echo ', upload'), tag $(wb_tag_prefix "$p")$v${WB_GH_RELEASE_REPO:+, GitHub release in $WB_GH_RELEASE_REPO}"
    done
    [ -z "$WB_RELEASE_SITES" ] || say "would deploy sites: $WB_RELEASE_SITES"
    if [ ${#problems[@]} -gt 0 ]; then
      printf '  ✗ %s\n' "${problems[@]}" >&2
      die "not ready to release"
    fi
    say "Ready – run without --dry-run"
    return 0
  fi
  if [ ${#problems[@]} -gt 0 ]; then
    printf '  ✗ %s\n' "${problems[@]}" >&2
    die "not ready to release (werkbank release --dry-run shows the plan)"
  fi
  mkdir -p build/release
  if wb_has_hook verify_release; then verify_release; else wb_verify; fi

  local report done_lines=()
  for p in "${todo[@]}"; do
    v=$(wb_product_version "$p")
    tag="$(wb_tag_prefix "$p")$v"
    say "Release $p $v"
    wb_release_build "$p" "$upload"
    git tag -a "$tag" -m "$WB_APP $p $v"
    git push -q origin "$tag"
    done_lines+=("- $p $v: tag $tag")
    if [ -n "$WB_GH_RELEASE_REPO" ]; then
      local notes files=()
      notes=$(wb_changelog_section "${v%%+*}")
      [ -n "$notes" ] || notes=$(wb_changelog_section "$v")
      while IFS= read -r f; do files+=("$f"); done < <(find build/release -maxdepth 1 -type f -name "*${v%%+*}*" ! -name 'report-*' | sort)
      gh release create "$tag" --repo "$WB_GH_RELEASE_REPO" --title "$WB_APP $p $v" --notes "${notes:-$p $v}" \
        ${files[@]+"${files[@]}"}
      done_lines+=("  GitHub release in $WB_GH_RELEASE_REPO (${#files[@]} files)")
    fi
  done
  local site
  for site in $WB_RELEASE_SITES; do
    wb_site_deploy "$site" --live
    done_lines+=("- site $site live")
  done
  report="build/release/report-$(wb_product_version "${todo[0]}").md"
  {
    echo "# Release $WB_APP $(date +%F)"
    echo
    printf '%s\n' "${done_lines[@]}"
    echo
    echo "Left by hand:"
    $upload || echo "- upload to the stores (werkbank release --upload, or the consoles)"
    if wb_has_hook release_manual; then release_manual; fi
  } >"$report"
  say "Report: $report"
  cat "$report"
}

# ---------------------------------------------------------------------------
# Sites (STANDARD.md "Landingpages"): one deploy for every target

# WB_SITES lists the sites as <name>=<folder>|<base URL>|<target>, targets:
#   blog:<folder below static/>   the blog repository (WEBSITE_REPO), live = push
#   ghpages:<owner/repo>[:<domain>] gh-pages branch of that repository; folders in
#                                 WB_SITE_KEEP_<name> stay when the build lacks them
#   workflow:<file>               a deploy workflow of this repository (gh workflow run)
#   hook                          the project's site_deploy_<name> <built folder> <live>
# Preview builds into build/site/<folder>/ and changes nothing elsewhere; --live
# deploys. site_post_<name> <built folder> runs after the build (redirects, extras).
wb_site_deploy() {
  local name=${1:?site name or all} live=false entry found=false
  [ "${2:-}" = --live ] && live=true
  for entry in $WB_SITES; do
    local key=${entry%%=*} rest=${entry#*=}
    [ "$name" = all ] || [ "$name" = "$key" ] || continue
    found=true
    local folder url target out
    IFS='|' read -r folder url target <<<"$rest"
    if [ -z "$folder" ] || [ -z "$url" ] || [ -z "$target" ]; then
      die "WB_SITES entry $entry: <name>=<folder>|<url>|<target>"
    fi
    say "Site $key ($folder → $target)"
    out=$(wb_site_build "$folder" "$url")
    if wb_has_hook "site_post_$key"; then "site_post_$key" "$out"; fi
    if ! $live; then
      say "Preview: $out/index.html (--live deploys to $target)"
      continue
    fi
    case "$target" in
      blog:*) wb_site_blog "$out" "${target#blog:}" --push ;;
      ghpages:*) WB_SITE_NAME=$key wb_site_ghpages "$out" "${target#ghpages:}" ;;
      workflow:*) gh workflow run "${target#workflow:}" --ref main && say "Workflow ${target#workflow:} started" ;;
      hook)
        wb_has_hook "site_deploy_$key" || die "site_deploy_$key missing in tool/werkbank.conf"
        "site_deploy_$key" "$out" true
        ;;
      *) die "unknown site target $target" ;;
    esac
  done
  $found || die "no site $name in WB_SITES"
}

# Replaces the gh-pages branch of <owner/repo>[:<domain>] with the built
# folder $1 (a fresh clone; CNAME for the domain, .nojekyll so .well-known stays).
wb_site_ghpages() {
  local src=${1:?built site} spec=${2:?owner/repo[:domain]} repo domain work
  repo=${spec%%:*}
  domain=""
  [ "$spec" = "$repo" ] || domain=${spec#*:}
  work=$(mktemp -d)
  if git clone -q --depth 1 --branch gh-pages "${WB_GIT_BASE:-https://github.com/}$repo${WB_GIT_SUFFIX:-.git}" "$work/pages" 2>/dev/null; then :; else
    git clone -q --depth 1 "${WB_GIT_BASE:-https://github.com/}$repo${WB_GIT_SUFFIX:-.git}" "$work/pages"
    git -C "$work/pages" checkout -q --orphan gh-pages
  fi
  # Folders of WB_SITE_KEEP_<name> stay as they are when this build has none of
  # its own (made elsewhere, e.g. from private files only the main checkout has).
  local keepvar="WB_SITE_KEEP_${WB_SITE_NAME:-}" k
  mkdir -p "$work/kept"
  for k in ${!keepvar:-}; do
    if [ ! -e "$src/$k" ] && [ -e "$work/pages/$k" ]; then
      mkdir -p "$work/kept/$(dirname "$k")"
      mv "$work/pages/$k" "$work/kept/$k"
      say "kept $k from the published site"
    fi
  done
  find "$work/pages" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  cp -R "$src/." "$work/pages/"
  cp -R "$work/kept/." "$work/pages/"
  [ -z "$domain" ] || echo "$domain" >"$work/pages/CNAME"
  touch "$work/pages/.nojekyll"
  git -C "$work/pages" add -A
  if git -C "$work/pages" diff --cached --quiet; then
    say "gh-pages of $repo unchanged"
  else
    git -C "$work/pages" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
      commit -q -m "$WB_APP: $(git rev-parse --short HEAD)"
    git -C "$work/pages" push -q origin gh-pages
    say "gh-pages of $repo pushed"
  fi
  rm -rf "$work"
}

# ---------------------------------------------------------------------------
# Device tests (STANDARD.md "Gerätetest")

# Runs the integration tests ($@, default WB_DEVICETEST_TARGETS or every
# integration_test/*_test.dart) with flutter drive --keep-app-running on every
# connected device – phones, tablets,
# the Mac; not the web – one device after the other, and writes a report to
# build/devicetest/<time>/report.md with a log per run. --device <id> limits
# it to one device. The project's hooks devicetest_before/devicetest_after
# get the device id and platform (back up app data, quit the app); a failing
# devicetest_before skips the device. Without
# devicetest_after a Mac run quits the app it started, so instances do not
# pile up in the Dock.
wb_devicetest() {
  local only=""
  if [ "${1:-}" = --device ]; then only=${2:?device id}; shift 2; fi
  local targets=("$@")
  if [ ${#targets[@]} -eq 0 ]; then
    if [ -n "$WB_DEVICETEST_TARGETS" ]; then
      # shellcheck disable=SC2206
      targets=($WB_DEVICETEST_TARGETS)
    else
      while IFS= read -r t; do targets+=("$t"); done < <(find integration_test -maxdepth 1 -name '*_test.dart' 2>/dev/null | sort)
    fi
  fi
  [ ${#targets[@]} -gt 0 ] || die "no integration tests (integration_test/*_test.dart)"
  local devices
  # Only platforms the project has (ios/, android/, macos/), never the web.
  local platforms="" p
  for p in ios android macos; do [ -d "$p" ] && platforms="$platforms $p"; done
  devices=$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
only, platforms = sys.argv[1], sys.argv[2].split()
for d in json.load(sys.stdin):
    kind = d.get("targetPlatform", "").split("-")[0]
    kind = "macos" if kind == "darwin" else kind
    if kind in platforms and (not only or d["id"] == only):
        print("\t".join([d["id"], kind, d["name"].replace("\t", " ")]))
' "$only" "$platforms")
  [ -n "$devices" ] || die "no device${only:+ $only} connected (flutter devices)"
  local out stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  out="build/devicetest/$stamp"
  mkdir -p "$out"
  # flutter drive with --keep-app-running: without it the app is uninstalled at the
  # end, and with it the data on the device (a lost iPad catalog, 15.10.2026).
  # The project's driver if it has one, else the standard one.
  local driver=test_driver/integration_test.dart
  if [ ! -f "$driver" ]; then
    driver=build/devicetest/integration_test_driver.dart
    printf "import 'package:integration_test/integration_test_driver.dart';\n\nFuture<void> main() => integrationDriver();\n" >"$driver"
  fi
  {
    echo "# Gerätetest $stamp – $WB_APP $(wb_version)"
    echo
    echo "| Gerät | Test | Ergebnis | Dauer | Log |"
    echo "| --- | --- | --- | --- | --- |"
  } >"$out/report.md"
  local id platform name target log start secs result failed=0
  while IFS=$'\t' read -r id platform name; do
    say "$name ($platform)"
    # A failed hook (no backup of the app data, say) skips the device: no test without a way back.
    if wb_has_hook devicetest_before && ! devicetest_before "$id" "$platform"; then
      warn "  skipped: devicetest_before failed"
      printf '| %s | – | skipped (devicetest_before failed) | – | – |\n' "$name" >>"$out/report.md"
      failed=1
      continue
    fi
    for target in "${targets[@]}"; do
      # The id too: two devices may share a name ("iPhone").
      log="$out/$(echo "$name-$id-$(basename "$target" .dart)" | tr -c 'A-Za-z0-9._\n-' '_').log"
      start=$(date +%s)
      if flutter drive --keep-app-running --driver="$driver" --target="$target" -d "$id" --no-pub >"$log" 2>&1; then
        result=ok
      else
        result=FAILED
        failed=1
      fi
      secs=$(($(date +%s) - start))
      printf '| %s | %s | %s | %d:%02d | %s |\n' "$name" "$target" "$result" $((secs / 60)) $((secs % 60)) \
        "$(basename "$log")" >>"$out/report.md"
      if [ "$result" = ok ]; then say "  $target ok"; else warn "  $target FAILED – $log"; fi
    done
    if wb_has_hook devicetest_after; then
      devicetest_after "$id" "$platform"
    elif [ "$platform" = macos ]; then
      pkill -f "$PWD/build/macos/Build/Products/" 2>/dev/null || true
    fi
  done <<<"$devices"
  say "Report: $out/report.md"
  [ "$failed" = 0 ] || die "device tests failed"
}

# ---------------------------------------------------------------------------

wb_doctor() {
  local tool
  for tool in git flutter dart xcrun gh hugo rsync python3 shellcheck; do
    if command -v "$tool" >/dev/null; then say "$tool: $(command -v "$tool")"; else warn "$tool missing"; fi
  done
  if (wb_keytool >/dev/null 2>&1); then say "keytool: $(wb_keytool)"; fi
  if [ -f android/key.properties ]; then
    say "android/key.properties present"
  else
    warn "android/key.properties missing (needed for werkbank android)"
  fi
  if [ -n "$WB_PLAY_PACKAGE" ]; then
    if [ -f "$WB_PLAY_KEY" ]; then say "Play service account key present"; else warn "Play key $WB_PLAY_KEY missing (needed for werkbank upload-play)"; fi
  fi
  if (wb_asc_key >/dev/null 2>&1); then
    say "App Store Connect API key present"
  else
    warn "no App Store Connect API key (needed for werkbank ios --upload)"
  fi
  say "app $WB_APP, version $(wb_version 2>/dev/null || echo '?'), symbols to $WB_SYMBOLS_DIR"
  [ -f tool/werkbank/VERSION ] && say "werkbank $(cat tool/werkbank/VERSION)"
  return 0
}
