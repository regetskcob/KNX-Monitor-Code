# Release and supply chain security

The Home Assistant add-on runs with host networking and access to the Home
Assistant API. Whoever can push an image to `ghcr.io/regetskcob/*-knx-monitor`
controls the KNX bus of every installation that updates. The path from source
to image is therefore protected in several layers. The same applies to the
Docker image and the KNX Box image.

Part of this is checked by a test, so a change to a workflow that drops a
protection fails CI: `ha-addon/knx_monitor/server/test/supply_chain_test.dart`.

## Workflows

Workflows: `.github/workflows/addon.yml` (add-on and Docker images),
`.github/workflows/box-image.yml` (KNX Box package and Raspberry Pi image),
`.github/workflows/ci.yml` (checks).

- **Actions pinned to commit SHAs.** Every `uses:` names a full 40-character
  commit SHA, with the version as a comment (`# v4.4.0`). A moved tag in a
  third-party action changes nothing. Dependabot proposes updates monthly
  (`.github/dependabot.yml`), also for SHA pins; security updates arrive
  independently of that schedule.
- **Least privilege.** The default token permission of `addon.yml` is
  `contents: read`. Only the jobs `image` and `latest` get `packages: write`.
  The web build and the smoke test (which use `subosito/flutter-action`) run
  with read access only.
- **`id-token: write` only where signing happens:** the two publishing jobs in
  `addon.yml` and the two signing jobs in `box-image.yml`.
- **Approval gate.** Before images are pushed, the job `approve` runs in the
  environment `addon-release`. It is meant to wait for a required reviewer.
  Required reviewers are not available for this repository on its current
  GitHub plan, so the job currently passes without waiting; it becomes effective
  once the plan allows it.
- **Pinned base images.** The add-on's build stage uses `dart:<version>` pinned
  by digest (`ha-addon/knx_monitor/Dockerfile`); the runtime image is built
  `FROM scratch` with only the compiled server, the Dart runtime files, time zone
  data and the web app. Dependencies are fetched with
  `dart pub get --enforce-lockfile`. Dependabot raises the digest. The KNX Box
  image is built with pi-gen at a fixed tag and a verified commit
  (`box-image.yml`, `box/build-image.sh`, `PI_GEN_COMMIT`); a mismatch aborts
  the build. The pi-gen version is raised by hand.
- **Fixed versions for users.** The Docker template names a fixed version, not
  `latest` (`tool/public-repo/docker/compose.yaml`; `tool/sync_public.sh` sets it
  from the release tag).

## Signatures and checksums

Images and box artefacts built from release tags are signed with
[cosign](https://github.com/sigstore/cosign), keyless: the signing certificate
is issued for the GitHub Actions workflow identity (OIDC), and no long-lived
signing key exists. Signing was introduced with version 1.9.2; older releases
are not signed.

| Artefact | Signature | Checksums |
|---|---|---|
| Add-on images `ghcr.io/regetskcob/{aarch64,amd64}-knx-monitor` | cosign (OCI) | – |
| Docker image `ghcr.io/regetskcob/knx-monitor` | cosign (OCI) | – |
| KNX Box package and image | `*.sigstore.json` bundles | `SHA256SUMS.txt` |
| Linux desktop release | – | `SHA256SUMS.txt` |

If signing fails, the workflow run fails and `latest` is not moved.

### Verifying

```sh
# Add-on (<arch>-knx-monitor) and Docker (knx-monitor)
cosign verify ghcr.io/regetskcob/knx-monitor:<version> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/regetskcob/[^/]+/\.github/workflows/addon\.yml@refs/tags/addon-v'

# KNX Box package and image
cosign verify-blob knx-box-<version>.tar.gz --bundle knx-box-<version>.tar.gz.sigstore.json \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/regetskcob/[^/]+/\.github/workflows/box-image\.yml@refs/tags/box-v'

# Checksums
sha256sum -c SHA256SUMS.txt
```

The identity pattern pins the owner, the workflow file and the tag prefix.
Every signature is recorded in the public Rekor transparency log, including the
repository, workflow and tag that produced it.

Home Assistant does not verify signatures itself. They let users check an image
after the fact and reveal an image that was replaced under an existing tag.

## Branch and tag protection

- **`main` only through pull requests.** A ruleset forbids direct pushes,
  force pushes and deletion of `main`, without exceptions. The release script
  (`tool/release.sh addon`) opens a pull request for the version bump, waits for
  CI and merges it with a merge commit, so the release tag stays in the history
  of `main`.
- **Release tags.** A tag ruleset restricts creating, updating and deleting the
  tags `addon-v*`, `app-v*` and `box-v*` to the repository administrator.
  Workflows (`GITHUB_TOKEN`), deploy keys and collaborators with write access
  cannot create release tags.
- **Actions settings.** The default workflow token is read-only (workflows
  request more themselves), and GitHub Actions may not create or approve pull
  requests.

These settings live in GitHub, not in the repository, and cannot be checked from
the code. The same holds for the remaining recommendations: only the building
repository's workflows should have write access to the container packages, and
the maintainer account should use two-factor authentication with a passkey or
security key and only fine-grained personal access tokens with an expiry date
and without `workflow` or `write:packages` scope unless needed.

## What this does not cover

- Whoever takes over the maintainer's GitHub account can change settings and
  workflows. Only the account protection above helps against that.
- Whoever can push commits can also change the workflow in a tagged commit and
  remove the `approve` job. SHA pins and the approval gate protect against
  compromised third-party actions, stolen tokens without tag permission and
  accidental tags, not against an attacker with full write access. That is why
  the tag ruleset matters.
- The public repository `regetskcob/KNX-Monitor`, which carries the add-on
  metadata and the releases, has its own settings; overwriting a release there
  is not prevented by the rules above.
- Image tags in ghcr.io can be overwritten. Home Assistant offers a new version
  only once `config.yaml` in the public repository names it, and
  `tool/release.sh` pushes that file only after the images. But an image
  overwritten under an already published version would reach new installations.
  Signatures make such a replacement detectable, not impossible.
