# SAHBI Robot Protocol v1

Status: **design + reference implementation in the app.** There is **no SAHBI hardware**. What exists:

| Piece | State |
|---|---|
| Message codec, validation, safety limits (`lib/features/robot_link/protocol.dart`) | Implemented, unit-tested |
| BLE framing + CRC + reassembly | Implemented, unit-tested |
| `SimulatedRobotTransport`: in-process fake device, talks through real BLE frames | Implemented, unit-tested, visible in Settings → Debug |
| `LocalPhoneTransport`: the phone screen is the face (default) | Implemented |
| `BleTransport` | **Skeleton.** The protocol logic is complete, but no BLE plugin is bundled. It needs a `BleLink` adapter (e.g. flutter_blue_plus) and is hidden behind the "Robot (experimental)" flag |
| `WifiTransport` (WebSocket) | **Skeleton.** It compiles, but there is no device to talk to, so it is untested against hardware |

The phone stays the brain (LLM, STT, TTS, memory). The robot is face, ears and mouth. That is deliberate: existing pocket robots are limited by battery life (around 1–2 h) and by depending on Wi-Fi. BLE keeps the robot cheap and low-power, and the phone already has the connectivity.

## 1. Transports

### 1.1 BLE GATT (primary)

Custom 128-bit UUIDs. These were randomly generated for SAHBI and are not SIG-assigned:

| Role | UUID | Properties |
|---|---|---|
| Service | `7a1b0001-5a48-4249-9c3e-6d0b5e1f2a10` | primary |
| Command (app → robot) | `7a1b0002-5a48-4249-9c3e-6d0b5e1f2a10` | write, write-without-response |
| Event (robot → app) | `7a1b0003-5a48-4249-9c3e-6d0b5e1f2a10` | notify |
| Telemetry (robot → app) | `7a1b0004-5a48-4249-9c3e-6d0b5e1f2a10` | notify (battery, IMU at a low rate) |

The app requests MTU 247 and falls back to the default 23.

### 1.2 Wi-Fi WebSocket (optional, for audio streaming)

- `wss://<robot-ip>:<port>/sahbi/v1`, one JSON message per text frame (no BLE framing).
- Binary frames carry `audio.stream` PCM chunks: 16 kHz, mono, 16-bit LE.
- The first message must be `system.hello` with the pairing token (see §7).

## 2. Message format (both transports)

UTF-8 JSON object:

```json
{"v":1, "seq":42, "type":"face.set_emotion", "payload":{"emotion":"happy","intensity":0.7}, "ack":true}
```

| Field | Rule |
|---|---|
| `v` | protocol version, integer. Other versions are rejected with error 1 |
| `seq` | 0–65535, increments per sender and wraps |
| `type` | one of the commands/events below. Anything else gets error 2 |
| `payload` | object, optional |
| `ack` | if true, the receiver must answer `ack` (or `error`) with `payload.ref = seq` |

## 3. BLE framing

Each message gets a CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, check value of `"123456789"` = 0x29B1), big-endian, appended. The result is split into fragments of `(MTU − 3) − 6` bytes, each with a 6-byte header:

| Byte | Meaning |
|---|---|
| 0 | frame version (1) |
| 1 | flags: bit0 = first, bit1 = last |
| 2–3 | message seq, big-endian |
| 4 | fragment index |
| 5 | fragment count (≤ 255) |

The receiver reassembles per seq (fragments may arrive out of order and interleaved) and verifies the CRC. On a mismatch it drops the message and emits error 3.

## 4. Handshake, heartbeat, timeouts

1. The app sends `system.hello` `{protocol: 1, app: "sahbi", token?}`.
2. The robot answers `system.hello_ack` `{ref, protocol, device_id, fw, capabilities[], battery}`, or `error` 1 if the version doesn't match.
3. The app sends `system.ping` every **2 s**. With no traffic for **6 s**, the link is considered lost: pending acks fail with a timeout, and the robot must stop its motors.
4. Ack timeout: 2 s by default.

Capabilities are strings: `face`, `audio`, `touch`, `presence`, `imu`, `battery`, `motor`. The app only sends commands for advertised capabilities.

## 5. Command set (app → robot)

| Type | Payload | Notes |
|---|---|---|
| `system.hello` | `{protocol, app, token?}` | §4 |
| `system.ping` | – | robot replies `system.pong {ref}` |
| `system.reboot` | – | ack, then reboot |
| `system.ota_info` | – | robot replies `system.ota_info {fw, update_available}`. **OTA itself is out of scope for v1** |
| `face.set_emotion` | `{emotion, intensity 0..1}` | emotions: neutral, happy, sad, curious, surprised, sleepy, angry, listening, speaking, music |
| `face.look` | `{x −1..1, y −1..1}` | gaze target |
| `face.speak_start` / `face.speak_stop` | – | mouth animation on/off |
| `face.viseme` | `{v, t_ms}` | optional stream. The app's mouth sync is **approximate** (word boundaries or a synthetic envelope), not true lip-sync |
| `audio.play` | `{id}` | built-in sound |
| `audio.stop` | – | |
| `audio.volume` | `{level 0..1}` | |
| `audio.stream` | Wi-Fi only | binary PCM frames |
| `sensor.subscribe` | `{sensors: ["touch","presence","imu","battery"], rate_hz?}` | |
| `motor.move` | `{left −1..1, right −1..1, duration_ms}` | **safety-limited**, §6 |
| `motor.stop` | – | immediate |

## 6. Motor safety (hard limits, enforced on both sides)

- |speed| ≤ **0.5**. `RobotCodec.encode` refuses larger values (error 5, `safetyLimit`) before anything is sent. Firmware must clamp too.
- `duration_ms` must be an integer in **1–2000**.
- **Watchdog 500 ms.** The motor stops unless refreshed by another `motor.move` within 500 ms, whatever the duration. This is tested against the simulator.
- If the link is lost (no heartbeat for 6 s), the motors stop.
- Low battery may refuse movement with error 7.

## 7. Security

- BLE: LE Secure Connections pairing with bonding (numeric comparison when the robot has a screen). Unbonded centrals may only call `system.hello` and `system.ota_info`.
- The pairing token is shown on the robot screen or as a QR code, stored in the app's secure storage, and sent in `system.hello`. Wrong token: error 6.
- No Wi-Fi credentials or API keys ever cross this protocol in plaintext. The robot never talks to the LLM or the backend directly.
- Android permissions: BLUETOOTH_SCAN (`neverForLocation`) and BLUETOOTH_CONNECT on Android 12+, requested only when the user opens Robot settings. **The current build does not scan**, so BLUETOOTH_SCAN is not declared yet. Add it together with a real `BleLink`.

## 8. Events (robot → app)

`ack {ref}`, `error {ref, code, message?}`, `system.hello_ack`, `system.pong {ref}`, `system.ota_info`, `sensor.touch {zone, kind: tap|long|stroke}`, `sensor.presence {present, distance_m?}` (mmWave), `sensor.imu {ax, ay, az, gx, gy, gz}`, `sensor.battery {level 0..1, charging?}`, `telemetry {...}`.

## 9. Error codes

| Code | Name | Meaning |
|---|---|---|
| 1 | unsupportedVersion | protocol/frame version mismatch |
| 2 | unknownCommand | type not in this spec |
| 3 | badPayload | invalid JSON, missing fields, CRC error |
| 4 | busy | try again later |
| 5 | safetyLimit | motor command outside limits |
| 6 | auth | missing/wrong pairing token |
| 7 | lowBattery | refused to save power |
| 8 | internal | firmware fault |
| 9 | timeout | no ack / link lost |

## 10. Hardware reference (documentation only, nothing built)

- ESP32-S3 (BLE 5 + Wi-Fi, PSRAM) for the face, audio I/O and sensors.
- 1.5–2" colour IPS LCD for the face (the same CustomPainter shapes, ported).
- I2S MEMS mic array (2–3 mics) feeding the phone for STT, plus an I2S amp and speaker.
- Capacitive touch pads, optional 60 GHz mmWave presence sensor, IMU.
- Li-Po with a fuel gauge. Optional micro-gear motors behind the safety layer above.

## `behavior.state` (app → robot, MIMO mood) — added in v1.x, optional

Sent whenever MIMO's autonomous mood changes (`MimoBehaviorEngine`, pure
Dart in `lib/features/behavior/`). A robot body uses it to animate its own
display / servos the same way the phone face does. Robots that do not know
the message ignore it (unknown types are acked with `ok:false`).

```json
{"v":1,"id":42,"type":"behavior.state",
 "payload":{"state":"bored","blink_min_s":4,"blink_max_s":8,"lid":0.45,"widen":0}}
```

| state | meaning | eyes |
|---|---|---|
| `idle` | calm, looks around now and then | normal blink 3–5.5 s |
| `curious` | something moved in front of it | wide, quick glances |
| `playful` | touched / playing a game | fast blinks, double blinks |
| `bored` | ignored ≥ 5 min | lids half down, slow wander |
| `sleepy` | ignored ≥ 9 min or quiet hours | lids mostly down |
| `listening` | "MIMO" heard / conversation | wide, steady, no blinking |

NOT VERIFIED on real hardware (no robot exists yet).
