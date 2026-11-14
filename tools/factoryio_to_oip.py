#!/usr/bin/env python3
"""Convert Spring2026_Final_Practicum_Modbus.factoryio into an Open Industry Project folder.

The OIP scene is wired for an EXTERNAL PLC: Open Industry Project is the Modbus TCP server
(protocol "serve"), and the controller (Nautilus) polls it, exactly as it polled Factory I/O.
Every part tag is a Modbus address, so no program runs inside OIP.

Address rule (OIP, PLC polls the simulator):
  %IXb.n -> discrete input b*8+n     %QXb.n -> coil b*8+n
  %IWn   -> input register n         %QWn   -> holding register n
  %QDn   -> holding registers 2n, 2n+1 (float32, LOW word first)

Discrete inputs and coils keep the Factory I/O numbering from io_map.csv, so the existing
Nautilus Modbus manifest addresses stay valid for all BOOL points.

Usage: python3 tools/factoryio_to_oip.py <scene.factoryio> <output project dir>
Writes project.json and scene.json. Re-running overwrites them (and any edits made in the app).

HISTORICAL: this produced the FIRST version of the scene. The scene in ../oip/ has since been
edited in the OIP editor (custom panel selectors, pilot lights, displays, pushers with limit
switches, local panel HOME/OUT lights) and is the source of truth. Running this script again
would bring back the original button panel and plain diverters. The .factoryio input is not
part of this repo.
"""
import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

GRID = 0.125          # Factory I/O grid unit, metres
ORIGIN_X, ORIGIN_Z = 264, 135   # Factory I/O grid point placed at the OIP origin
PI = math.pi

DECK = 0.9            # belt deck height (m)
BELT_W = 1.0          # main / takeaway belt width (m)
HALF = BELT_W / 2


def di(n):
    return f"%IX{n // 8}.{n % 8}"


def co(n):
    return f"%QX{n // 8}.{n % 8}"


def r(v):
    return round(v, 4)


def fio_xz(X, Z):
    """Factory I/O (left-handed, grid) -> OIP (right-handed, metres). Z is mirrored."""
    return (X - ORIGIN_X) * GRID, -(Z - ORIGIN_Z) * GRID


def load_fio_positions(path):
    """Map every Factory I/O sensor/actuator name to its object's grid position."""
    root = ET.parse(path).getroot()
    pos = {}
    for obj in root.findall("Object"):
        p = obj.find("Proxy")
        if p is None:
            continue
        a = p.find("Position").attrib
        xyz = (float(a["X"]), float(a["Y"]), float(a["Z"]))
        for el in obj.iter():
            if el.tag in ("BinaryInput", "BinaryOutput") and el.get("Name"):
                pos.setdefault(el.get("Name"), xyz)
    return pos


class Scene:
    def __init__(self):
        self.parts = []
        self.n = 0

    def add(self, name, package, position, rot, params):
        self.n += 1
        self.parts.append({
            "id": f"pt_{self.n}",
            "name": name,
            "type": "part",
            "packageId": package,
            "position": [r(v) for v in position],
            "rotationY": r(rot),
            "params": params,
        })


def belt(scene, name, tail, rot, length, *, speed=1.0, speed_tag="", width=BELT_W, openings=(), deck=DECK):
    scene.add(name, "oip.belt-conveyor", (tail[0], deck, tail[1]), rot, {
        "segments": [[length, 0]],
        "width": width,
        "standHeight": deck,
        "fpmUnits": False,
        "speed": speed,
        "speedTag": speed_tag,
        "leftGuard": True,
        "rightGuard": True,
        "guardOpenings": [list(o) for o in openings],
    })


def eye(scene, name, x, z, rot, tag, *, mode="diffuse", rng=1.1, nc=False):
    scene.add(name, "oip.diffuse-sensor", (x, DECK + 0.02, z), rot, {
        "maxRange": rng, "mode": mode, "showBeam": True, "normallyClosed": nc, "mark": "", "tag": tag,
    })


def diverter(scene, name, x, z, rot, tag, distance):
    scene.add(name, "oip.diverter", (x, DECK - 0.2, z), rot, {
        "diverted": False, "divertTime": 0.25, "divertDistance": distance,
        "standHeight": r(DECK - 0.2), "tag": tag,
    })


def despawner(scene, name, x, z, *, count_tag="", length=0.6, width=1.1):
    scene.add(name, "oip.despawner", (x, 0.3, z), 0, {
        "length": length, "width": width, "height": 1.0, "countOnly": "", "showReadout": True,
        "countTag": count_tag,
    })


# ---- operator panels -------------------------------------------------------------------------------------------

def panel_item(scene, fio, fio_name, label, *, face_x, tag="",lamp="", color="#e8e8e8",
               momentary=True, nc=False, estop=False, dz=0.0):
    X, Y, Z = fio[fio_name]
    _, z = fio_xz(X, Z)
    params = {"text": label}
    if estop:
        params.update({"emergencyStop": True, "startStruck": False})
    else:
        params.update({"emergencyStop": False, "buttonColor": color, "momentary": momentary,
                       "startPressed": False, "normallyClosed": nc})
    if lamp:
        params.update({"lampSource": "tag", "lampTag": lamp})
    elif not estop:
        params.update({"lampSource": "press" if tag else "off"})
    params["tag"] = tag
    # button front is local +Z; rotationY = pi/2 turns it to face world +X. Its back plate is 0.03 behind origin.
    scene.add(f"{label} ({fio_name})", "oip.push-button", (face_x + 0.03, Y * GRID - 0.045, z + dz), PI / 2, params)


def cabinet(scene, name, face_x, z_min, z_max, height=1.85):
    depth = 0.15
    scene.add(name, "oip.shape", (face_x - depth / 2, 0, (z_min + z_max) / 2), 0, {
        "shape": "box", "length": depth, "width": r(z_max - z_min), "height": height,
        "color": "#5b6770", "solid": True,
    })


def build(fio_path):
    fio = load_fio_positions(fio_path)
    s = Scene()

    # ---- material flow: emitter -> belt 1 (classify, vision, reject) -> belt 2 (stop blade, 3 sorters) ----------
    # Factory I/O flows toward -Z; here the main line flows toward +Z (rotationY = -pi/2 turns local +X to world +Z).
    MAIN = -PI / 2
    b1_tail, b2_tail = -4.75, -0.45
    reject_z = -1.45  # where boxes stop after the reject eye fires (belt-stop latency)
    lanes = {"Lid": 0.0, "Base": 1.25, "Raw": 2.625}   # Factory I/O sorter/takeaway rows Z=137/135, 126/125, 115/114

    s.add("Emitter (Emitter1)", "oip.box-spawner", (0, DECK + 0.5, -4.3), MAIN, {
        "boxesPerMinute": 30, "fixedRate": True, "release": "enable", "product": "oip.box",
        # nine Factory I/O part types, in vision-sensor code order 1..9 (see README.md)
        "boxColors": "#1e3cff,#5aa0ff,#0a1e8c,#28c828,#96ff64,#0a6e1e,#a0a0a0,#dcdcdc,#5a5a5a",
        "mixAttribute": "code", "mixValues": "1,2,3,4,5,6,7,8,9", "randomColors": True,
        "length": 0.4, "width": 0.4, "height": 0.3, "mass": 5, "disable": False,
        "runTag": co(6),
    })
    belt(s, "Belt Conveyor (4m) 1", (0, b1_tail), MAIN, 4, speed=0.6, speed_tag="%QD50",
         openings=[(r(reject_z - b1_tail - 0.45), r(reject_z - b1_tail + 0.45), 0)])
    belt(s, "Belt Conveyor (4m) 2", (0, b2_tail), MAIN, 4, speed=0.6, speed_tag="%QD51",
         openings=[(r(z - b2_tail - 0.45), r(z - b2_tail + 0.45), 0) for z in lanes.values()])

    # sensors on belt 1 (+X side = Factory I/O +X side)
    eye(s, "ClassifyDiffuseSensor", HALF + 0.05, -2.625, -PI / 2, di(20))
    s.add("VisionSensor1 (color code 1..9)", "oip.color-sensor", (-HALF - 0.05, DECK + 0.02, -2.3), PI / 2, {
        "maxRange": 1.1, "showBeam": True,
        "colors": "#1e3cff,#5aa0ff,#0a1e8c,#28c828,#96ff64,#0a6e1e,#a0a0a0,#dcdcdc,#5a5a5a",
        "tolerance": 25, "colorTag": "%IW0",
    })
    eye(s, "RejectDiffuseSensor", -HALF - 0.05, -1.3, PI / 2, di(2))

    # reject pusher (Factory I/O Pusher) pushes -X across belt 1 onto the chute
    diverter(s, "RejectPusher", HALF + 1.0635 + 0.05, reject_z, PI / 2, co(20), 1.5)  # full stroke so the box lands on the chute
    belt(s, "Reject chute", (-HALF - 0.18, reject_z), PI, 2.2, speed=1.0, width=0.8, deck=0.8)
    despawner(s, "Remover4 (reject)", -3.2, reject_z, count_tag="%IW4", width=1.0)

    # AtExit: retro-reflective beam along the +X edge of the sorting section, TRUE while clear (as in Factory I/O)
    eye(s, "AtExit (retro-reflective)", HALF + 0.1, -1.125, 0, di(0), mode="retro", rng=4.4, nc=True)

    s.add("StopBlade", "oip.blade-stop", (0, DECK, -0.6), MAIN, {
        "width": BELT_W, "active": False, "raiseHeight": 0.04, "tag": co(28),
    })

    # sorters: Factory I/O pivot-arm sorters become pop-up diverters pushing +X onto the 2 m takeaways
    turn = {"Lid": co(14), "Base": co(3), "Raw": co(17)}
    sort_eye = {"Lid": di(35), "Base": di(36), "Raw": di(37)}
    remover = {"Lid": ("Remover1", "%IW1"), "Base": ("Remover2", "%IW2"), "Raw": ("Remover3", "%IW3")}
    for lane, z in lanes.items():
        diverter(s, f"{lane}SorterTurn", -HALF - 1.0635 - 0.05, z, -PI / 2, turn[lane], 1.15)
        eye(s, f"{lane}SortPositionEye (new)", HALF + 0.05, z - 0.1, -PI / 2, sort_eye[lane])
        belt(s, f"Belt Conveyor (2m) {lane}", (HALF + 0.18, z), 0, 2, speed=1.0)
        despawner(s, f"{remover[lane][0]} ({lane})", 3.0, z, count_tag=remover[lane][1])
    despawner(s, "End-of-line catch (new)", 0, 3.95, length=1.2, width=0.6)

    # ---- remote panel (Factory I/O switchboard at X=271..273, faces +X) ---------------------------------------
    face = (273 - ORIGIN_X) * GRID - 0.03
    cabinet(s, "Remote panel", face, -3.6, -2.9)
    s.add("VisualStatusIndicator (stack light)", "oip.stack-light", (face - 0.075, 1.85, -3.125), PI / 2, {
        "segments": 3, "value": 0, "tag": "%QW10",
    })
    P = lambda *a, **k: panel_item(s, fio, *a, face_x=face, **k)
    P("EmergencyStop", "E-STOP", tag=di(5), estop=True)
    P("Start", "START", tag=di(18), lamp=co(27), color="#22aa33")
    P("Stop", "STOP", tag=di(19), lamp=co(29), color="#cc2222", nc=True)
    P("Reset", "RESET", tag=di(17), lamp=co(25), color="#2255cc")
    P("Auto", "AUTO", tag=di(1), momentary=False, dz=-0.035)
    P("Manual", "MAN", tag=di(13), momentary=False, dz=0.035)
    P("SendSort", "SORT", tag=di(32), momentary=False, dz=-0.035)
    P("SendReject", "REJECT", tag=di(33), momentary=False, dz=0.035)
    P("IncSpdx100", "+100", tag=di(10), lamp=co(8))
    P("IncSpdx10", "+10", tag=di(11), lamp=co(9))
    P("DecSpdx100", "-100", tag=di(4), lamp=co(5))
    P("DecSpdx10", "-10", tag=di(3), lamp=co(4))
    P("RemoteControlPanel", "REMOTE", tag=di(16), lamp=co(21))
    P("RawPLRed", "RAW", lamp=co(16), color="#cc2222")
    P("BasePLYellow", "BASE", lamp=co(0), color="#e0c020")
    P("LidPLGreen", "LID", lamp=co(11), color="#22aa33")
    P("Manual PL", "MANUAL", lamp=co(41), color="#e0c020")
    P("AutoPL", "AUTO", lamp=co(31), color="#22aa33")
    P("LabPLCRunning", "LAB PLC", lamp=co(10), color="#22aa33")
    P("SkidPLCRunning", "SKID PLC", lamp=co(26), color="#22aa33")

    # ---- local panel (Factory I/O switchboard at X=283..285, faces +X) ----------------------------------------
    face = (285 - ORIGIN_X) * GRID - 0.03
    cabinet(s, "Local panel", face, 3.2, 3.95)
    P = lambda *a, **k: panel_item(s, fio, *a, face_x=face, **k)
    P("EmergencyStop2", "E-STOP 2", tag=di(6), estop=True)
    P("LocalControlPanel", "LOCAL", tag=di(12), lamp=co(15))
    P("Reset2", "RESET 2", tag=di(34), lamp=co(44), color="#2255cc")
    P("BaseSorterBeltCCWManPB", "BASE CCW", tag=di(21), lamp=co(35))
    P("BaseSorterBeltCWManPB", "BASE CW", tag=di(22), lamp=co(36))
    P("BaseSorterTurnManPB", "BASE TURN", tag=di(23), lamp=co(37))
    P("LidSorterBeltCCWManPB", "LID CCW", tag=di(24), lamp=co(38))
    P("LidSorterBeltCWManPB", "LID CW", tag=di(25), lamp=co(39))
    P("LidSorterTurnManPB", "LID TURN", tag=di(26), lamp=co(40))
    P("RawSorterBeltCCWManPB", "RAW CCW", tag=di(27), lamp=co(32))
    P("RawSorterBeltCWManPB", "RAW CW", tag=di(28), lamp=co(33))
    P("RawSorterBeltTurnManPB", "RAW TURN", tag=di(29), lamp=co(34))
    P("BeltConveyor(4m)ManPB", "BELT", tag=di(30), lamp=co(42))
    P("RejectPusherManPB", "REJECT", tag=di(31), lamp=co(43))

    return {
        "version": 4,
        "units": "metric",
        "plcs": [{"name": "PLC1", "runsOn": "plc", "protocol": "serve", "connect": True}],
        "parts": s.parts,
    }


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    scene = build(src)
    (out / "scene.json").write_text(json.dumps(scene, indent=2) + "\n")
    (out / "project.json").write_text(json.dumps({
        "version": 7,
        "name": "Spring2026 Final Practicum Modbus",
        "scene": "scene.json",
    }, indent=2) + "\n")
    print(f"wrote {len(scene['parts'])} parts to {out}")


if __name__ == "__main__":
    main()
