# HYDRA session log format

The simulator records everything that happens while it runs: every Bluetooth transaction it takes part in,
every action a test engineer takes in the UI, and lifecycle events such as a server starting or a pairing
being restored. The log is written as it happens to one file on the device and survives relaunches and
reboots. The Session Log screen (Diagnostics on the root list, or the toolbar button on either server
screen) shows it, filters it by kind, clears it, and shares it in the two renderings described here.

## Timestamps

Every entry carries one timestamp: the host clock at the moment the entry was recorded, in UTC, as ISO 8601
with millisecond precision and a `Z` suffix:

```
2026-11-03T14:22:01.123Z
```

This is the encoding Tidepool Loop uses for its own device log when it is exported (LoopKit's critical
event log writes device log timestamps with `ISO8601DateFormatter` in UTC with fractional seconds), so lines
from a HYDRA export and a Loop export sort and align on the timestamp column without conversion. The two
devices keep their own clocks; with both set automatically they agree to well under a second, which is
finer than Bluetooth connection intervals. The sequence number is the tie-breaker within HYDRA's own log,
not across devices.

## Fields

| Field | Values | Meaning |
|---|---|---|
| `id` | integer from 1 | Sequence number. Increases across launches until the log is cleared; survives rotation. |
| `timestamp` | ISO 8601 UTC | When the entry was recorded (see above). |
| `mode` | `pump`, `cgm`, `acs`, `app` | Which simulated device was active: insulin pump, CGM sensor, the standalone Authorization Control client, or nothing (app-level lines). |
| `role` | `server`, `client`, `tester` | `server` is the simulated device, `client` the simulator acting as a collector or controller, `tester` an action from the UI. |
| `kind` | `connection`, `read`, `write`, `notify`, `indicate`, `stimulus`, `lifecycle`, `trace`, `error` | What the line is (see below). |
| `scenario` | text or absent | The active glucose source for the CGM (scenario name, or a constant or sine description); `mock pump` for the pump; absent for app-level lines. |
| `scenarioVersion` | text or absent | What makes the scenario reproducible, currently the trace-effects seed when effects are on. |
| `detail` | free text | The message. Bluetooth lines name the characteristic UUID, the central where one is involved, the payload in hex, and the ATT result. |

### Kinds

| Kind | Source |
|---|---|
| `connection` | Advertising and radio state, a central subscribing or unsubscribing, a client connecting or disconnecting. |
| `read` | A read request received by a server (with the response and result) or sent by a client. |
| `write` | A write request received by a server (with the payload and result, including forced refusals) or sent by a client, and the client's write response. |
| `notify` | A notification pushed by a server, or a reading captured for one. |
| `indicate` | An indication pushed by a server, and indication handling in the kits. |
| `stimulus` | Something the test engineer did in the UI: toggles, forced states, injected values and faults, commands issued from a client screen. The detail names the control and the value, for example `Next Payload Fault armed: corrupt CRC`. |
| `lifecycle` | Server or client started or stopped, pairing or history restored or forgotten, app launched, log cleared. |
| `trace` | Everything else the kits print, such as message-queue pacing. |
| `error` | Integrity faults, failures, and ATT error responses. |

The kind of a kit line is decided from its words when it is recorded; the rule lives in
`SessionLog.kind(of:)`. Anything unrecognised becomes `trace` rather than being dropped.

## JSONL rendering

The file on the device, and the "Share as JSONL" export, is JSON Lines: one JSON object per line, UTF-8,
`\n` terminated, fields as above, absent optionals omitted.

```
{"id":412,"timestamp":"2026-11-03T14:22:01.123Z","mode":"cgm","role":"tester","kind":"stimulus","scenario":"Normal Trace","detail":"Start Session"}
{"id":413,"timestamp":"2026-11-03T14:22:01.131Z","mode":"cgm","role":"server","kind":"lifecycle","scenario":"Normal Trace","detail":"startSession(source:): session started at 2026-11-03 14:22:01 +0000"}
{"id":414,"timestamp":"2026-11-03T14:23:01.204Z","mode":"cgm","role":"server","kind":"notify","scenario":"Normal Trace","detail":"Notify 2AA7 to all subscribed centrals data: 0E00B2C03C00..."}
```

The device file is `Application Support/HYDRA/session-log.jsonl`. At 20 MB it is rotated to
`session-log.previous.jsonl` and a new file starts; the sequence numbers continue. The export is a copy of
the current file taken between writes, so no line is torn.

## Text rendering

"Share as text" renders the same entries one per line, fixed-order fields separated by single spaces, the
detail last so it may contain spaces. Two comment lines open the file.

```
# HYDRA session log, exported 2026-11-03T15:00:00.000Z by DeviceSimulator 1.0 (42)
# timestamp(UTC) #seq mode role kind [scenario | version] detail
2026-11-03T14:22:01.123Z #412 cgm tester stimulus [Normal Trace] Start Session
2026-11-03T14:22:01.131Z #413 cgm server lifecycle [Normal Trace] startSession(source:): session started at 2026-11-03 14:22:01 +0000
2026-11-03T14:23:01.204Z #414 cgm server notify [Normal Trace | effects seed 7] Notify 2AA7 to all subscribed centrals data: 0E00B2C03C00...
2026-11-03T14:23:05.000Z #415 app tester lifecycle log cleared
```

- The bracketed scenario group is present only when the entry has a scenario; the ` | version` part only
  when it has a scenario version.
- Newlines inside a detail are written as the two characters `\n`, so every entry is exactly one line and
  the file can be grepped and joined with a Loop export line by line.
