# Resilience tests on real hardware

What can be checked without hardware runs automatically:

| What | Where | Runs |
| --- | --- | --- |
| Rollback of `setup.sh` (update, silent server, `--rollback`, firewall stays) | `box/test-setup.sh` | `tool/release.sh verify`, `box-image.yml` |
| Health endpoint `/healthz` and `watchdog` in `config.yaml` | `ha-addon/knx_monitor/server/test/server_process_test.dart` | `tool/release.sh verify` |
| Upgrade old → new → old → new with real server versions, without Docker | `tool/addon_upgrade_test.sh [tag]` | by hand, before every add-on release |
| Image starts, data survives a restart | smoke test in `.github/workflows/addon.yml` | on add-on tags |

What only real devices show is covered by the three procedures below. None of
them runs automatically.

## 1. Add-on watchdog on a real Home Assistant

**Why:** Whether the Supervisor reaches the add-on in the host network at
`http://[HOST]:8765/healthz` can only be seen there. If it does not, it keeps
restarting an add-on whose watchdog is switched on. The watchdog is a
per-installation switch and off by default, so an update alone changes
nothing for anyone.

**Procedure** (preferably on a test installation, not on a production system):

1. Install the add-on in this version, switch on **Watchdog** under *Info*,
   start it.
2. Wait ten minutes. The Supervisor log (*Settings › System › Logs ›
   Supervisor*) must not contain `Watchdog found a problem with … application`.
   If it does, switch the watchdog off: the problem is reachability, not the
   server.
3. Simulate a hang, via SSH on the host:
   `docker pause addon_<slug>_knx_monitor`. Within one to two minutes the
   Supervisor must restart the container (`docker unpause` is then no longer
   needed).
4. Simulate a crash: `docker kill addon_<slug>_knx_monitor`. The add-on must
   come back. Afterwards *Recordings › History* and the start status show an
   unexpected restart with its time.
5. Stop it normally from the UI: this must **not** count as an unexpected
   restart.

**Passed when:** step 2 stays quiet, steps 3 and 4 bring the add-on back, and
only those two count as restarts.

## 2. Rollback of `setup.sh` on a real box

**Why:** `box/test-setup.sh` stubs `systemctl` and `curl`. Whether the check
works with real systemd, permissions and file system only a Raspberry Pi
shows.

Use a box whose data you can lose, connected by LAN cable. Before starting,
note `sudo cat /opt/knx-box/VERSION` and `ls -la /var/lib/knx-box`.

1. **Update:** unpack the new package, run `sudo ./setup.sh --yes`. Expected:
   new `/opt/knx-box/VERSION`, `server.prev` and `web.prev` present, box
   reachable in the browser, password and Wi-Fi unchanged, history intact.
2. **Automatic rollback:** in the unpacked package, replace the server with a
   program that exits at once (`printf '#!/bin/sh\nexit 1\n' >server`), run
   `sudo ./setup.sh --yes`. Expected: message that it goes back to the
   previous version, non-zero exit code, `/opt/knx-box/VERSION` back to the
   previous one, `systemctl is-active knx-box` active.
3. **Silent server:** as 2, but with `printf '#!/bin/sh\nsleep 600\n' >server`
   (runs, does not answer). Expected: the same after about 40 seconds of
   health checks.
4. **Manual:** install the real new package again, then
   `sudo ./setup.sh --rollback`. Expected: "back to …"; a second `--rollback`
   reports that there is no previous version.
5. **Firewall:** before and after every step, `sudo nft list table inet knx_box`
   and `systemctl is-enabled knx-box-firewall` must be unchanged. A box with
   `INTERNET_SHARING=yes` keeps its disabled firewall after the update.
6. **Reboot:** `sudo reboot`. The box comes back with the current version and
   no unexpected restart is counted. Then pull the power plug and plug it in
   again: exactly one unexpected restart, reason "host restarted".

## 3. Add-on upgrade with a test tag

**Why:** the path through the image and the Supervisor (backup before the
update, `/data`, Ingress) can only be checked with a real image. Run
`tool/addon_upgrade_test.sh` first.

A tag with a hyphen, e.g. `addon-v1.10.0-test1`, builds and publishes only the
image of that version; `latest` stays where it is (`addon.yml`). As long as
the version is not listed in the public add-on repository, Home Assistant
offers it to nobody.

1. On a branch, set `version: "1.10.0-test1"` in
   `ha-addon/knx_monitor/config.yaml`, commit, `git tag addon-v1.10.0-test1`,
   push the tag and wait for `addon.yml`.
2. On the test installation, copy `ha-addon/knx_monitor` with the **old**
   `config.yaml` (version of the last release, `image:` unchanged) to
   `/addons/knx_monitor`. *Add-on Store › ⋮ › Check for updates*, install the
   **local** add-on, set the gateway, import a project, enable continuous
   recording and collect a day of history. Local add-ons have their own data
   folder; an installed regular Busclear stays untouched.
3. Put the new `config.yaml` (version `1.10.0-test1`) on top, *Check for
   updates*, update with backup. Check: gateway connected, catalog present,
   history complete up to the update, gap only for the duration of the
   update, `/api/report` off, no restart counted.
4. Restore the backup (*Settings › System › Backups*). Check: old version, old
   data, everything running.
5. Clean up: remove the local add-on, delete tag and image
   (`git push origin :addon-v1.10.0-test1`, package version in GitHub
   Packages).

**Long-term run:** the actual goal – three months without intervention, with
reports delivered – only shows on a box in the field: enable the report, check
the first report at the turn of the month, unplug a device and see it appear
in the next report.

## Results: Raspberry Pi 4 (box 1.9.1)

| Check | Result |
| --- | --- |
| Update 1.8.3 → 1.9.1 with `setup.sh --yes` | passed; data and firewall unchanged |
| Rollback with a dead server | passed |
| Rollback with a silent server | passed (79 s including setup) |
| `--rollback` by hand | passed |
| Reboot | not counted as a restart |
| Password check | runs in its own isolate with 40,000 PBKDF2 rounds: first sign-in 6.5 s instead of 33 s, the server stays reachable meanwhile |
| Mac and iPad app against the box | passed (`integration_test/box_session_test.dart`) |
| Pulling the power plug | not yet tested |

Tested without a bus: the HAT reported no bus voltage.
