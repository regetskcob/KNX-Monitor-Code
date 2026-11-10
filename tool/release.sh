#!/usr/bin/env bash
# Builds and publishes all release artifacts of Busclear.
#
#   tool/release.sh verify           # checks of the pull request CI, on any branch – run before pushing
#   tool/release.sh push [args]      # git push; marks HEAD verified on GitHub, so the PR CI skips its checks
#   tool/release.sh layout           # folder structure only (part of verify, tool/werkbank/STANDARD.md)
#   tool/release.sh smoke            # build the add-on image locally (podman or docker) and run its smoke
#                                    # test (tool/smoke_docker.sh); push/tag then let the CI skip it
#   tool/release.sh check            # preflight: clean main, verify, versions
#   tool/release.sh addon            # tag addon-v<version>, wait for both images, then merge main via PR + GitHub release
#   tool/release.sh site [knx] [--live] # busclear.de with /socials/: preview build, --live over FTPS to do.de
#   tool/release.sh android          # build signed AAB (needs android/key.properties)
#   tool/release.sh ios              # build IPA, archive for the Organizer, upload to App Store Connect if API key is set
#   tool/release.sh macos            # build and archive for the Organizer (upload there), symbols kept
#   tool/release.sh app              # android + ios, then tag app-v<version>
#   tool/release.sh desktop          # Linux from CI of tag app-v<version> → public release (latest)
#   tool/release.sh box <version>    # Busclear Box image from the box-v<version> workflow, plus the case (box/case) → public release
#   tool/release.sh integration      # Busclear integration for Home Assistant (HACS): sync, tag v<version>, GitHub release
#   tool/release.sh status           # show versions, tags and open release steps (add-on, app, box, integration, source)
#   tool/release.sh notes [--draft]  # release texts of this build (TestFlight, Play) complete? drafts from the PRs
#   tool/release.sh devicetest [--device <id>] [test …]
#                                    # integration tests on every connected device, app data backed up first
#
# UPLOAD=1 sends the store builds on: iOS and macOS archives to App Store Connect
# with the Apple account signed in to Xcode (no API key), the AAB with its release
# notes to the Play track of WB_PLAY_TRACK (service account ~/keys/knx-monitor-play.json).
# The release texts must be complete first (tool/release.sh notes).
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

HA_REPO=regetskcob/KNX-Monitor-HA
CODE_REPO=regetskcob/KNX-Monitor-Code
HA_MANIFEST=ha-integration/custom_components/knx_monitor/manifest.json
integration_version() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$HA_MANIFEST"; }
public_release_exists() { gh release view "$2" -R "$1" >/dev/null 2>&1; }
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
  [ -z "$(wb_resolved_changed)" ] || die "Package.resolved changed, probably by a store build: $(wb_resolved_changed | paste -sd ' ' -) – commit via PR first"
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

# The add-on image's smoke test (tool/smoke_docker.sh), locally instead of in
# the CI: builds the web app and the image with podman (or docker), runs the
# test and stamps the commit (werkbank/smoke). push and the add-on tag then tell
# GitHub, and the smoke job of addon.yml skips it. On macOS podman needs its
# machine (started here) and a compose provider (brew install docker-compose).
SMOKE_IMAGE=localhost/knx-monitor-smoke
smoke_engine() {
  if [ -n "${ENGINE:-}" ]; then echo "$ENGINE"
  elif command -v podman >/dev/null 2>&1; then echo podman
  elif command -v docker >/dev/null 2>&1; then echo docker
  fi
}
smoke_stamped() {
  local f; f="$(git rev-parse --git-dir)/werkbank-stamp-smoke"
  [ -f "$f" ] && [ "$(cat "$f")" = "$(git rev-parse HEAD)" ]
}
cmd_smoke() {
  local engine; engine=$(smoke_engine)
  [ -n "$engine" ] || die "neither podman nor docker found (brew install podman)"
  if [ "$engine" = podman ] && [ "$(uname)" = Darwin ] &&
    ! podman machine inspect --format '{{.State}}' 2>/dev/null | grep -q running; then
    say "Starting the podman machine"
    podman machine start >/dev/null
  fi
  say "Web app for the image"
  tool/build_ha_addon.sh >/dev/null
  say "Building $SMOKE_IMAGE ($engine)"
  "$engine" build -q -t "$SMOKE_IMAGE" ha-addon/knx_monitor >/dev/null
  ENGINE=$engine tool/smoke_docker.sh "$SMOKE_IMAGE"
  wb_stamp smoke
}

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
  # Smoke test locally first: a broken image stops here, before the tag, and the
  # tag's CI skips the test (werkbank/smoke). Without podman/docker the CI runs it.
  if ! smoke_stamped; then
    if [ -n "$(smoke_engine)" ]; then cmd_smoke; else warn "no podman/docker – the CI runs the smoke test"; fi
  fi
  say "Tagging addon-v$v (main stays unmerged until the images exist)"
  git tag -a "addon-v$v" -m "Home Assistant add-on $v"
  wb_push_tag "addon-v$v"
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
  # SBOM of the server (CycloneDX, tool/sbom.py) as a release file: what is inside, for the CRA.
  local sbom; sbom=$(mktemp -d)
  python3 tool/sbom.py "$sbom" >/dev/null
  # --latest=false: "latest" stays the app release (desktop downloads link there).
  gh release create "addon-v$v" -R "$PUBLIC_REPO" --title "Home Assistant add-on $v" --notes "$notes" --latest=false \
    "$sbom/busclear-server.cdx.json" >/dev/null
  rm -rf "$sbom"
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

# busclear.de (site/ with the socials page) through the werkbank deploy:
# preview by default, --live from a clean main (tool/werkbank.conf, WB_SITES).
cmd_site() {
  command -v hugo >/dev/null || die "hugo not installed (brew install hugo)"
  case " $* " in *" --live "*) require_clean_main ;; esac
  wb_site_deploy "${1:-knx}" "${@:2}"
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
  if [ "${UPLOAD:-}" = 1 ]; then
    wb_upload_play
  else
    say "Not uploaded – UPLOAD=1, or the Play Console (Release → Create new release)"
  fi
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
  # UPLOAD=1 sends the archive with the Xcode account below; the API key path (altool)
  # only without it, as before.
  if [ "${UPLOAD:-}" != 1 ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then upload=(--upload); fi
  # shellcheck disable=SC2086
  wb_ios ${upload[@]+"${upload[@]}"} -- --obfuscate --split-debug-info=build/symbols/ios $rc $sb $beta
  organizer_copy build/ios/archive/Runner.xcarchive iOS
  if [ "${UPLOAD:-}" = 1 ]; then wb_upload_apple build/ios/archive/Runner.xcarchive; fi
}

# Path of a new archive in the folder the Xcode Organizer reads ($1: platform).
organizer_path() {
  echo "$HOME/Library/Developer/Xcode/Archives/$(date +%F)/Busclear $1 $(app_version).xcarchive"
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
  wb_resolved_guard
  if [ "${UPLOAD:-}" = 1 ]; then wb_upload_apple "$archive"; fi
}

cmd_app() {
  require_clean_main
  local v; v=$(app_version)
  tag_exists "app-v$v" && die "app-v$v already exists – bump the build number in pubspec.yaml"
  # Texts first: an upload without them leaves testers with nothing to look at.
  if [ "${UPLOAD:-}" = 1 ]; then WB_NO_CLIPBOARD=1 wb_store_notes >/dev/null; fi
  # verify for exactly this commit lets the tag's CI skip app and addon-server
  # (werkbank/verify, job gate); the desktop builds run in any case.
  [ "$(cat "$(wb_stamp_file)" 2>/dev/null)" = "$(git rev-parse HEAD)" ] || cmd_verify
  cmd_android
  cmd_ios
  git tag -a "app-v$v" -m "App store build $v"
  wb_push_tag "app-v$v"
  say "Tagged app-v$v"
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
  # SBOM of the app (CycloneDX, tool/sbom.py), covered by SHA256SUMS.txt as well.
  python3 tool/sbom.py "$tmp/sbom" >/dev/null && cp "$tmp/sbom/busclear-app.cdx.json" "$tmp/out/"
  (cd "$tmp/out" && shasum -a 256 ./*.tar.gz ./*.cdx.json | sed 's| \./| |' >SHA256SUMS.txt)
  say "Creating public release app-v$v"
  gh release create "app-v$v" -R "$PUBLIC_REPO" --title "Busclear $name" --latest \
    --notes "Linux build of Busclear $name: unpack and run \`./install.sh\` in the \`bundle\` folder: it installs Busclear to \`~/.local/opt/knx-monitor\` and adds it with its icon to the app menu, then the download can go. For an update, do the same with the new version. Step by step (German and English): \`README.txt\` in the \`bundle\` folder. Windows, iPhone, iPad, Mac and Android follow (App Store, Google Play)." \
    "$tmp"/out/*
  rm -rf "$tmp"
}

# Busclear Box: .github/workflows/box-image.yml builds image and package on a
# box-v<version> tag; this publishes its artifacts in the public repository.
#
# Only a run started by pushing the tag (not a manual run on a branch of the
# same name) of exactly the tagged commit counts, and every file must carry a
# cosign signature of that run: identity, trigger and commit are checked
# with cosign verify-blob. Without cosign or with a failed check nothing is
# published.
box_identity() { echo "https://github.com/$REPO/.github/workflows/box-image.yml@refs/tags/$1"; }

box_run() { # box_run <tag> <commit>
  gh run list -R "$REPO" --workflow box-image.yml --event push --status success -L 50 \
    --json databaseId,headBranch,headSha,event \
    --jq "[.[] | select(.event == \"push\" and .headBranch == \"$1\" and .headSha == \"$2\")][0].databaseId // empty"
}

box_verify() { # box_verify <file> <tag> <commit>
  [ -f "$1.sigstore.json" ] || die "no signature for ${1##*/} – box releases are only published signed"
  cosign verify-blob "$1" --bundle "$1.sigstore.json" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --certificate-identity "$(box_identity "$2")" \
    --certificate-github-workflow-trigger push \
    --certificate-github-workflow-sha "$3" >/dev/null 2>&1 ||
    die "signature of ${1##*/} does not verify for $(box_identity "$2") at $3"
}

cmd_box() {
  local v=${1:?usage: tool/release.sh box <version>}
  local tag=box-v$v
  command -v cosign >/dev/null || die "cosign missing (brew install cosign) – box releases are only published with a verified signature"
  # From GitHub, overwriting a local tag of the same name: a stale one would
  # pick the run of another commit. Without the remote tag nothing is published.
  git fetch -q --force origin "refs/tags/$tag:refs/tags/$tag" || die "could not fetch tag $tag from origin"
  local sha; sha=$(git rev-parse -q --verify "refs/tags/$tag^{commit}") || die "tag $tag not found"
  local run; run=$(box_run "$tag" "$sha")
  [ -n "$run" ] || die "no successful box-image run for the push of $tag ($sha) – push the tag and wait for the workflow"
  local tmp; tmp=$(mktemp -d)
  say "Downloading box image of run $run"
  gh run download "$run" -R "$REPO" -n knx-box-bundle -D "$tmp"
  gh run download "$run" -R "$REPO" -n knx-box-image -D "$tmp"
  local image images=()
  for image in "$tmp"/*.img.xz; do
    [ ! -f "$image" ] || images+=("$image")
  done
  [ "${#images[@]}" -gt 0 ] || die "run $run has no image"
  say "Verifying signatures (cosign)"
  for image in "$tmp/knx-box.tar.gz" "${images[@]}"; do
    box_verify "$image" "$tag" "$sha"
  done
  mv "$tmp/knx-box.tar.gz" "$tmp/knx-box-$v.tar.gz"
  mv "$tmp/knx-box.tar.gz.sigstore.json" "$tmp/knx-box-$v.tar.gz.sigstore.json"
  local files=("${images[@]}" "$tmp/knx-box-$v.tar.gz")
  local notes="Image mit dem Raspberry Pi Imager (Eigenes Image) auf SD-Karte oder SSD schreiben. Vor dem ersten Start optional knx-box.txt auf der Boot-Partition ausfüllen. Paket für einen schon laufenden Pi: entpacken, sudo ./setup.sh. Prüfsummen: SHA256SUMS.txt (sha256sum -c), Signaturen (cosign verify-blob, siehe docs/release-security.md): *.sigstore.json."
  # Case for printing (STLs and description) from the state of the tag.
  # Up to box-v1.8.4 the box lived in tool/knx-box/.
  local case=box/case
  git cat-file -e "$tag:$case" 2>/dev/null || case=tool/knx-box/case
  if git cat-file -e "$tag:$case" 2>/dev/null; then
    git archive --format=zip --prefix="knx-box-case-$v/" -o "$tmp/knx-box-case-$v.zip" "$tag:$case"
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
  gh release create "$tag" -R "$PUBLIC_REPO" --latest=false --title "Busclear Box $v" --notes "$notes" "${files[@]}"
  rm -rf "$tmp"
}

cmd_status() {
  local av pv; av=$(addon_version); pv=$(app_version)
  git fetch -q --tags origin
  printf 'add-on  %-10s %s\n' "$av" "$(tag_exists "addon-v$av" && echo published || echo 'not published → tool/release.sh addon')"
  printf 'app     %-10s %s\n' "$pv" "$(tag_exists "app-v$pv" && echo published || echo 'not published → tool/release.sh app')"
  printf 'site    last change %s\n' "$(git log -1 --format=%cs -- site)"
  # Everything else that carries a version: a release is only complete when none of these is
  # behind. The integration was forgotten with 1.11.0 because it was not listed here.
  printf 'box     %-10s %s\n' "$av" "$(public_release_exists "$PUBLIC_REPO" "box-v$av" && echo published || echo "not published → push tag box-v$av, then tool/release.sh box $av")"
  printf 'desktop %-10s %s\n' "${pv%%+*}" "$(public_release_exists "$PUBLIC_REPO" "app-v$pv" && echo published || echo 'not published → tool/release.sh desktop')"
  local iv; iv=$(integration_version)
  printf 'integr. %-10s %s\n' "$iv" "$(public_release_exists "$HA_REPO" "v$iv" && echo published || echo 'not published → tool/release.sh integration')"
  local synced; synced=$(gh api "repos/$CODE_REPO/commits?per_page=1" --jq '.[0].commit.message' 2>/dev/null | head -1)
  printf 'source  %-10s %s\n' "${synced#Stand }" "$([ "$(git rev-parse -q --verify "${synced#Stand }^{commit}" 2>/dev/null)" = "$(git rev-parse origin/main)" ] && echo 'public source is at main' || echo 'behind main → tool/sync_public_source.sh')"
  cmd_verify_images "$av" || true
}

# The Busclear integration (ha-integration/, public repository KNX-Monitor-HA, installed through
# HACS): one commit per state, tag v<version>, and the GitHub release HACS offers as the update.
cmd_integration() {
  require_clean_main
  local iv; iv=$(integration_version)
  public_release_exists "$HA_REPO" "v$iv" && die "integration v$iv is already released – bump the version in $HA_MANIFEST"
  tool/sync_ha_integration.sh --release
}

case "${1:-}" in
  verify) cmd_verify ;;
  smoke) cmd_smoke ;;
  push) shift; wb_push "$@" ;;
  layout) wb_layout ;;
  check) cmd_check ;;
  addon) cmd_addon ;;
  site) shift; cmd_site "$@" ;;
  android) cmd_android ;;
  ios) cmd_ios ;;
  macos) cmd_macos ;;
  app) cmd_app ;;
  desktop) cmd_desktop ;;
  box) cmd_box "${2:-}" ;;
  integration) cmd_integration ;;
  status) cmd_status ;;
  notes) shift; wb_store_notes "$@" ;;
  devicetest) shift; wb_devicetest "$@" ;;
  verify-images) cmd_verify_images "${2:-}" ;;
  # For tests and for checking what a build would get, without building.
  rc-define) rc_define "${2:?RC_APPLE_KEY or RC_GOOGLE_KEY}" ;;
  desktop-run) desktop_run "${2:?tag}" ;;
  *) sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
