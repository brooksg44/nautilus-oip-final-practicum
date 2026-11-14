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

## Camera and navigation

OIP has no saved camera views like Factory I/O's. It remembers one camera position per scene between
sessions. These take their place:

| What you want | How in OIP |
|---|---|
| Fixed views | **Numpad 1 / 3 / 7** for front, right and top; add **Ctrl** for rear, left and bottom. Without a numpad, click the axis balls on the orientation gizmo in the corner of the 3D view. **O** switches between perspective and orthographic. |
| Jump to a part | Select it in the scene tree and press **F**. Press **F** again to follow it as it moves; a third time stops following. |
| Back to the opening view | **Reset View** in the command palette (**Ctrl+Shift+P**, then type "reset view"). It isn't in the View menu. |
| Fly around | Hold the **right mouse button**, or press **Shift+F**. Steer with **W A S D**, **Q / E** go down / up, and **Shift** goes faster. **Esc** stops flying. |
| First person | **Pilot mode (P)**: walk with **W A S D**, and press **E** (or **F**, or click) to work buttons. **Esc** or **P** leaves it. |
| Full-screen scene only | **Present** in the command palette, for a projector. **Esc** leaves it. |

To get to either control panel, select **Remote panel** or **Local panel** in the scene tree and
press **F**.

### Operating panel devices

Clicking a part in the editor only selects it. Select a button, selector or E-stop and press **C**, or
press **E** on it in Pilot mode. The simulation must be **playing**; a press while it is stopped only
changes the preview, and Nautilus never sees it. A momentary button gives a 0.3 s press; a latching
button (RESET), a selector or an E-stop changes state on each press.

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
