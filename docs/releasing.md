# Releasing

Everything goes through one entry point, `tool/release.sh`. `tool/release.sh
verify` runs the same checks as the CI and is the step before every push.

## Home Assistant add-on

Home Assistant reads add-on versions from the public repository
[regetskcob/KNX-Monitor](https://github.com/regetskcob/KNX-Monitor), which is
the add-on repository users add. It must only ever offer versions whose images
exist.

1. Bump `version` in `ha-addon/knx_monitor/config.yaml`, extend
   `ha-addon/knx_monitor/CHANGELOG.md` and commit.
2. Run `tool/release.sh addon`. It pushes the tag `addon-v<version>`, waits
   until `.github/workflows/addon.yml` has built both images (amd64, aarch64),
   checks that both carry the version and `latest`, and only then runs
   `tool/sync_public.sh`. That copies the add-on files of the tag into the
   add-on repository and creates the GitHub release there.
3. The packages `amd64-knx-monitor` and `aarch64-knx-monitor` are public on
   GHCR, so Home Assistant can pull them without credentials.

How the images are signed and how to verify them:
[release-security.md](release-security.md).

## KNX Box and Linux app

Box images are built by `.github/workflows/box-image.yml` from a
`box-v<version>` tag, see [knx-box.md](knx-box.md). The Linux app is built by
the `linux` job of `.github/workflows/ci.yml` on an `app-v<version>` tag and
attached to the release in the add-on repository.

## Source code

The public source tree is built from the development repository by
`tool/export_public_source.sh` and published with
`tool/sync_public_source.sh --push`, one commit per release.
