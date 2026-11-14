# Final Practicum: Nautilus + Open Industry Project

A sorting-line PLC exercise, originally built for Factory I/O, running on
[Open Industry Project](https://github.com/Open-Industry-Project/Open-Industry-Project) (OIP) and controlled by a
[Nautilus](https://github.com/joyautomation/nautilus) soft PLC over Modbus TCP.

| Folder | What it is |
|---|---|
| [`oip/`](oip/) | The OIP project: the scene, its custom parts (pusher with limit switches, 2-position selector, pilot light, digital display) and the I/O map. Open it in the OIP desktop app. |
| [`nautilus/`](nautilus/) | The Nautilus controller: the practicum logic in **ST, LD and FBD** (pick one with the `LanguageSelect` setpoint), an OIP adapter, a reusable `Pusher` function block and an 88-scenario acceptance suite. |
| [`tools/`](tools/) | `factoryio_to_oip.py`, the converter that produced the first version of the scene (kept for history). |

## Quick start

1. Open `oip/` in the OIP **desktop app**. Under **Simulation › PLC Controllers…**, give `PLC1` port
   **5020**, then press Play.
2. In `nautilus/modbus_manifest.yaml`, set the `oip` source's `host` to the computer running OIP
   (`127.0.0.1` if both run on one machine).
3. `cd nautilus && naut run .`, and open the dashboard at <http://127.0.0.1:8081>.
4. On OIP's remote panel (selectors start in AUTO and SORT): RESET, then +100, then START. Select a
   panel device and press **C** to operate it.

Checks: `naut check nautilus` (0 errors) and `naut test nautilus` (88 passed).

See [`oip/README.md`](oip/README.md) for the scene, its addresses and how it differs from the
Factory I/O original, and [`nautilus/README.md`](nautilus/README.md) for the controller.

## Keeping this repo up to date

The working copies live where the tools expect them (OIP keeps its project open from its own
folder). `./sync.sh` copies both into this repo; then review with `git status` and commit. Set
`NAUT_SRC` / `OIP_SRC` to point it at other folders.

## License

MIT. See [LICENSE](LICENSE).
