# Final Practicum — Open Industry Project build

Nautilus controller for the Open Industry Project (OIP) conversion of the Spring 2026 Final Practicum
scene (the `oip/` folder of this repo).

The three controller implementations in `lib/` (`practicum_st.st`, `practicum_ld.ld`,
`practicum_fbd.fbd`) are the same as in the Factory I/O version of the project. The `LanguageSelect`
setpoint (1 ST, 2 LD, 3 FBD) picks which one runs. `main.st` adds a thin OIP adapter around them.

## Running it

1. Open the `oip/` project in the **OIP desktop app**. In **Simulation › PLC Controllers…**, set
   `PLC1` to port **5020** (unit 1), then press Play.
2. Set `host` in `modbus_manifest.yaml` to the computer running OIP. It is `10.211.55.3` here
   (OIP in a Parallels VM, Nautilus on the Mac host); use `127.0.0.1` when both run on one machine.
3. `naut run .`, then open the dashboard at <http://127.0.0.1:8081>.
4. The selectors start in **AUTO** and **SORT**. Press **RESET**, then **+100** to set a belt speed,
   then **START**. To operate a panel device, select it and press **C** (or walk up in Pilot mode and
   press **E**).

OIP switches every output off if Nautilus stops polling for 1 s.

## What the adapter does (`main.st`)

| OIP difference | Handled by |
|---|---|
| The reject pusher's limit switches | The scene's reject pusher is a **Pusher with limits** (`user.pusher-limits`), a copy of OIP's pusher that publishes its home and full-extension positions. `RejPushBackLimit` is discrete 14 (`%IX1.6`) and `RejPushFrontLimit` is discrete 15 (`%IX1.7`), the Factory I/O addresses. The stroke is 1.5 m. |
| Pivot-arm sorters became pushers | Each sort lane is a **Pusher with limits** (`user.pusher-limits`). Its limits are `LidPusherRetracted`/`Extended` (discrete 38/39), `BasePusher…` (40/41) and `RawPusher…` (42/43). In Auto, the lane the controller chose arms that lane's `OipKicker` (`lib/oip_kicker.st`). When the sort eye sees the box, the kicker tracks it to the blade (0.3 m lead, less 0.08 s of I/O latency), holds belt 2, and runs one `Pusher` cycle. Belt 2 runs again once the retracted limit closes. In Manual, the lane's **PUSH** button (the old *Turn* input) jogs the pusher. A stroke over 2 s, or both limits on at once, latches `LidPusherFault`/`BasePusherFault`/`RawPusherFault`; RESET or RESET 2 clears it. |
| Belts take m/s, not 0–10 V | `Belt1SpeedMps = BeltSpeedRef / 100`; `Belt2SpeedMps` is the same except 0 while a diverter pushes (float32, HR 100 and 102, `wordorder: little`) |
| A stack light instead of three lamps | `StackLight = RunningPL + 2·WarningLight1 + 4·EStoppedPL` (HR 10) |
| Panel displays | The scene's digital displays show `BaseCounter` (HR 0), `BeltSpeedRef` (HR 2), `LidCounter` (HR 3), `ProductionRate` (HR 4) and `RawCounter` (HR 5), the Factory I/O register numbers. The OIP removal counts `RawRemoved`, `BaseRemoved`, `LidRemoved` and `RejectRemoved` are on the dashboard. |
| Local panel HOME / OUT lights | `RawHomePL`/`RawOutPL` (coils 32/33), `BaseHomePL`/`BaseOutPL` (35/36), `LidHomePL`/`LidOutPL` (38/39) and `RejectHomePL`/`RejectOutPL` (47/48) show each pusher's retracted and extended limits. They replace the sorter CW/CCW lamps. |
| No Factory I/O status inputs | `FIOReset`, `FIOPaused` and `FIORunning` are setpoints (`FIOReset` still resets the sequence) |

Tags that OIP has no part for are `state` tags in `tags/io.yaml`. These are the sorter CW/CCW buttons,
commands and lamps, the Turn commands, the removers, `Spare`, the three status lamps and the old
voltage speeds.
The controllers still write them, so the logic is unchanged and the panel lamps (`*PL`) still work.

## The `Pusher` function block (`lib/pusher.st`)

A reusable block for any pusher with a retracted and an extended limit switch:

```
Push(Enable := ..., Cycle := StartPulse, ManualExtend := Jog,
     RetractedLS := BackLS, ExtendedLS := FrontLS, StrokeTimeout := T#2s, ResetFault := Rst);
Coil := Push.Extend;   (* also Busy, Done (one scan), AtHome, Fault, State *)
```

A rising edge on `Cycle` with the blade home extends to the extended limit, then retracts to the retracted limit, and `Done` pulses. `Enable` FALSE drops the coil at once. Each stroke has a timeout, and a stroke over the limit or both limits on at once latches `Fault` until `ResetFault` rises.

## Files

- `nautilus.yaml`: one 20 ms task running `main.st`, plus the Modbus driver
- `modbus_manifest.yaml`: source `oip` at 10.211.55.3:5020, with only the addresses the OIP scene binds
- `lib/pusher.st`, `lib/oip_kicker.st`: the `Pusher` block and the per-lane sort logic
- `tags/io.yaml`: tag roles for this build
- `practicum_oip_test.yaml`: 88 virtual-time scenarios (each behaviour in ST, LD and FBD). Regenerate
  it with `python3 tools/make_tests.py`.

## Checks

```sh
naut check .   # 0 errors; the warnings all come from the copied lib/ files, the same as the Factory I/O version
naut test .    # 88 passed
```
