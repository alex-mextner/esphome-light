# esphome-light project notes

## HA config sync — keep `/config/esphome/` in step

Source of truth is this repo. The HAOS Dashboard add-on reads
`/config/esphome/*.yaml` directly — HA must mirror the repo. After ANY
edit to `esp32-c3-light.yaml` or `secrets.yaml`, sync to HA:

```bash
# credentials in .env (gitignored): HA_SSH_USER, HA_SSH_PASS, HA_HOST
source .env
sshpass -p "$HA_SSH_PASS" ssh "$HA_SSH_USER@$HA_HOST" 'sudo tee /config/esphome/esp32-c3-light.yaml > /dev/null' < esp32-c3-light.yaml
```

Note: SCP subsystem is disabled on this HA instance — use `ssh … sudo tee` pattern.

Or mirror the post-commit hook pattern from `../esphome-ir/scripts/sync-esphome-to-ha.sh`.

When the file list changes, remove the obsolete file on HA too:
```bash
sshpass -p "$HA_SSH_PASS" ssh root@192.168.0.25 'rm -f /config/esphome/<old>.yaml'
```

## Network layout

- `192.168.0.25` — homeassistant.local (HA)
- `192.168.0.18` — Ultras-MBP (dev Mac)
- esp32-c3-light — DHCP, use `esp32-c3-light.local` or HA dashboard for IP

## Hardware wiring

- **GPIO4** — PIR sensor signal (HC-SR501 or similar). No pullup needed —
  the sensor drives the line actively. Add `pullup: true` in pin config only
  for open-drain PIR modules.
- **GPIO2** — Transistor base via ~1kΩ resistor → LED strip. GPIO2 is a
  strapping pin on ESP32-C3 (internal pullup keeps it HIGH at boot), but the
  transistor may briefly turn the strip on at every power-up. Rewire to
  GPIO5/GPIO6 if that's unacceptable.

## Light logic

1. PIR motion or HA `light.turn_on` (from off) → `script.execute: light_timer`
2. Light fades in to `Target Brightness` over `Fade In Time` s (default 2 s).
3. Begins a step-based dim: every 10 s, brightness drops one step toward
   `Dim Floor` % over the full `Timer Duration` minutes. Each step issues
   `light.turn_on` so HA shows the current level within ~10 s.
4. Any motion, HA turn-on, or `Target Brightness` change while light is on
   restarts the countdown (`script.mode: restart`).
5. `Timer Duration` change does NOT restart — takes effect on next trigger.
6. HA `light.turn_off` stops the script immediately (`on_turn_off` handler)
   and starts a `Motion Block Duration` min cooldown (default 1 min) — PIR
   is ignored until it expires.
7. After the full dim, `light.turn_off` with 1 s transition.

## HA entities

| Entity | Purpose |
|--------|---------|
| `light.motion_light` | Main light, turn on/off from dashboards |
| `number.target_brightness` | Target brightness %, persisted |
| `number.timer_duration` | Fade-out duration in minutes, persisted |
| `number.motion_block_duration` | PIR cooldown after manual turn-off, min (0–60, default 1) |
| `number.fade_in_time` | Fade-in duration in seconds (1–10, default 2) |
| `number.dim_floor` | Bottom brightness before auto-off, % (1–50, default 10) |
| `switch.motion_detection` | Enable/disable PIR trigger |
| `binary_sensor.pir_motion` | Raw PIR state |
| `sensor.uptime`, `sensor.wifi_signal` | Diagnostics |
| `sensor.heap_free`, `sensor.loop_time` | Diagnostics |

## Flashing

First flash (USB cable) — port `/dev/cu.usbmodem2101`:
```bash
cd /Users/ultra/xp/esphome-light
esphome run esp32-c3-light.yaml --device /dev/cu.usbmodem2101
```

Subsequent OTA flashes (wireless):
```bash
esphome run esp32-c3-light.yaml --device esp32-c3-light.local
```

**WiFi instability**: this ESP32-C3 (same as esp32-c3-ir) frequently drops WiFi
and drops OTA mid-transfer. mDNS resolves fine via `dns-sd` but not via `ping`.
If OTA times out, plug USB and flash via `/dev/cu.usbmodem2101`.

Live logs:
```bash
esphome logs esp32-c3-light.yaml
# or one-process SSE (no API slot usage):
curl http://<ip>/events
```

## Diagnosis

- **Brief LED flash at boot**: expected — GPIO2 strapping pin behavior.
  See hardware wiring notes above.
- **PIR triggers when motion detection switch is off**: impossible by design
  (switch.is_on condition in on_press).
- **Light won't turn off after HA turn_off**: script is still running and
  countering — check that `g_scripting` isn't stuck `true` (would happen if
  the device rebooted mid-script). A reboot clears it (initial_value: false).
- **PIR unresponsive for ~60 s after power-on**: expected — `g_boot_done` starts `false`
  and is set `true` only after the 60 s `on_boot` delay (HC-SR501 warm-up window).
  Motion during this window is silently ignored. No action needed.
- **Transition math**: dim from 80% to 10% over 30 min at 1 kHz LEDC
  (16-bit = 65535 levels) with 10 ms update interval = ~180 000 steps,
  ~0.0004% per step — imperceptible moment to moment.
