# LoopDeviceSimulator

LoopDeviceSimulator provides generic CGM and pump implementation that use bluetooth to support design, quality assurance, and rapid prototyping of the Tidepool Loop app. The current CGM and pump implementations use the Bluetooth SIG standard services: Continuous Glucose Monitor service, Insulin Delivery Service, Authorization Control Service, Device Time Service, etc.

## Test tool, not a medical device

The simulator is a software test tool for engineers and testers. It is not a medical device, and the pump it presents over Bluetooth is a simulation that cannot command any physical infusion pump: no insulin is ever delivered. A notice bar on every screen says so; tapping it opens the full wording and the simulator version.

## Session log

Every Bluetooth transaction, tester action and lifecycle event is recorded to a session log on the device, which the Session Log screen can share as JSON Lines or plain text. The fields, kinds and both renderings are documented in [docs/SESSION-LOG-FORMAT.md](docs/SESSION-LOG-FORMAT.md). The simulator version is recorded at every launch and every server start, and in the header of the text export.

## Defaults and reset

Tester settings, pairings and device history survive an application restart. "Reset to Defaults" on the root screen puts everything below back and forgets all pairings and history; the session log is kept.

| Setting | Default |
|---|---|
| Server name override | blank (pump advertises `Tidepool-Pump-Simulator`, CGM `Tidepool-CGM-Simulator`) |
| Authorization Control (pump and CGM) | off, no stored pairing |
| Pump behaviour | on |
| Pump command response override | Normal |
| Pump server busy, procedure in progress, out-of-range schedule, ready to disconnect | off (session stimuli, cleared whenever the server stops, not kept across relaunch) |
| Pump device bolus entry | 1.0 U |
| Pump Feature flags | Basal Rate, TBR Absolute, Bolus Fast, Bolus Activation Type (E2E Protection off) |
| Pump history | the kit's sample history |
| CGM encrypted link | off |
| CGM communication interval | 5 min |
| CGM records per notification | 8 |
| CGM record capacity | the kit default |
| CGM backfill duration | 1 h |
| CGM calibration schedule | once per session |
| CGM warm-up | 1 min |
| CGM glucose source | the bundled "Normal Trace" scenario |
| CGM trace effects | none |
| CGM alert levels | 250 / 70 / 55 / 300 mg/dL, −3 / +3 mg/dL/min |
| CGM sensor range | 40 to 400 mg/dL |
| CGM session run time | 240 h |
| CGM clock offset | 0 min |
| CGM feature, manual status bits | the kit defaults, none set |
| CGM measurement database | empty |
