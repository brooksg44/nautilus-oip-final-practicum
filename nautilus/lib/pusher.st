(* Pusher - one pneumatic pusher with a retracted and an extended limit
   switch (Factory I/O pusher, OIP "Pusher with limits").

   Cycle (rising edge, pusher home): extend until the extended limit
   closes, then retract until the retracted limit closes. Done pulses for
   one scan when the blade is home again. ManualExtend drives the coil
   directly while the pusher is idle (jogging in manual mode).

   Each stroke must finish within StrokeTimeout, otherwise the pusher
   retracts and Fault latches (a jammed blade or a dead limit switch).
   Both limits on at once is also a fault. ResetFault (rising edge) clears it.
   Enable FALSE retracts at once and abandons any cycle. *)
FUNCTION_BLOCK Pusher
VAR_INPUT
    Enable : BOOL;              (* FALSE: coil off, cycle abandoned *)
    Cycle : BOOL;               (* rising edge: one full out-and-back stroke *)
    ManualExtend : BOOL;        (* while idle: extend while TRUE *)
    RetractedLS : BOOL;         (* limit switch: blade fully home *)
    ExtendedLS : BOOL;          (* limit switch: blade fully out *)
    StrokeTimeout : TIME := T#2s;
    ResetFault : BOOL;
END_VAR
VAR_OUTPUT
    Extend : BOOL;              (* the pusher coil *)
    Busy : BOOL;                (* a cycle is running *)
    Done : BOOL;                (* one scan: the cycle finished, blade home *)
    AtHome : BOOL;              (* retracted limit made and coil off *)
    Fault : BOOL;               (* latched stroke timeout or limit conflict *)
    State : INT;                (* 0 idle, 1 extending, 2 retracting, 9 fault *)
END_VAR
VAR
    StrokeTmr : TON;
    PrevCycle : BOOL;
    PrevReset : BOOL;
    CycleEdge : BOOL;
    ResetEdge : BOOL;
    StrokeTimedOut : BOOL;
    StateAtStart : INT;
END_VAR

CycleEdge := Cycle AND NOT PrevCycle;
ResetEdge := ResetFault AND NOT PrevReset;
PrevCycle := Cycle;
PrevReset := ResetFault;
Done := FALSE;

StrokeTimedOut := StrokeTmr.Q;   (* from last scan's timer call below *)
StateAtStart := State;

IF NOT Enable THEN
    IF State <> 9 THEN State := 0; END_IF;
ELSIF RetractedLS AND ExtendedLS THEN
    State := 9;
ELSE
    CASE State OF
    0:
        IF CycleEdge AND RetractedLS THEN State := 1; END_IF;
    1:
        IF ExtendedLS THEN
            State := 2;
        ELSIF StrokeTimedOut THEN
            State := 9;
        END_IF;
    2:
        IF RetractedLS THEN
            State := 0;
            Done := TRUE;
        ELSIF StrokeTimedOut THEN
            State := 9;
        END_IF;
    9:
        IF ResetEdge THEN State := 0; END_IF;
    ELSE
        State := 0;
    END_CASE;
END_IF;

Fault := State = 9;
Busy := (State = 1) OR (State = 2);
Extend := Enable AND ((State = 1) OR ((State = 0) AND ManualExtend));
AtHome := RetractedLS AND NOT Extend;
(* Stroke timer: runs while the blade travels, restarted on each new stroke. *)
StrokeTmr(IN := ((State = 1) OR (State = 2)) AND (State = StateAtStart), PT := StrokeTimeout);
END_FUNCTION_BLOCK
