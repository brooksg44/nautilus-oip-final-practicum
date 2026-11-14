PROGRAM Main
(* Open Industry Project build of the Final Practicum.
   The three controller FBs (ST/LD/FBD) are the same as the Factory I/O
   project. This program wraps them with an OIP adapter that fires the
   pop-up diverters from the sort-position eyes, writes belt speeds in
   m/s, and packs the stack light. The reject pusher's limit switches
   (RejPushBackLimit / RejPushFrontLimit) come from the scene's
   'Pusher with limits' part over Modbus, as in Factory I/O. *)
VAR_EXTERNAL
    Stop : BOOL;
    Reset : BOOL;
    Reset2PB : BOOL;
    LidPusherRetracted : BOOL;
    LidPusherExtended : BOOL;
    BasePusherRetracted : BOOL;
    BasePusherExtended : BOOL;
    RawPusherRetracted : BOOL;
    RawPusherExtended : BOOL;
    LidPusherFault : BOOL;
    RawHomePL : BOOL;
    RawOutPL : BOOL;
    BaseHomePL : BOOL;
    BaseOutPL : BOOL;
    LidHomePL : BOOL;
    LidOutPL : BOOL;
    RejectHomePL : BOOL;
    RejectOutPL : BOOL;
    RejPushBackLimit : BOOL;
    RejPushFrontLimit : BOOL;
    BasePusherFault : BOOL;
    RawPusherFault : BOOL;
    LidSortEye : BOOL;
    BaseSortEye : BOOL;
    RawSortEye : BOOL;
    LidDiverter : BOOL;
    BaseDiverter : BOOL;
    RawDiverter : BOOL;
    StackLight : INT;
    Belt1SpeedMps : REAL;
    Belt2SpeedMps : REAL;
    ScanDtS : REAL;
    LanguageSelect : INT;
    ActiveLanguage : INT;
    LanguageValid : BOOL;
    RawFlag : BOOL;
    BaseFlag : BOOL;
    LidFlag : BOOL;
    RejectFlag : BOOL;
    EmitFlag : BOOL;

    MainStep : INT;
    AutoStep : INT;
    Mode : INT;
    BeltSpeedRef : INT;
    LastBeltRefSpeed : INT;
    TargetBeltSpeed : REAL;
    BaseLightInd : BOOL;
    BaseSorterBeltCCW : BOOL;
    BaseSorterBeltCW : BOOL;
    BaseSorterBeltTurn : BOOL;
    DecSpdX10Light : BOOL;
    DecSpdX100Light : BOOL;
    Emitter : BOOL;
    Spare : BOOL;
    IncSpdX1Light : BOOL;
    IncSpdX10Light : BOOL;
    LabPLCRunning : BOOL;
    LidLightInd : BOOL;
    LidSorterBeltCCW : BOOL;
    LidSorterBeltCW : BOOL;
    LidSorterBeltTurn : BOOL;
    LocalPanelActive : BOOL;
    RawLightInd : BOOL;
    RawSorterBeltTurn : BOOL;
    RawSorterBeltCCW : BOOL;
    RawSorterBeltCW : BOOL;
    RejectPusher : BOOL;
    RemotePanelActive : BOOL;
    Remover1 : BOOL;
    Remover2 : BOOL;
    Remover3 : BOOL;
    ControlOnPL : BOOL;
    SkidPLCRunning : BOOL;
    StartPL : BOOL;
    StopBlade : BOOL;
    StopPL : BOOL;
    WarningLight1 : BOOL;
    AutoPL : BOOL;
    RawSorterBeltCCWPL : BOOL;
    RawSorterBeltCWPL : BOOL;
    RawSorterBeltTurnPL : BOOL;
    BaseSorterBeltCCWPL : BOOL;
    BaseSorterBeltCWPL : BOOL;
    BaseSorterBeltTurnPL : BOOL;
    LidSorterBeltCCWPL : BOOL;
    LidSorterBeltCWPL : BOOL;
    LidSorterBeltTurnPL : BOOL;
    ManualPL : BOOL;
    BeltConveyor4mPL : BOOL;
    RejectPusherPL : BOOL;
    ControlOnPL2 : BOOL;
    EStoppedPL : BOOL;
    RunningPL : BOOL;
    BeltConveyor4mSpeed : REAL;
    ProductionRate : INT;
    BeltConveyor4mSpeed2 : REAL;
END_VAR
VAR
    stController : PracticumST;
    ldController : PracticumLD;
    fbdController : PracticumFBD;
    Initialized : BOOL;
    Changed : BOOL;
    LidKick : OipKicker;   (* one per sort lane: track, stop belt 2, Pusher cycle *)
    BaseKick : OipKicker;
    RawKick : OipKicker;
    Belt2Hold : BOOL;
    StackBits : INT;
END_VAR
VAR CONSTANT
    EYE_TO_BLADE : REAL := 0.3;  (* m: box centre to blade centre when the eye first sees it
                                     (eye 0.1 m before the blade + half a 0.4 m box) *)
    IO_LATENCY : REAL := 0.08;   (* s: Modbus read + write round trip to OIP *)
END_VAR

(* ---- Controller (unchanged from the Factory I/O project) ---------- *)

LanguageValid := (LanguageSelect >= 1) AND (LanguageSelect <= 3);
Changed := Initialized AND (LanguageSelect <> ActiveLanguage);
IF NOT Initialized OR Changed OR NOT LanguageValid THEN
    (* Reset dormant instances too, so their edge/timer/latch histories
       cannot survive a language switch. Counter totals remain shared. *)
    stController(ResetState := TRUE);
    ldController(ResetState := TRUE);
    fbdController(ResetState := TRUE);
    MainStep := 1;
    AutoStep := 16;
    Mode := 0;
    BeltSpeedRef := 0;
    LastBeltRefSpeed := 0;
    TargetBeltSpeed := 0.0;
    RawFlag := FALSE;
    BaseFlag := FALSE;
    LidFlag := FALSE;
    RejectFlag := FALSE;
    EmitFlag := FALSE;

END_IF;
IF LanguageValid THEN ActiveLanguage := LanguageSelect; ELSE ActiveLanguage := 0; END_IF;
IF Changed OR NOT LanguageValid THEN
    BaseLightInd := FALSE;
    BaseSorterBeltCCW := FALSE;
    BaseSorterBeltCW := FALSE;
    BaseSorterBeltTurn := FALSE;
    DecSpdX10Light := FALSE;
    DecSpdX100Light := FALSE;
    Emitter := FALSE;
    Spare := FALSE;
    IncSpdX1Light := FALSE;
    IncSpdX10Light := FALSE;
    LabPLCRunning := FALSE;
    LidLightInd := FALSE;
    LidSorterBeltCCW := FALSE;
    LidSorterBeltCW := FALSE;
    LidSorterBeltTurn := FALSE;
    LocalPanelActive := FALSE;
    RawLightInd := FALSE;
    RawSorterBeltTurn := FALSE;
    RawSorterBeltCCW := FALSE;
    RawSorterBeltCW := FALSE;
    RejectPusher := FALSE;
    RemotePanelActive := FALSE;
    Remover1 := FALSE;
    Remover2 := FALSE;
    Remover3 := FALSE;
    ControlOnPL := FALSE;
    SkidPLCRunning := FALSE;
    StartPL := FALSE;
    StopBlade := FALSE;
    StopPL := TRUE;
    WarningLight1 := FALSE;
    AutoPL := FALSE;
    RawSorterBeltCCWPL := FALSE;
    RawSorterBeltCWPL := FALSE;
    RawSorterBeltTurnPL := FALSE;
    BaseSorterBeltCCWPL := FALSE;
    BaseSorterBeltCWPL := FALSE;
    BaseSorterBeltTurnPL := FALSE;
    LidSorterBeltCCWPL := FALSE;
    LidSorterBeltCWPL := FALSE;
    LidSorterBeltTurnPL := FALSE;
    ManualPL := FALSE;
    BeltConveyor4mPL := FALSE;
    RejectPusherPL := FALSE;
    ControlOnPL2 := FALSE;
    EStoppedPL := FALSE;
    RunningPL := FALSE;
    BeltConveyor4mSpeed := 0.0;
    BeltSpeedRef := 0;
    ProductionRate := 0;
    BeltConveyor4mSpeed2 := 0.0;
ELSE
    (* Exactly one normal controller invocation per scan. *)
    CASE ActiveLanguage OF
    1: stController(ResetState := FALSE);
    2: ldController(ResetState := FALSE);
    3: fbdController(ResetState := FALSE);
    END_CASE;
END_IF;

(* ---- OIP output adapter --------------------------------------------
   A pop-up diverter only moves a box that is in front of it. In Auto the
   lane chosen by the controller (RawFlag/BaseFlag/LidFlag, steps 24/27/28
   to 224/227/228) arms that lane's OipKicker: when the sort eye sees the
   box it tracks the box to the blade, holds belt 2, pushes and retracts.
   In Manual the Turn toggle drives the diverter directly. *)
Belt1SpeedMps := INT_TO_REAL(BeltSpeedRef) / 100.0;
LidKick(Enable := Mode = 5, PusherOn := (Mode = 4) OR (Mode = 5),
        Armed := (Mode = 5) AND LidFlag, Eye := LidSortEye,
        SpeedMps := Belt1SpeedMps, Dt := ScanDtS, LeadM := EYE_TO_BLADE, LatencyS := IO_LATENCY,
        ManualExtend := LidSorterBeltTurn, RetractedLS := LidPusherRetracted,
        ExtendedLS := LidPusherExtended, ResetFault := Reset OR Reset2PB);
BaseKick(Enable := Mode = 5, PusherOn := (Mode = 4) OR (Mode = 5),
         Armed := (Mode = 5) AND BaseFlag, Eye := BaseSortEye,
         SpeedMps := Belt1SpeedMps, Dt := ScanDtS, LeadM := EYE_TO_BLADE, LatencyS := IO_LATENCY,
         ManualExtend := BaseSorterBeltTurn, RetractedLS := BasePusherRetracted,
         ExtendedLS := BasePusherExtended, ResetFault := Reset OR Reset2PB);
RawKick(Enable := Mode = 5, PusherOn := (Mode = 4) OR (Mode = 5),
        Armed := (Mode = 5) AND RawFlag, Eye := RawSortEye,
        SpeedMps := Belt1SpeedMps, Dt := ScanDtS, LeadM := EYE_TO_BLADE, LatencyS := IO_LATENCY,
        ManualExtend := RawSorterBeltTurn, RetractedLS := RawPusherRetracted,
        ExtendedLS := RawPusherExtended, ResetFault := Reset OR Reset2PB);
LidDiverter := LidKick.Extend;
BaseDiverter := BaseKick.Extend;
RawDiverter := RawKick.Extend;
LidPusherFault := LidKick.Fault;
BasePusherFault := BaseKick.Fault;
RawPusherFault := RawKick.Fault;
(* Local panel: each pusher's HOME / OUT lamps show its limit switches
   (they replace the Factory I/O sorter CW / CCW lamps). *)
RawHomePL := RawPusherRetracted;   RawOutPL := RawPusherExtended;
BaseHomePL := BasePusherRetracted; BaseOutPL := BasePusherExtended;
LidHomePL := LidPusherRetracted;   LidOutPL := LidPusherExtended;
RejectHomePL := RejPushBackLimit;  RejectOutPL := RejPushFrontLimit;
Belt2Hold := LidKick.HoldBelt OR BaseKick.HoldBelt OR RawKick.HoldBelt;

(* BeltSpeedRef is cm/s (0..300); OIP belts take m/s. Belt 2 stands
   still while a diverter pushes. *)
IF Belt2Hold THEN Belt2SpeedMps := 0.0; ELSE Belt2SpeedMps := Belt1SpeedMps; END_IF;

(* Stack light bitmask: bit0 green Running, bit1 amber Warning, bit2 red E-stopped. *)
StackBits := 0;
IF RunningPL THEN StackBits := StackBits + 1; END_IF;
IF WarningLight1 THEN StackBits := StackBits + 2; END_IF;
IF EStoppedPL THEN StackBits := StackBits + 4; END_IF;
StackLight := StackBits;

Initialized := TRUE;
END_PROGRAM
