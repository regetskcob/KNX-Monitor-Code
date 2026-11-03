#!/usr/bin/env bash
# Builds and publishes all release artifacts of KNX Monitor.
#
#   tool/release.sh verify           # checks of the pull request CI, on any branch – run before pushing
#   tool/release.sh layout           # folder structure only (part of verify, tool/werkbank/STANDARD.md)
#   tool/release.sh check            # preflight: clean main, verify, versions
#   tool/release.sh addon            # tag addon-v<version>, wait for both images, then merge main via PR + GitHub release
#   tool/release.sh site             # build landing page and push it to the website repo
#   tool/release.sh android          # build signed AAB (needs android/key.properties)
#   tool/release.sh ios              # build IPA, archive for the Organizer, upload to App Store Connect if API key is set
#   tool/release.sh macos            # build and archive for the Organizer (upload there), symbols kept
#   tool/release.sh app              # android + ios, then tag app-v<version>
#   tool/release.sh desktop          # Linux from CI of tag app-v<version> → public release (latest)
#   tool/release.sh box <version>    # KNX Box image from the box-v<version> workflow, plus the case (box/case) → public release
#   tool/release.sh status           # show versions, tags and open release steps
#
# Versions:
#   add-on: ha-addon/knx_monitor/config.yaml  (version: "1.2.0"), tag addon-v1.2.0
#   apps:   pubspec.yaml                      (version: 1.0.0+1),   tag app-v1.0.0+1
# A tag that already exists means that version was published – bump first.
#
# iOS upload uses App Store Connect API keys (optional):
#   ASC_KEY_ID, ASC_ISSUER_ID and ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
#   (or ASC_KEY_PATH)
# Without them the IPA is built and must be uploaded with Transporter or Xcode.
#
# In-app purchases: store builds need the public
# RevenueCat SDK keys RC_APPLE_KEY (appl_…) and RC_GOOGLE_KEY (goog_…), e.g.
# from ~/.config/knx-monitor/revenuecat.env. A release build without key is Free
# with no way to buy. RC_NONE=1 builds without on purpose and unlocks everything
# (PLAN_OPEN): store builds while there is no business. PAID=1 is the guard for
# the first paid release and later ones: it refuses RC_NONE.
# BETA=1 tool/release.sh ios|android builds for TestFlight / Play test tracks
# only: testers get Pro and a thank-you after launch. Never submit such a build
# for App Review (same sandbox, no purchases visible) and never promote it to
# Play production – build again without BETA. Android also needs the offering
# metadata beta_unlock=true in RevenueCat (remote switch).
#
# Repositories: the source lives in the private $REPO (tags, workflows). Users
# only see the public $PUBLIC_REPO: Home Assistant add-on metadata (synced by
# tool/sync_public.sh), GitHub releases with downloads, issues.
set -euo pipefail
# Shared steps (layout, verify, builds, symbols): tool/werkbank, settings in
# tool/werkbank.conf, rules in tool/werkbank/STANDARD.md.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=werkbank/lib/common.sh
. "$(dirname "$0")/werkbank/lib/common.sh"
wb_enter_repo
wb_load_conf

REPO=regetskcob/KNX-Monitor-Source
PUBLIC_REPO=regetskcob/KNX-Monitor
ADDON_CONFIG=ha-addon/knx_monitor/config.yaml
ADDON_CHANGELOG=ha-addon/knx_monitor/CHANGELOG.md

addon_version() { grep -E '^version:' "$ADDON_CONFIG" | cut -d'"' -f2; }
app_version() { wb_version; }
tag_exists() { git rev-parse -q --verify "refs/tags/$1" >/dev/null || git ls-remote --exit-code --tags origin "refs/tags/$1" >/dev/null 2>&1; }

# Changelog section of one version (lines between "## <version>" and the next "## ").
changelog_section() {
  awk -v v="## $1" '$0 == v {on=1; next} on && /^## / {exit} on' "$ADDON_CHANGELOG" | sed '/./,$!d'
}

# With "ahead", local main may contain unpushed commits on top of origin/main.
require_clean_main() {
  [ "$(git branch --show-current)" = main ] || die "not on main"
  git fetch -q origin
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "uncommitted changes – commit or stash first"
  if [ "${1:-}" = ahead ]; then
    git merge-base --is-ancestor origin/main HEAD || die "main is behind or diverged from origin/main – pull first"
  else
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main differs from origin/main – push or pull first"
  fi
}

# The same checks as the pull request CI (.github/workflows/ci.yml), on any
# branch or worktree: run before pushing so the CI run only confirms. The web
# build and the add-on server come from verify_extra in tool/werkbank.conf.
cmd_verify() { wb_verify; }

cmd_check() {
  require_clean_main ahead
  cmd_verify
  say "Versions"
  local av; av=$(addon_version)
  [ -n "$(changelog_section "$av")" ] || die "no CHANGELOG entry for add-on $av"
  tag_exists "addon-v$av" && warn "add-on $av is already published – bump version in $ADDON_CONFIG for a new add-on release"
  tag_exists "app-v$(app_version)" && warn "app $(app_version) is already published – bump version in pubspec.yaml for a new store build"
  say "All checks passed"
}

# main is protected (ruleset "main nur über PR"): local commits reach it only
# through a pull request. Pushes HEAD to branch $1, opens a PR, waits for its
# checks and merges with a merge commit, so tags on HEAD stay in main's history.
pr_to_main() {
  local branch=$1 title=$2
  git push -q -f origin "HEAD:refs/heads/$branch"
  local url; url=$(gh pr create -R "$REPO" --base main --head "$branch" --title "$title" --body "Opened by tool/release.sh.")
  say "Pull request: $url – waiting for checks"
  sleep 15
  # Changes only to docs start no CI run; then there is nothing to wait for.
  if ! gh pr checks "$url" -R "$REPO" 2>&1 | grep -q 'no checks reported'; then
    gh pr checks "$url" -R "$REPO" --watch --fail-fast --interval 30 >/dev/null || die "checks failed: $url – fix on $branch, then rerun"
  fi
  gh pr merge "$url" -R "$REPO" --merge --delete-branch >/dev/null
  git fetch -q origin
  git merge -q --ff-only origin/main
}

# Home Assistant reads the version from config.yaml on main. The version bump is
# therefore merged into main only after both images exist; until then only the
# tag is on GitHub (the workflow builds from the tag).
cmd_addon() {
  require_clean_main ahead
  local v; v=$(addon_version)
  tag_exists "addon-v$v" && die "addon-v$v already exists – bump version in $ADDON_CONFIG"
  local notes; notes=$(changelog_section "$v")
  [ -n "$notes" ] || die "no CHANGELOG entry for $v in $ADDON_CHANGELOG"
  say "Tagging addon-v$v (main stays unmerged until the images exist)"
  git tag -a "addon-v$v" -m "Home Assistant add-on $v"
  git push -q origin "addon-v$v"
  say "Waiting for image workflow"
  sleep 10
  local run; run=$(gh run list -R "$REPO" --workflow addon.yml --branch "addon-v$v" -L 1 --json databaseId --jq '.[0].databaseId')
  [ -n "$run" ] || die "workflow run for addon-v$v not found"
  # "approve" only waits with required reviewers (private repo: only with
  # Enterprise, see docs/release-security.md); otherwise it runs through.
  say "Building images: https://github.com/$REPO/actions/runs/$run"
  gh run watch "$run" -R "$REPO" --exit-status --interval 30 >/dev/null ||
    die "image build failed: gh run view $run -R $REPO --log-failed – main was not merged; fix, then delete the tag (git push origin :addon-v$v; git tag -d addon-v$v) and retry"
  cmd_verify_images "$v" || die "images incomplete – main was not merged"
  # If the version bump already reached main via PR, there is nothing left to merge.
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || pr_to_main "release/addon-v$v" "Add-on $v"
  git merge-base --is-ancestor "addon-v$v" HEAD || die "addon-v$v is not in main after the merge"
  say "Updating public repository – Home Assistant now offers $v"
  tool/sync_public.sh "addon-v$v" --push
  say "Creating GitHub release"
  # --latest=false: "latest" stays the app release (desktop downloads link there).
  gh release create "addon-v$v" -R "$PUBLIC_REPO" --title "Home Assistant add-on $v" --notes "$notes" --latest=false >/dev/null
}

cmd_verify_images() {
  local v=${1:-$(addon_version)} ok=1
  local accept='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'
  for arch in amd64 aarch64; do
    local token digest latest
    token=$(curl -fsS "https://ghcr.io/token?scope=repository:${REPO%%/*}/$arch-knx-monitor:pull" 2>/dev/null | sed -E 's/.*"token":"([^"]+)".*/\1/') || token=
    digest() { curl -fsSI -H "Authorization: Bearer $token" -H "Accept: $accept" \
      "https://ghcr.io/v2/${REPO%%/*}/$arch-knx-monitor/manifests/$1" 2>/dev/null | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" {print $2}'; }
    digest=$([ -n "$token" ] && digest "$v")
    if [ -z "$digest" ]; then
      warn "$arch-knx-monitor:$v is not publicly pullable – set the package to Public: https://github.com/users/${REPO%%/*}/packages/container/$arch-knx-monitor/settings"
      ok=0
      continue
    fi
    latest=$(digest latest)
    # imagetools create wraps a single manifest in a new index – same image, other digest.
    if [ "$latest" != "$digest" ] && curl -fsS -H "Authorization: Bearer $token" -H "Accept: $accept" \
      "https://ghcr.io/v2/${REPO%%/*}/$arch-knx-monitor/manifests/latest" 2>/dev/null | grep -q "\"$digest\""; then
      latest=$digest
    fi
    if [ "$latest" = "$digest" ]; then
      say "$arch-knx-monitor:$v is publicly pullable and latest"
    else
      warn "$arch-knx-monitor:latest is not $v – the packages are out of sync"
      ok=0
    fi
  done
  [ $ok = 1 ]
}

cmd_site() {
  require_clean_main
  command -v hugo >/dev/null || die "hugo not installed (brew install hugo)"
  tool/deploy_site.sh --push
}

# --dart-define for the purchase path of a store build ($1: RC_APPLE_KEY or
# RC_GOOGLE_KEY): the key, or with RC_NONE=1 deliberately free (PLAN_OPEN, the
# only place that sets it). A key lying around does not change that decision.
rc_define() {
  if [ "${RC_NONE:-}" = 1 ]; then
    [ "${PAID:-}" != 1 ] || die "PAID=1 and RC_NONE=1 contradict each other: a paid release needs its RevenueCat key"
    echo "--dart-define=PLAN_OPEN=true"
    return
  fi
  local env=~/.config/knx-monitor/revenuecat.env
  # shellcheck disable=SC1090
  [ -f "$env" ] && . "$env"
  local key=${!1:-}
  [ -n "$key" ] || die "$1 missing – a release build without it is Free with no way to buy (set RC_NONE=1 to build a free one on purpose)"
  echo "--dart-define=$1=$key"
}

# Accounts come only with the business model: a store build gets neither
# Supabase values nor an account. Only BETRIEB=1 builds them in,
# from ~/.config/knx-monitor/supabase.env; then a build without the file aborts.
supabase_defines() {
  [ "${BETRIEB:-}" = 1 ] || return 0
  local env=~/.config/knx-monitor/supabase.env
  [ -f "$env" ] || die "$env missing – BETRIEB=1 needs the account values"
  # shellcheck disable=SC1090
  . "$env"
  [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_KEY:-}" ] || die "$env lacks SUPABASE_URL or SUPABASE_KEY – BETRIEB=1 would ship without the account"
  # APPLE_WEB=true once the services ID for Sign in with Apple in the browser is in place.
  echo "--dart-define=BETRIEB=true --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_KEY=$SUPABASE_KEY --dart-define=APPLE_WEB=${APPLE_WEB:-false}"
}

# Store builds through werkbank: signature check, copy to
# build/release/knx-monitor-<version>.(aab|ipa), debug symbols kept in
# ~/keys/symbols/knx-monitor/<version>/<platform> (flutter clean wipes build/,
# crash reports of the obfuscated build need them).
cmd_android() {
  local rc; rc=$(rc_define RC_GOOGLE_KEY)
  local sb; sb=$(supabase_defines)
  local beta=""
  if [ "${BETA:-}" = 1 ]; then
    beta="--dart-define=BETA=true"
    say "Test-track-only build (BETA): never promote it to production"
  fi
  # shellcheck disable=SC2086
  wb_android -- --obfuscate --split-debug-info=build/symbols/android $rc $sb $beta
  say "Upload it in the Play Console (Release → Create new release)"
}

# Uploads to App Store Connect when ASC_KEY_ID and ASC_ISSUER_ID are set.
cmd_ios() {
  local rc; rc=$(rc_define RC_APPLE_KEY)
  local sb; sb=$(supabase_defines)
  local beta=""
  if [ "${BETA:-}" = 1 ]; then
    beta="--dart-define=BETA=true"
    say "TestFlight-only build (BETA): do not submit it for App Review"
  fi
  local upload=()
  if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then upload=(--upload); fi
  # shellcheck disable=SC2086
  wb_ios ${upload[@]+"${upload[@]}"} -- --obfuscate --split-debug-info=build/symbols/ios $rc $sb $beta
  organizer_copy build/ios/archive/Runner.xcarchive iOS
}

# Path of a new archive in the folder the Xcode Organizer reads ($1: platform).
organizer_path() {
  echo "$HOME/Library/Developer/Xcode/Archives/$(date +%F)/KNX Monitor $1 $(app_version).xcarchive"
}

# Makes an archive show up in the Xcode Organizer.
organizer_copy() {
  [ -d "$1" ] || die "no archive at $1"
  local target; target=$(organizer_path "$2")
  mkdir -p "$(dirname "$target")"
  rm -rf "$target"
  cp -R "$1" "$target"
  say "Archive in the Organizer: $target"
}

# Mac App Store: same checks and defines as iOS. flutter build first, because it
# writes the defines and obfuscation into macos/Flutter/ephemeral, which the
# archive then picks up. Upload from the Organizer (Distribute App).
cmd_macos() {
  local rc; rc=$(rc_define RC_APPLE_KEY)
  local sb; sb=$(supabase_defines)
  local beta=""
  if [ "${BETA:-}" = 1 ]; then
    beta="--dart-define=BETA=true"
    say "TestFlight-only build (BETA): do not submit it for App Review"
  fi
  # shellcheck disable=SC2086
  flutter build macos --release --obfuscate --split-debug-info=build/symbols/macos $rc $sb $beta
  wb_symbols macos
  local archive; archive=$(organizer_path macOS)
  mkdir -p "$(dirname "$archive")"
  rm -rf "$archive"
  xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -archivePath "$archive" archive
  [ -d "$archive" ] || die "no archive at $archive"
  say "Archive in the Organizer: $archive"
}

cmd_app() {
  require_clean_main
  local v; v=$(app_version)
  tag_exists "app-v$v" && die "app-v$v already exists – bump the build number in pubspec.yaml"
  cmd_android
  cmd_ios
  git tag -a "app-v$v" -m "App store build $v"
  git push -q origin "app-v$v"
  say "Tagged app-v$v"
}

# Run id of the latest successful run of a workflow for a tag or commit.
run_for() {
  gh run list -R "$REPO" --workflow "$1" --status success -L 20 --json databaseId,headBranch,headSha \
    --jq "[.[] | select(.headBranch == \"$2\" or .headSha == \"$2\")][0].databaseId // empty"
}

# Run of ci.yml for a tag whose linux job succeeded, newest first. Only that job
# counts: A failed windows job (not published anyway) must not block the release.
desktop_run() {
  local run conclusion
  for run in $(gh run list -R "$REPO" --workflow ci.yml -L 20 --json databaseId,headBranch \
    --jq "[.[] | select(.headBranch == \"$1\")] | .[].databaseId"); do
    conclusion=$(gh run view "$run" -R "$REPO" --json jobs --jq '.jobs[] | select(.name == "linux") | .conclusion')
    if [ "$conclusion" = success ]; then echo "$run"; return; fi
  done
}

# Public desktop downloads: CI builds Windows and Linux (obfuscated) only for
# app-v* tags; this packs the Linux artifact of the tag run of app-v<version>
# with the EULA and publishes it as the "latest" release that the website
# links to. Windows stays unpublished until it launches with the store apps
# (account and Paddle); macOS ships through the App Store only.
cmd_desktop() {
  local v; v=$(app_version)
  local name=${v%%+*}
  tag_exists "app-v$v" || die "app-v$v not tagged – run tool/release.sh app first"
  # The tag run, not the push run of the same commit: only it has the desktop artifacts.
  local run; run=$(desktop_run "app-v$v")
  [ -n "$run" ] || die "no CI run for tag app-v$v with a successful linux job – wait for it (gh run list -R $REPO --workflow ci.yml), artifacts are kept 7 days"
  local tmp; tmp=$(mktemp -d)
  say "Downloading desktop builds of CI run $run"
  gh run download "$run" -R "$REPO" -n knx-monitor-linux -D "$tmp/linux"
  mkdir -p "$tmp/out"
  (cd "$tmp/linux" && tar -xzf knx-monitor-linux-x64.tar.gz && cp "$OLDPWD/tool/public-repo/LICENSE" bundle/LICENSE.txt &&
    tar -czf "$tmp/out/knx-monitor-$name-linux-x64.tar.gz" bundle)
  (cd "$tmp/out" && shasum -a 256 ./*.tar.gz | sed 's| \./| |' >SHA256SUMS.txt)
  say "Creating public release app-v$v"
  gh release create "app-v$v" -R "$PUBLIC_REPO" --title "KNX Monitor $name" --latest \
    --notes "Linux build of KNX Monitor $name: unpack and run \`./install.sh\` in the \`bundle\` folder: it installs KNX Monitor to \`~/.local/opt/knx-monitor\` and adds it with its icon to the app menu, then the download can go. For an update, do the same with the new version. Step by step (German and English): \`README.txt\` in the \`bundle\` folder. Windows, iPhone, iPad, Mac and Android follow (App Store, Google Play)." \
    "$tmp"/out/*
  rm -rf "$tmp"
}

# KNX Box: .github/workflows/box-image.yml builds image and package on a
# box-v<version> tag; this publishes its artifacts in the public repository.
cmd_box() {
  local v=${1:?usage: tool/release.sh box <version>}
  local run; run=$(run_for box-image.yml "box-v$v")
  [ -n "$run" ] || die "no successful box-image run for box-v$v – push the tag and wait for the workflow"
  local tmp; tmp=$(mktemp -d)
  say "Downloading box image of run $run"
  gh run download "$run" -R "$REPO" -n knx-box-bundle -D "$tmp"
  gh run download "$run" -R "$REPO" -n knx-box-image -D "$tmp"
  mv "$tmp/knx-box.tar.gz" "$tmp/knx-box-$v.tar.gz"
  # Signatures from the run (cosign, tags only); older runs have none.
  [ ! -f "$tmp/knx-box.tar.gz.sigstore.json" ] || mv "$tmp/knx-box.tar.gz.sigstore.json" "$tmp/knx-box-$v.tar.gz.sigstore.json"
  local files=("$tmp"/*.img.xz "$tmp/knx-box-$v.tar.gz")
  local notes="Image mit dem Raspberry Pi Imager (Eigenes Image) auf SD-Karte oder SSD schreiben. Vor dem ersten Start optional knx-box.txt auf der Boot-Partition ausfüllen. Paket für einen schon laufenden Pi: entpacken, sudo ./setup.sh. Prüfsummen: SHA256SUMS.txt (sha256sum -c), Signaturen (cosign): *.sigstore.json."
  # Case for printing (STLs and description) from the state of the tag;
  # fetch the tag first in case it only exists on GitHub.
  git fetch -q origin "refs/tags/box-v$v:refs/tags/box-v$v" 2>/dev/null || true
  # Up to box-v1.8.4 the box lived in tool/knx-box/.
  local case=box/case
  git cat-file -e "box-v$v:$case" 2>/dev/null || case=tool/knx-box/case
  if git cat-file -e "box-v$v:$case" 2>/dev/null; then
    git archive --format=zip --prefix="knx-box-case-$v/" -o "$tmp/knx-box-case-$v.zip" "box-v$v:$case"
    files+=("$tmp/knx-box-case-$v.zip")
    notes+=" Gehäuse zum Drucken (Vorschau, Pi 3B bis 5 mit kBerry): knx-box-case-$v.zip, Beschreibung im README.md darin."
  fi
  # Checksums over everything that goes out.
  (cd "$tmp" && shasum -a 256 "${files[@]##*/}" >SHA256SUMS.txt)
  files+=("$tmp/SHA256SUMS.txt")
  local bundle
  for bundle in "$tmp"/*.sigstore.json; do
    [ ! -f "$bundle" ] || files+=("$bundle")
  done
  gh release create "box-v$v" -R "$PUBLIC_REPO" --latest=false --title "KNX Monitor Box $v" --notes "$notes" "${files[@]}"
  rm -rf "$tmp"
}

cmd_status() {
  local av pv; av=$(addon_version); pv=$(app_version)
  git fetch -q --tags origin
  printf 'add-on  %-10s %s\n' "$av" "$(tag_exists "addon-v$av" && echo published || echo 'not published → tool/release.sh addon')"
  printf 'app     %-10s %s\n' "$pv" "$(tag_exists "app-v$pv" && echo published || echo 'not published → tool/release.sh app')"
  printf 'site    last change %s\n' "$(git log -1 --format=%cs -- site)"
  cmd_verify_images "$av" || true
}

case "${1:-}" in
  verify) cmd_verify ;;
  layout) wb_layout ;;
  check) cmd_check ;;
  addon) cmd_addon ;;
  site) cmd_site ;;
  android) cmd_android ;;
  ios) cmd_ios ;;
  macos) cmd_macos ;;
  app) cmd_app ;;
  desktop) cmd_desktop ;;
  box) cmd_box "${2:-}" ;;
  status) cmd_status ;;
  verify-images) cmd_verify_images "${2:-}" ;;
  # For tests and for checking what a build would get, without building.
  rc-define) rc_define "${2:?RC_APPLE_KEY or RC_GOOGLE_KEY}" ;;
  desktop-run) desktop_run "${2:?tag}" ;;
  *) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
