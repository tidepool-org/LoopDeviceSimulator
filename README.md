# LoopDeviceSimulator

LoopDeviceSimulator provides generic CGM and pump implementation that use bluetooth to support design, quality assurance, and rapid prototyping of the Tidepool Loop app. The current CGM and pump implementations use the Bluetooth SIG standard services: Continuous Glucose Monitor service, Insulin Delivery Service, Authorization Control Service, Device Time Service, etc.

## Session log

Every Bluetooth transaction, tester action and lifecycle event is recorded to a session log on the device, which the Session Log screen can share as JSON Lines or plain text. The fields, kinds and both renderings are documented in [docs/SESSION-LOG-FORMAT.md](docs/SESSION-LOG-FORMAT.md).
