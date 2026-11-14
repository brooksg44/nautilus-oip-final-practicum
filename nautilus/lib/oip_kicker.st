(* One sort lane on belt 2 (OIP build): a sort-position eye and a Pusher.

   The eye sits upstream of the pusher blade, so when it first sees a box
   the box is not yet in front of the blade. Track how far the box has
   travelled at the commanded belt speed; when its centre reaches the blade,
   hold belt 2 still and run one Pusher cycle (out to the extended limit,
   back to the retracted limit). Belt 2 stays held until the blade is home,
   so the push does not depend on belt speed or on the Modbus round trip.
   In Manual the lane's Turn toggle jogs the pusher through ManualExtend. *)
FUNCTION_BLOCK OipKicker
VAR_INPUT
    Enable : BOOL;       (* Auto mode: tracking and cycles allowed *)
    PusherOn : BOOL;     (* Auto or Manual: the pusher may move at all *)
    Armed : BOOL;        (* controller chose this lane (RawFlag/BaseFlag/LidFlag) *)
    Eye : BOOL;          (* this lane's sort-position eye *)
    SpeedMps : REAL;     (* belt 2 commanded speed while it runs *)
    Dt : REAL;           (* scan time, s *)
    LeadM : REAL;        (* eye-to-blade distance for the box centre, m *)
    LatencyS : REAL;     (* I/O round trip to subtract from the lead, s *)
    ManualExtend : BOOL; (* Manual mode jog *)
    RetractedLS : BOOL;  (* pusher limit switches *)
    ExtendedLS : BOOL;
    ResetFault : BOOL;
END_VAR
VAR_OUTPUT
    Extend : BOOL;       (* pusher coil *)
    HoldBelt : BOOL;     (* belt 2 must stand still *)
    Fault : BOOL;        (* pusher stroke timeout / limit conflict *)
    Phase : INT;         (* 0 idle, 1 tracking, 2 pushing *)
END_VAR
VAR
    Push : Pusher;
    Travel : REAL;
    PrevEye : BOOL;
    Target : REAL;
    Fire : BOOL;
END_VAR

Fire := FALSE;
IF NOT Enable THEN
    Phase := 0;
END_IF;
CASE Phase OF
0:
    IF Armed AND Eye AND NOT PrevEye THEN
        Travel := 0.0;
        Phase := 1;
    END_IF;
1:
    Travel := Travel + SpeedMps * Dt;
    Target := LeadM - SpeedMps * LatencyS;
    IF Target < 0.0 THEN Target := 0.0; END_IF;
    IF NOT Armed THEN
        Phase := 0;
    ELSIF Travel >= Target THEN
        Fire := TRUE;
        Phase := 2;
    END_IF;
2:
    (* wait for the pusher cycle below to finish (or fault) *)
    Phase := 2;
ELSE
    Phase := 0;
END_CASE;

Push(Enable := PusherOn, Cycle := Fire, ManualExtend := ManualExtend AND NOT Enable,
     RetractedLS := RetractedLS, ExtendedLS := ExtendedLS, ResetFault := ResetFault);

IF (Phase = 2) AND NOT Fire AND NOT Push.Busy THEN
    Phase := 0;   (* home again, or faulted *)
END_IF;

Extend := Push.Extend;
HoldBelt := (Phase = 2) OR Push.Busy;
Fault := Push.Fault;
PrevEye := Eye;
END_FUNCTION_BLOCK
