# Spring 2026 Final Practicum: Open Industry Project scene

A sorting line for Open Industry Project (OIP), converted from the Factory I/O scene
`Spring2026_Final_Practicum_Modbus.factoryio` and then refined in the OIP editor. A Nautilus
controller drives it over Modbus TCP; the controller lives in the `nautilus/` folder of the same repo.

## How it connects

OIP is the **Modbus TCP server**. The scene's controller `PLC1` runs on *an external PLC* with the
protocol *The PLC polls the simulator* (`serve`). The scene holds no program, and every device is
wired to a Modbus address.

- Use the **desktop app**; a browser tab can't open sockets. Set the port under
  **Simulation › PLC Controllers…** (default **5020**, unit 1). The port is a per-computer setting.
- If no poll arrives for 1 s, OIP turns every PLC-driven output off.
- Addresses: `%IXb.n` = discrete input `b*8+n`, `%QXb.n` = coil `b*8+n`, `%IWn` = input register `n`,
  `%QWn` = holding register `n`, `%QDn` = holding registers `2n` and `2n+1`, a float32 sent **low word
  first** (Nautilus: `format: float32`, `wordorder: little`).
- OIP registers addresses when a run starts, so press Stop and Play after adding or rewiring a part.

`oip_io_map.csv` lists every wired address (exported from OIP's I/O list).

## The line

Boxes of 9 types (blue, green and metal; raw, lid and base) drop from the emitter onto belt 1. They
pass the classify eye, a colour sensor (`%IW0`, codes 1–9) and the reject eye. A **reject pusher**
pushes metal boxes down a chute. A stop blade (unused by the logic) separates belt 1 from belt 2, where
three **sort pushers** push boxes onto the Lid, Base and Raw takeaways. Each pusher has a sort-position
eye just before it. Despawners at the end of each lane count what arrives (`%IW1` Lid, `%IW2` Base,
`%IW3` Raw, `%IW4` Reject). A catch at the end of belt 2 removes unsorted boxes.

Belt speeds are REAL m/s at `%QD50` / `%QD51`. The stack light is an INT bitmask at `%QW10`: bit 0
green (running), bit 1 amber (warning), bit 2 red (E-stopped).

### Remote panel (beside belt 1)

START / STOP / RESET, E-STOP, REMOTE, speed buttons (+100, +10, −10, −100), the **MAN/AUTO** and
**SORT/REJECT** selectors, pilot lights (RAW, BASE, LID, MANUAL, AUTO, LAB PLC, SKID PLC), digital
displays (RAW, BASE and LID counters at `%QW5`, `%QW0`, `%QW3`; SPEED cm/s at `%QW2`; RATE at `%QW4`)
and the stack light. RESET latches (press once to hold it in, again to release), so it can be held for
the controller's 5 s counter reset in Manual.

### Local panel (beyond the Raw lane)

LOCAL, E-STOP 2, RESET 2, BELT, REJECT, and per sort lane a **PUSH** button with **HOME** and **OUT**
lights. REJECT HOME / REJECT OUT show the reject pusher's limits.

## Custom parts (`parts/user.*`)

| Part | What it does |
|---|---|
| `user.pusher-limits` | Copy of OIP's pop-up pusher that also publishes a **retracted** and an **extended** limit switch (`retractedTag`, `extendedTag`), like Factory I/O's pusher. Textures are plain finishes. |
| `user.selector-switch` | 2-position maintained selector: exactly one of `leftTag` / `rightTag` is true. Use (C, or E in Pilot mode) turns it. |
| `user.pilot-light` | Panel lamp, lit while `tag` is true; lens colour and legend are params. |
| `user.digital-display` | Panel readout of an INT `tag`, with a legend and decimals param. |

### Pusher limit switches

| Pusher | Coil (extend) | Retracted | Extended |
|---|---|---|---|
| Reject | `%QX2.4` | `%IX1.6` (14) | `%IX1.7` (15) |
| Lid | `%QX1.6` | `%IX4.6` (38) | `%IX4.7` (39) |
| Base | `%QX0.3` | `%IX5.0` (40) | `%IX5.1` (41) |
| Raw | `%QX2.1` | `%IX5.2` (42) | `%IX5.3` (43) |

## Differences from the Factory I/O scene

- The three pivot-arm sorters are pushers on their old *Turn* coils, each with a new sort-position eye
  (`%IX4.3` Lid, `%IX4.4` Base, `%IX4.5` Raw) and limit switches. The CW/CCW outputs and buttons are gone.
- The vision sensor is a colour sensor with the same codes 1–9; the emitter gives each part type its
  own colour.
- The stack light is one INT instead of three coils.
- `FIOPaused` / `FIOReset` / `FIORunning` don't exist (the Nautilus project makes them setpoints).
- Safeguards and other decorative parts are left out.
