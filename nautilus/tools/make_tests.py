#!/usr/bin/env python3
"""Generate virtual-time acceptance scenarios for the OIP build.

Every behavioural scenario runs once per controller language (ST, LD, FBD).
Differences from the Factory I/O suite: the reject pusher limits are
emulated by timers in main.st, the sorters are pop-up diverters fired by the
sort-position eyes, belt speeds are written in m/s and the status lamps are
one stack-light bitmask.
"""
import copy
import json
from pathlib import Path

healthy = dict(EmergencyStop=True, EmergencyStop2=True, Stop=True, AtExit=True,
               # every pusher at rest on its retracted limit
               RejPushBackLimit=True, LidPusherRetracted=True, BasePusherRetracted=True, RawPusherRetracted=True)


def step(g=None, n=1, e=None, t=None):
    d = {}
    if g:
        d['given'] = g
    d['advance' if t else 'scans'] = t or n
    if e:
        d['expect'] = e
    return d


def arm(mode='auto'):
    return [step({**healthy, 'AutoSS': mode == 'auto', 'ManualSS': mode == 'manual'}, e={'MainStep': 2, 'StackLight': 0}),
            step({'Reset': True}, e={'MainStep': 3, 'Mode': 5 if mode == 'auto' else 4}),
            step({'Reset': False})]


def running():
    return arm() + [
        step({'IncSpdX100': True, 'Start': True}),
        step({'IncSpdX100': False, 'Start': False}, t='3.1s',
             e={'AutoStep': 19, 'RunningPL': True, 'BeltSpeedRef': 100,
                'Belt1SpeedMps': 1.0, 'Belt2SpeedMps': 1.0, 'StackLight': 1})]


tests = []


def add(name, steps):
    tests.append(dict(name=name, steps=steps))


add('startup and reset require healthy contacts and clear sensors', [
    step(e={'MainStep': 1, 'Mode': 0, 'Belt1SpeedMps': 0.0}),
    step(healthy, e={'MainStep': 2}),
    step({'Reset': True, 'ClassifyDefuseSensor': True}, e={'MainStep': 2}),
    step({'ClassifyDefuseSensor': False}, e={'MainStep': 3}),
    step({'EmergencyStop2': False}, e={'MainStep': 1, 'Mode': 0})])

add('e-stop flashes the red stack-light tier', [
    step({'EmergencyStop': False, 'EmergencyStop2': True, 'Stop': True}, n=2),
    step(t='1s', e={'MainStep': 1}),
    # EStoppedPL blinks at 1 Hz; sample both halves of the cycle
    step(t='250ms', e={'StackLight': 4}),
    step(t='500ms', e={'StackLight': 0})])

add('three second warning shows amber, then green while running', arm() + [
    step({'Start': True}, e={'AutoStep': 20, 'Emitter': False}),
    step({'Start': False}, t='2.8s', e={'AutoStep': 20, 'Emitter': False}),
    step(t='240ms', e={'AutoStep': 19, 'Emitter': True, 'StackLight': 1}),
    step(t='600ms', e={'Emitter': False})])

add('amber warning tier blinks during the start warning', arm() + [
    step({'Start': True}), step({'Start': False}),
    step(t='1s'),
    step(t='250ms', e={'AutoStep': 20, 'StackLight': 0}),
    step(t='500ms', e={'AutoStep': 20, 'StackLight': 2})])

LS = {'RawDiverter': 'RawPusher', 'BaseDiverter': 'BasePusher', 'LidDiverter': 'LidPusher'}
lanes = [('raw', 1, 24, 'RawCounter', 'RawDiverter', 'RawSortEye'),
         ('raw green', 4, 24, 'RawCounter', 'RawDiverter', 'RawSortEye'),
         ('base', 3, 27, 'BaseCounter', 'BaseDiverter', 'BaseSortEye'),
         ('base green', 6, 27, 'BaseCounter', 'BaseDiverter', 'BaseSortEye'),
         ('lid', 2, 28, 'LidCounter', 'LidDiverter', 'LidSortEye'),
         ('lid green', 5, 28, 'LidCounter', 'LidDiverter', 'LidSortEye')]
all_div = ['RawDiverter', 'BaseDiverter', 'LidDiverter']
for name, code, state, counter, div, eye in lanes:
    others = {d: False for d in all_div if d != div}
    other_eyes = {e: True for e in ['RawSortEye', 'BaseSortEye', 'LidSortEye'] if e != eye}
    add('sort ' + name + ' fires its diverter at the sort eye', running() + [
        step({'ClassifyDefuseSensor': True, 'VisionSensor1': code},
             e={'AutoStep': 22, 'BeltSpeedRef': 60, 'Belt1SpeedMps': 0.6}),
        step({'SendSortPB': True}, e={'AutoStep': state, counter: 1, 'BeltSpeedRef': 100, div: False}),
        step({'AtExit': False, 'ClassifyDefuseSensor': False, 'SendSortPB': False},
             e={'AutoStep': state + 100, div: False}),
        # a box passing another lane's eye must not fire that lane
        step(other_eyes, n=3, e={div: False, **others}),
        # eye sees the box: belt 2 keeps running while the box travels to the blade
        step({**{k: False for k in other_eyes}, eye: True}, e={div: False, 'Belt2SpeedMps': 1.0}),
        step(t='100ms', e={div: False, 'Belt2SpeedMps': 1.0}),
        # box centred on the blade (0.3 m lead - 0.08 s latency at 1 m/s): belt 2 holds, blade out
        step(t='200ms', e={div: True, 'Belt2SpeedMps': 0.0, 'Belt1SpeedMps': 1.0}),
        # blade leaves home: stays out until the extended limit closes
        step({eye: False, LS[div] + 'Retracted': False}, t='1s', e={div: True, 'Belt2SpeedMps': 0.0}),
        step({LS[div] + 'Extended': True}, e={div: False, 'Belt2SpeedMps': 0.0}),
        # retracting: belt 2 stays held until the retracted limit closes
        step({LS[div] + 'Extended': False}, t='1s', e={div: False, 'Belt2SpeedMps': 0.0}),
        step({LS[div] + 'Retracted': True}, n=2, e={div: False, 'Belt2SpeedMps': 1.0}),
        step({'AtExit': True}, e={'AutoStep': state + 200}),
        step(t='600ms', e={'AutoStep': 19, 'Emitter': True, counter: 1, div: False})])

add('a jammed sort pusher times out, faults, releases the belt and resets', running() + [
    step({'ClassifyDefuseSensor': True, 'VisionSensor1': 3}),
    step({'SendSortPB': True}, e={'AutoStep': 27}),
    step({'AtExit': False, 'ClassifyDefuseSensor': False}),
    step({'BaseSortEye': True}, t='300ms', e={'BaseDiverter': True, 'Belt2SpeedMps': 0.0}),
    # blade leaves home but never reaches the extended limit
    step({'BasePusherRetracted': False}, t='1.5s', e={'BaseDiverter': True, 'BasePusherFault': False}),
    step(t='600ms', e={'BaseDiverter': False, 'BasePusherFault': True, 'Belt2SpeedMps': 1.0}),
    step({'BasePusherRetracted': True, 'BaseSortEye': False}, n=5, e={'BasePusherFault': True}),
    step({'Reset': True}, e={'BasePusherFault': False}),
    step({'Reset': False})])

add('both limits on at once is a pusher fault', arm() + [
    step({'LidPusherExtended': True}, n=2, e={'LidPusherFault': True, 'LidDiverter': False}),
    step({'LidPusherExtended': False}, n=2, e={'LidPusherFault': True}),
    step({'Reset2PB': True}, e={'LidPusherFault': False})])

add('at 3 m/s the push starts almost as soon as the eye sees the box', arm() + [
    step({'IncSpdX100': True, 'Start': True}), step({'IncSpdX100': False, 'Start': False}),
    step({'IncSpdX100': True}), step({'IncSpdX100': False}),
    step({'IncSpdX100': True}), step({'IncSpdX100': False}, t='3.1s', e={'AutoStep': 19, 'Belt2SpeedMps': 3.0}),
    step({'ClassifyDefuseSensor': True, 'VisionSensor1': 2}),
    step({'SendSortPB': True}, e={'AutoStep': 28}),
    step({'AtExit': False, 'ClassifyDefuseSensor': False}, e={'AutoStep': 128}),
    step({'LidSortEye': True}),
    step(t='60ms', e={'LidDiverter': True, 'Belt2SpeedMps': 0.0})])

for code in [7, 8, 9]:
    add('reject metal %d uses the emulated pusher limits' % code, running() + [
        step({'ClassifyDefuseSensor': True, 'VisionSensor1': code}),
        step(e={'AutoStep': 25}),
        step({'RejectDiffuseSensor': True},
             e={'AutoStep': 85, 'RejectPusher': True, 'BeltSpeedRef': 0, 'Belt1SpeedMps': 0.0}),
        # the pusher leaves home, then reaches full extension (limit switches from OIP)
        step({'RejPushBackLimit': False}, t='300ms', e={'AutoStep': 85, 'RejectPusher': True}),
        step({'RejPushFrontLimit': True}, e={'AutoStep': 86, 'RejectPusher': False}),
        step({'RejPushFrontLimit': False, 'RejectDiffuseSensor': False, 'ClassifyDefuseSensor': False}, n=20, e={'AutoStep': 86}),
        step({'RejPushBackLimit': True}, e={'AutoStep': 19, 'BeltSpeedRef': 100, 'Belt1SpeedMps': 1.0})])

add('operator reject overrides sort and unknown vision waits', running() + [
    step({'ClassifyDefuseSensor': True, 'VisionSensor1': 0}),
    step({'SendSortPB': True}, n=5, e={'AutoStep': 22}),
    step({'VisionSensor1': 1, 'SendRejectPB': True}, e={'AutoStep': 25, 'RawCounter': 0})])

add('manual turn toggles drive the diverters directly', arm('manual') + [
    step({'RawSorterBeltTurnManPB': True}, e={'RawSorterBeltTurn': True, 'RawDiverter': True}),
    step({'RawSorterBeltTurnManPB': False}, n=10, e={'RawDiverter': True}),
    step({'LidSorterBeltTurnManPB': True}, e={'LidDiverter': True, 'BaseDiverter': False}),
    step({'RawSorterBeltTurnManPB': True}, e={'RawDiverter': False}),
    step({'ManualSS': False, 'AutoSS': True}, e={'Mode': 5, 'LidDiverter': False, 'RawDiverter': False})])

add('local panel HOME / OUT lamps follow each pusher limit', arm('manual') + [
    step(n=2, e={'RawHomePL': True, 'BaseHomePL': True, 'LidHomePL': True, 'RawOutPL': False}),
    step({'RawSorterBeltTurnManPB': True}, e={'RawDiverter': True}),
    step({'RawSorterBeltTurnManPB': False, 'RawPusherRetracted': False}, e={'RawHomePL': False, 'RawOutPL': False}),
    step({'RawPusherExtended': True}, e={'RawOutPL': True, 'RawHomePL': False, 'BaseHomePL': True})])

add('local panel REJECT HOME / OUT lamps follow the reject pusher limits', arm('manual') + [
    step(n=2, e={'RejectHomePL': True, 'RejectOutPL': False}),
    step({'RejPushBackLimit': False}, e={'RejectHomePL': False, 'RejectOutPL': False}),
    step({'RejPushFrontLimit': True}, e={'RejectHomePL': False, 'RejectOutPL': True})])

add('manual sort eyes do not fire diverters', arm('manual') + [
    step({'RawSortEye': True, 'BaseSortEye': True, 'LidSortEye': True}, n=5,
         e={'RawDiverter': False, 'BaseDiverter': False, 'LidDiverter': False})])

add('reject pusher stays out until the extended limit switch closes', running() + [
    step({'ClassifyDefuseSensor': True, 'VisionSensor1': 8}), step(e={'AutoStep': 25}),
    step({'RejectDiffuseSensor': True, 'RejPushBackLimit': True}, e={'AutoStep': 85, 'RejectPusher': True}),
    step({'RejPushBackLimit': False}, t='3s', e={'AutoStep': 85, 'RejectPusher': True}),
    step({'RejPushFrontLimit': True}, e={'AutoStep': 86, 'RejectPusher': False}),
    step({'RejPushFrontLimit': False}, t='3s', e={'AutoStep': 86, 'BeltSpeedRef': 0}),
    step({'RejPushBackLimit': True}, e={'AutoStep': 19})])

add('speed increments clamp and scale to m/s', arm('manual') + [
    step({'BeltConveyor4mManPB': True}, e={'BeltSpeedRef': 60, 'Belt1SpeedMps': 0.6, 'Belt2SpeedMps': 0.6}),
    step({'IncSpdX100': True}, e={'BeltSpeedRef': 160, 'Belt1SpeedMps': 1.6}),
    step(n=5, e={'BeltSpeedRef': 160}),
    step({'IncSpdX100': False}), step({'IncSpdX100': True}), step({'IncSpdX100': False}),
    step({'IncSpdX100': True}, e={'BeltSpeedRef': 300, 'Belt1SpeedMps': 3.0, 'Belt2SpeedMps': 3.0}),
    step({'Stop': False}, e={'MainStep': 2, 'Mode': 0, 'Belt1SpeedMps': 0.0, 'Belt2SpeedMps': 0.0})])

add('manual counter reset requires five continuous seconds', arm('manual') + [
    step({'RawCounter': 3, 'BaseCounter': 4, 'LidCounter': 5, 'Reset': True}, t='4s', e={'RawCounter': 3}),
    step({'Reset': False}), step({'Reset': True}, t='4s', e={'BaseCounter': 4}),
    step(t='1.1s', e={'RawCounter': 0, 'BaseCounter': 0, 'LidCounter': 0})])

for contact in ['Stop', 'EmergencyStop', 'EmergencyStop2']:
    add(contact + ' drops the diverter and belts and requires reset', running() + [
        step({'ClassifyDefuseSensor': True, 'VisionSensor1': 1}),
        step({'SendSortPB': True}, e={'AutoStep': 24}),
        step({'AtExit': False, 'RawSortEye': True}, t='300ms', e={'RawDiverter': True, 'Belt2SpeedMps': 0.0}),
        step({contact: False}, e={'Mode': 0, 'RawDiverter': False, 'Emitter': False,
                                  'Belt1SpeedMps': 0.0, 'Belt2SpeedMps': 0.0, 'StackLight': 0 if contact == 'Stop' else None}),
        step({contact: True, 'Reset': False, 'RawSortEye': False, 'AtExit': True}, n=5,
             e={'MainStep': 2, 'Mode': 0, 'RawDiverter': False})])

add('conflicting selectors disable motion', arm('manual') + [
    step({'RejectPusherManPB': True, 'BeltConveyor4mManPB': True}, e={'RejectPusher': True}),
    step({'AutoSS': True}, e={'Mode': 0, 'RejectPusher': False, 'Belt1SpeedMps': 0.0})])

# Drop expectations marked None (value depends on the blink phase).
for t in tests:
    for s in t['steps']:
        if 'expect' in s:
            s['expect'] = {k: v for k, v in s['expect'].items() if v is not None}

base = tests
tests = []
for language, label in [(1, 'ST'), (2, 'LD'), (3, 'FBD')]:
    for scenario in base:
        scenario = copy.deepcopy(scenario)
        scenario['name'] = label + ': ' + scenario['name']
        scenario['given'] = {'LanguageSelect': language}
        tests.append(scenario)

for old, new in [(1, 2), (2, 3), (3, 1)]:
    add(f'switch {old} to {new} clears motion, preserves totals and requires reset', [
        step({'LanguageSelect': old, **healthy, 'ManualSS': True}, e={'MainStep': 2}),
        step({'Reset': True}, e={'Mode': 4}), step({'Reset': False}),
        step({'RawCounter': 12, 'BaseCounter': 13, 'LidCounter': 14, 'BeltConveyor4mManPB': True,
              'RawSorterBeltTurnManPB': True},
             e={'Belt1SpeedMps': 0.6, 'RawDiverter': True}),
        step({'LanguageSelect': new}, e={'ActiveLanguage': new, 'MainStep': 1, 'Mode': 0, 'RawDiverter': False,
                                         'Belt1SpeedMps': 0.0, 'RawCounter': 12, 'BaseCounter': 13, 'LidCounter': 14}),
        step({'BeltConveyor4mManPB': False, 'RawSorterBeltTurnManPB': False}, n=5, e={'MainStep': 2, 'Mode': 0}),
        step({'Reset': True}, e={'Mode': 4, 'Belt1SpeedMps': 0.0, 'RawDiverter': False})])

add('invalid language disables all implementations and can recover', arm('manual') + [
    step({'BeltConveyor4mManPB': True, 'RejectPusherManPB': True}, e={'Belt1SpeedMps': 0.6, 'RejectPusher': True}),
    step({'LanguageSelect': 99}, n=5, e={'LanguageValid': False, 'ActiveLanguage': 0, 'MainStep': 1,
                                          'RejectPusher': False, 'Belt1SpeedMps': 0.0, 'StackLight': 0}),
    step({'LanguageSelect': 3}, e={'LanguageValid': True, 'ActiveLanguage': 3, 'MainStep': 1, 'RejectPusher': False}),
    step({'RejectPusherManPB': False, 'BeltConveyor4mManPB': False}, e={'MainStep': 2}),
    step({'Reset': True}, e={'Mode': 4, 'RejectPusher': False})])

out = Path(__file__).resolve().parents[1].joinpath('practicum_oip_test.yaml')
out.write_text(json.dumps({'tolerance': 0.001, 'tests': tests}, indent=2) + '\n')
print(f'Generated {len(tests)} acceptance scenarios.')
