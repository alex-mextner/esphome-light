# Plan: Fix ESPHome motion-light bugs and expose parameters to HA

## Overview

Fix 4 issues in `esp32-c3-light.yaml` and create an HA automation file:

1. **Bug 1** — HA immediately shows 10% brightness after motion stops, even though the
   physical light is at full brightness. Root cause: a single `light.turn_on` with a
   30-minute `transition_length` tells HA the *target* state (10%) right away; HA has
   no concept of in-progress transitions. Fix: replace one long transition with a `while`
   loop that steps brightness every 10 s so HA always shows the current physical level.

2. **Bug 2 + missing parameters** — `motion_block_duration` is hardcoded (30 s). The user
   wants ALL configurable values in HA. Add `number` entities for:
   - Motion Block Duration (how long PIR is ignored after manual turn-off, default 1 min)
   - Fade-in Time (currently hardcoded 2 s)
   - Dim Floor (the bottom brightness the light dims to, currently hardcoded 10%)
   The existing step-brightness loop also needs these globals to drive the math.

3. **Feature** — When the user manually disables Motion Detection in HA, auto-enable it
   again after 4 hours. Implemented as an HA automation YAML file.

4. **Bug 4** — Light sometimes turns on without any command or motion. Root cause:
   HC-SR501 is electrically unstable for the first 30–60 s after power-on (manufacturer
   spec), and the 50 ms `delayed_on` filter is insufficient for RF/conducted noise on
   GPIO4. Fix: add a 60 s post-boot startup delay (global flag `g_boot_done`) before
   PIR triggers are honoured, and increase `delayed_on` to 500 ms.

## Validation Commands

- `esphome config esp32-c3-light.yaml`
- `yamllint -d relaxed motion-detection-auto-enable.yaml`

### Task 1: Replace long dim transition with step-based while loop (Bug 1)

Context: the current `light_timer` script issues one `light.turn_on` with
`brightness: 10%` and `transition_length: timer_duration * 60 s`. HA reports the
target immediately. Replace with a `while` loop that decrements brightness by a
calculated step every 10 s using two new `float` globals: `g_dim_brightness` and
`g_dim_step`.

- [x] Add globals `g_dim_brightness` (float, initial 0.0) and `g_dim_step` (float, initial 0.0)
- [x] Replace the current step-3 `light.turn_on` + step-4 `delay` pair inside
      `light_timer` with a lambda that calculates step size, then a `while` loop
      that decrements brightness and calls `light.turn_on` with `transition_length: 10s`
      followed by `delay: 10s` per iteration; the loop exits when brightness reaches
      the Dim Floor value
- [x] The `g_scripting` guard must be set true/false around each `light.turn_on`
      inside the loop, same as existing calls
- [x] Verify the script structure with `esphome config esp32-c3-light.yaml`

### Task 2: Add configurable parameters to HA (Bug 2 + missing params)

Context: expose every hardcoded constant as a `number` entity so users can tune from HA.

- [ ] Add `number` entity `motion_block_duration` — min 0, max 60, step 1, unit min,
      default 1, restore_value true
- [ ] Add `number` entity `fade_in_time` — min 1, max 10, step 1, unit s,
      default 2, restore_value true
- [ ] Add `number` entity `dim_floor` — min 1, max 50, step 1, unit %, default 10,
      restore_value true
- [ ] Update `motion_block_timer` to use `motion_block_duration` (convert min→ms)
      instead of the hardcoded `30s`
- [ ] Update `light_timer` fade-in step to use `fade_in_time` number entity for
      `transition_length` and the post-fade-in `delay`
- [ ] Update `light_timer` while-loop exit condition and floor `light.turn_on` call
      to use `dim_floor` instead of hardcoded `10%` / `0.10f`
- [ ] Verify with `esphome config esp32-c3-light.yaml`

### Task 3: HA automation — auto-enable motion detection after 4 hours (Feature)

Context: when the user turns off the Motion Detection switch in HA, it should
re-enable itself automatically after 4 hours. Implemented as a standalone HA
automation YAML that can be pasted into `automations.yaml` or imported via UI.

- [ ] Create `motion-detection-auto-enable.yaml` with an automation triggered by
      `switch.motion_detection` going to `off` for 4 hours, action `switch.turn_on`
- [ ] Include a comment at the top explaining how to add it to HA
- [ ] Validate with `yamllint -d relaxed motion-detection-auto-enable.yaml`

### Task 4: Fix phantom turn-ons — startup delay + better PIR filtering (Bug 4)

Context: HC-SR501 specification says to ignore its output for 60 s after power-on.
The existing `delayed_on: 50ms` is too short for the RF noise observed on GPIO4.

- [ ] Add global `g_boot_done` (bool, initial false, restore_value no)
- [ ] Add `on_boot` hook in the `esphome:` section with priority -100, delay 60 s,
      then set `g_boot_done = true`
- [ ] Add `g_boot_done` as a third condition in the PIR `on_press` handler
      (alongside `switch.is_on: motion_enabled` and `!g_motion_blocked`)
- [ ] Increase PIR `delayed_on` filter from 50 ms to 500 ms
- [ ] Verify with `esphome config esp32-c3-light.yaml`
