# MCP server for AI tools

The add-on and the box offer an MCP server (Model Context Protocol): AI tools
such as Claude read the recorded bus, the findings over a period and the
project check. Together with the MCP server of the
[XKNX Editor](xknx-editor.md) an assistant can go from "what is wrong" to a
correction in the project. Busclear itself never sends anything to the bus or
changes data through it.

## Switching it on

Off by default. An admin switches it on in the app under Exports › Continuous ›
"AI access (MCP)". The page shows the address, the token and the command for
Claude Code:

```bash
claude mcp add --transport http busclear http://<address>:8765/api/mcp --header "Authorization: Bearer <token>"
```

- Add-on: `http://<Home Assistant host>:8765/api/mcp`. The add-on runs in the
  host network; without the token the port only answers Home Assistant's
  Ingress. The connection in the home network is plain HTTP.
- Box: the box address (HTTPS when the box has its certificate).
- "Issue new token" invalidates the old one; switching off closes the endpoint.

The token opens nothing but `/api/mcp`. Whoever has it can read the whole
history, which reveals presence; the app says so next to the switch.

## Security

Reviewed on 9 November 2026. In place:

- **Token:** 32 random bytes (`Random.secure`), compared in constant time.
  A new token on every switch-on and on "issue new token". The token is
  stored in `mcp.json` in the data root, outside the file store
  (`/api/files` cannot serve it).
- **Scope:** the token opens only `POST /api/mcp`. The settings need the
  normal admin login (Ingress, or a box admin device).
- **Box:** with its certificate, the token is refused over plain HTTP, so it
  only crosses the network over HTTPS. The add-on has no HTTPS of its own;
  the app warns about that.
- **Limits:** request body at most 64 KiB, at most 10 messages per batch, one
  tool call at a time (others get `busy`), at most 31 days per call.
- **Read-only:** the tools only read history and project files. Day
  summaries for `findings` are computed in memory, nothing is written.
- **Errors:** internal error details go to the log, not to the client.
- **Browsers:** no CORS headers, and every call needs the `Authorization`
  header, so a web page cannot use the endpoint (DNS rebinding included).

Not covered: whoever holds the token can read the whole history, which
reveals presence. That is the purpose of the tool, so the switch is off by
default and the app explains it.

## Protocol

`POST /api/mcp` with `Authorization: Bearer <token>`, JSON-RPC 2.0 as in the
MCP Streamable HTTP transport, answers as `application/json` (no event
stream): `initialize`, `ping`, `tools/list`, `tools/call`. Notifications get
`202`. The settings live in `mcp.json` in the data folder
(`ha-addon/knx_monitor/server/lib/src/mcp_server.dart`); admins read and change
them with `GET`/`PUT /api/mcp/settings` through the normal login.

## Tools

All read-only (`readOnlyHint`), for the active installation
(`lib/src/mcp_tools.dart`):

| Tool | What it returns |
| --- | --- |
| `overview` | project name, numbers of group addresses and devices, recorded history (first day, days, size), connection state |
| `search_telegrams` | recorded group telegrams, newest first, filtered by group address, sender, type, time range (default 24 h, at most 31 days) and numeric value; with names, datapoint type, raw payload and value |
| `device_activity` | telegrams per day of one device, the group addresses it sent to, when it was last heard |
| `findings` | the installation report's findings over the last days (silent devices and cyclic values, stuck measurements, repetitions, bus load, outages, bus errors) with availability, traffic and load |
| `project_check` | the project check without bus traffic, the rules of the app's `ProjectLint` (`lib/src/project_lint.dart`); both are held to the same expected findings in `test/fixtures/project_lint/` (`project_lint_parity_test.dart` in app and server) |
| `project_vs_bus` | the project against the recorded bus (`lib/src/project_evidence.dart`): devices sending where the project says they cannot, commands whose status does not answer within 5 s, which of several project senders were really heard, unanswered reads of status addresses without R |
| `editor_handover` | corrections for the XKNX Editor's `project_batch` and notes for its comments, the format of the app's handover (`busclear-xknx-editor`) |

`findings` condenses days on demand in an isolate (or takes the report
service's stored daily summaries) and looks back as far again as the period
for "silent since".

## Project against bus

`project_vs_bus` and the app's project check (section "Project against bus",
add-on and box, from `GET /api/project-evidence?days=7`) read the history
against the project:

- **Device sends differently from the project**: a device of the project
  sends (write or response) on an address where it has no sending object in
  the project, or no object at all. The device does not carry the project;
  the XKNX Editor's download preview shows the difference. Tunnels and
  devices outside the project are left out (they have their own checks).
- **Command without feedback**: pairs of command and status address per
  actuator, from the project (same channel in the object text, or the same
  address name without the status words, and exactly one status). A command
  from another device counts as answered when the actuator sends on the
  status address within 5 s. Reported from 3 commands with at most half
  answered. Actuators that report only on a change can show up here too.
- **Several senders, confirmed**: the project's addresses with several
  senders, with the senders really heard.
- **Reads without answer**: status addresses without R that were read, with
  the number of answers within 3 s.
- **Datapoint type from the history**: for addresses without a type, a
  suggestion from the payload length, the values and words in the name (for
  example two bytes and "Temperatur" → 9.001), as a DPST token for the XKNX
  Editor's `set_group_address_dpt`. "high" certainty needs one payload length
  and a matching name.
- **State unusually long unchanged**: a contact, window or alarm address that
  kept sending 1 for at least two days, at least 10 times, without changing
  (a stuck contact or a wrong polarity).
- **Triggers at night**: presence or motion addresses triggering (1) between
  0 and 5 o'clock on at least half of the recorded nights, at least three,
  more than once per night.

