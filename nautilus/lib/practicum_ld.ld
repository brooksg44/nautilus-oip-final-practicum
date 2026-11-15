(* Ladder build of the Final Practicum controller for the Open Industry
   Project (OIP) scene. Originally generated from the Factory I/O
   control.st by tools/build_languages.py, then restructured by hand: one
   coil per BOOL, named intermediate contacts, short rungs, and only the
   devices the OIP scene has.

   Gone with Factory I/O: the sorter belts' CW/CCW commands, buttons and
   lamps, the removers, the spare output and the 0..10 V belt speeds. The
   sort lanes are pushers now. This block chooses the lane (RawFlag,
   BaseFlag, LidFlag) and gives the belt speed in cm/s (BeltSpeedRef); Main
   times each push from the lane's sort eye, converts the speed to m/s and
   packs the stack light from RunningPL, WarningLight1 and EStoppedPL.

   While ResetState is TRUE the block clears its private state, leaves the
   shared numbers (steps, speeds, totals) alone and drops every command;
   Main then decides what the outputs are for that scan. *)
FUNCTION_BLOCK PracticumLD
VAR_EXTERNAL
    AtExit : BOOL;
    AutoSS : BOOL;
    RejectDiffuseSensor : BOOL;
    DecSpdX10 : BOOL;
    DecSpdX100 : BOOL;
    EmergencyStop : BOOL;
    EmergencyStop2 : BOOL;
    FIOReset : BOOL;
    IncSpdX100 : BOOL;
    IncSpdX10 : BOOL;
    LocalControlPanel : BOOL;
    ManualSS : BOOL;
    RejPushBackLimit : BOOL;
    RejPushFrontLimit : BOOL;
    RemoteControlPanel : BOOL;
    Reset : BOOL;
    Start : BOOL;
    Stop : BOOL;
    ClassifyDefuseSensor : BOOL;
    BaseSorterBeltTurnManPB : BOOL;
    LidSorterBeltTurnManPB : BOOL;
    RawSorterBeltTurnManPB : BOOL;
    BeltConveyor4mManPB : BOOL;
    RejectPusherManPB : BOOL;
    SendSortPB : BOOL;
    SendRejectPB : BOOL;
    Reset2PB : BOOL;
    VisionSensor1 : INT;
    BaseLightInd : BOOL;
    BaseSorterBeltTurn : BOOL;
    DecSpdX10Light : BOOL;
    DecSpdX100Light : BOOL;
    Emitter : BOOL;
    IncSpdX1Light : BOOL;
    IncSpdX10Light : BOOL;
    LidLightInd : BOOL;
    LidSorterBeltTurn : BOOL;
    LocalPanelActive : BOOL;
    RawLightInd : BOOL;
    RawSorterBeltTurn : BOOL;
    RejectPusher : BOOL;
    RemotePanelActive : BOOL;
    ControlOnPL : BOOL;
    StartPL : BOOL;
    StopBlade : BOOL;
    StopPL : BOOL;
    WarningLight1 : BOOL;
    AutoPL : BOOL;
    RawSorterBeltTurnPL : BOOL;
    BaseSorterBeltTurnPL : BOOL;
    LidSorterBeltTurnPL : BOOL;
    ManualPL : BOOL;
    BeltConveyor4mPL : BOOL;
    RejectPusherPL : BOOL;
    ControlOnPL2 : BOOL;
    EStoppedPL : BOOL;
    RunningPL : BOOL;
    BaseCounter : INT;
    BeltSpeedRef : INT;
    LidCounter : INT;
    ProductionRate : INT;
    RawCounter : INT;
    RejectFlag : BOOL;
    EmitFlag : BOOL;
    RawFlag : BOOL;
    BaseFlag : BOOL;
    LidFlag : BOOL;
    LastBeltRefSpeed : INT;
    ScanDtS : REAL;
    MainStep : INT;
    AutoStep : INT;
    Mode : INT;
END_VAR
VAR_INPUT
    ResetState : BOOL;
END_VAR
VAR
    ClockS : REAL;
    Blink : BOOL;
    AutoElapsed : REAL;
    EmitRemaining : REAL;
    SortElapsed : REAL;
    ResetHeld : REAL;
    PrevMode : INT;
    ScanStep : INT;
    SafetyTrip : BOOL;
    ResetPermit : BOOL;
    MachineReady : BOOL;
    InManual : BOOL;
    InAuto : BOOL;
    ModeChanged : BOOL;
    WarnStep : BOOL;
    WarnDone : BOOL;
    RejectCall : BOOL;
    SortCall : BOOL;
    SortDwell : BOOL;
    SortDone : BOOL;
    RejectDone : BOOL;
    BeltPbEdge : BOOL;
    RejectPbEdge : BOOL;
    RawPushPbEdge : BOOL;
    BasePushPbEdge : BOOL;
    LidPushPbEdge : BOOL;
    ManBelt : BOOL;
    ManReject : BOOL;
    ManRawPush : BOOL;
    ManBasePush : BOOL;
    ManLidPush : BOOL;
END_VAR
VAR CONSTANT
    BLINK_PERIOD_S : REAL := 1.0;     (* lamp blink period *)
    BLINK_ON_S : REAL := 0.5;         (* lit for the first half of the period *)
    WARN_TIME_S : REAL := 3.0;        (* start warning before the belt moves *)
    EMIT_PULSE_S : REAL := 0.5;       (* emitter pulse that releases one box *)
    SORT_DWELL_S : REAL := 0.5;       (* wait after a sorted box reaches the exit *)
    RESET_HOLD_S : REAL := 5.0;       (* Reset hold that clears the totals *)
    VISION_REJECT_MIN : INT := 7;     (* colour codes 7..9 (metal) are rejects *)
    VISION_REJECT_MAX : INT := 9;
END_VAR

LD
  // ---- Blink clock -------------------------------------------------------
  RUNG clock_clear (* a language switch restarts the blink and every private timer *)
    ResetState { ClockS := 0.0 } { AutoElapsed := 0.0 } { EmitRemaining := 0.0 }
  RUNG timers_clear (* same restart for the remaining private values *)
    ResetState { SortElapsed := 0.0 } { ResetHeld := 0.0 } { PrevMode := 0 }
  RUNG clock_run (* free-running clock that paces every blinking lamp *)
    /ResetState { ClockS := ClockS + ScanDtS }
  RUNG clock_wrap (* keep the clock inside one blink period *)
    /ResetState GE(ClockS, BLINK_PERIOD_S) { ClockS := ClockS - BLINK_PERIOD_S }
  RUNG blink (* on for the first half of each period *)
    /ResetState LT(ClockS, BLINK_ON_S) ( Blink )

  // ---- Main chart X1/X2/X3 -----------------------------------------------
  // MainStep: 1 = E-stopped, 2 = waiting for reset, 3 = control on.
  // Stop and both emergency stops are NC: TRUE = healthy.
  RUNG safety_trip (* either E-stop open, or a simulation reset, drops control *)
    [ /EmergencyStop | /EmergencyStop2 | FIOReset ] ( SafetyTrip )
  RUNG reset_permit (* a reset only counts with the line clear and the exit eye made *)
    [ Reset | Reset2PB ] /ClassifyDefuseSensor /RejectDiffuseSensor AtExit ( ResetPermit )
  RUNG main_control_on (* waiting for reset, Stop healthy, operator resets: control on *)
    /ResetState Stop EQ(MainStep, 2) ResetPermit { MainStep := 3 }
  RUNG main_estop_cleared (* E-stops are back and Stop is healthy: wait for a reset *)
    /ResetState Stop EQ(MainStep, 1) { MainStep := 2 }
  RUNG main_stop_pressed (* Stop takes control away until the next reset *)
    /ResetState /Stop NE(MainStep, 1) { MainStep := 2 }
  RUNG main_tripped (* last, so a safety trip beats every other transition *)
    /ResetState SafetyTrip { MainStep := 1 }
  RUNG machine_ready (* the only motion permissive: the real X3 state, never a lamp *)
    /ResetState EQ(MainStep, 3) ( MachineReady )
  RUNG control_on_lamps (* steady with control on, blinking while it is waited for *)
    [ MachineReady | Blink ] ( ControlOnPL ) ( ControlOnPL2 )
  RUNG stop_lamp (* lit whenever control is off *)
    /MachineReady ( StopPL )
  RUNG estopped_lamp (* blinks until the E-stops are healthy again *)
    EQ(MainStep, 1) Blink ( EStoppedPL )

  // ---- Mode: 0 = none, 4 = manual (X4), 5 = automatic (X5) ---------------
  RUNG mode_none (* no mode unless a selector rung below claims one *)
    /ResetState { Mode := 0 }
  RUNG mode_manual (* conflicting selectors give no mode at all *)
    MachineReady ManualSS /AutoSS { Mode := 4 }
  RUNG mode_auto (* conflicting selectors give no mode at all *)
    MachineReady AutoSS /ManualSS { Mode := 5 }
  RUNG in_manual (* manual chart active; also its panel lamp *)
    /ResetState EQ(Mode, 4) ( InManual ) ( ManualPL )
  RUNG in_auto (* automatic chart active; also its panel lamp *)
    /ResetState EQ(Mode, 5) ( InAuto ) ( AutoPL )
  RUNG mode_changed (* leaving a mode deactivates its child chart *)
    /ResetState NE(Mode, PrevMode) ( ModeChanged )
  RUNG mode_change_stops_belt (* a new mode starts stopped, at the first auto step *)
    ModeChanged { BeltSpeedRef := 0 } { LastBeltRefSpeed := 0 } { AutoStep := 16 }
  RUNG mode_change_clears_timers (* and with no sequence time carried over *)
    ModeChanged { AutoElapsed := 0.0 } { EmitRemaining := 0.0 } { SortElapsed := 0.0 }

  // ---- Belt speed reference, cm/s ----------------------------------------
  // The edge contacts lead their rungs so they see every scan.
  RUNG speed_up_10 (* one press, one 10 cm/s step *)
    +IncSpdX10 MachineReady { BeltSpeedRef := BeltSpeedRef + 10 }
  RUNG speed_up_100 (* one press, one 100 cm/s step *)
    +IncSpdX100 MachineReady { BeltSpeedRef := BeltSpeedRef + 100 }
  RUNG speed_down_10 (* one press, one 10 cm/s step *)
    +DecSpdX10 MachineReady { BeltSpeedRef := BeltSpeedRef - 10 }
  RUNG speed_down_100 (* one press, one 100 cm/s step *)
    +DecSpdX100 MachineReady { BeltSpeedRef := BeltSpeedRef - 100 }
  RUNG speed_clamp (* the belt takes 0..300 cm/s *)
    MachineReady { BeltSpeedRef := LIMIT( 0 , BeltSpeedRef , 300 ) }
  RUNG speed_remember (* the operator's last setting is what auto returns to *)
    [ +IncSpdX10 | +IncSpdX100 | +DecSpdX10 | +DecSpdX100 ] MachineReady { LastBeltRefSpeed := BeltSpeedRef }

  // ---- Automatic chart ---------------------------------------------------
  // X16/X21 wait for Start, X20 three second warning, X19 emit a box,
  // X22 classify, X24/X27/X28 sort (+100 box left the exit eye, +200 box
  // back at the exit eye), X25/X85/X86 reject.
  // Every transition tests ScanStep, the step the scan started in, so the
  // chart moves one step per scan however the rungs are ordered.
  RUNG auto_scan_step (* freeze the step for this scan *)
    InAuto { ScanStep := AutoStep }
  RUNG auto_scan_step_idle (* no step matches outside automatic *)
    /InAuto { ScanStep := 0 }
  RUNG auto_armed (* entry step: go and wait for Start *)
    EQ(ScanStep, 16) { AutoStep := 21 }
  RUNG auto_start (* Start begins the warning period *)
    EQ(ScanStep, 21) Start { AutoStep := 20 } { AutoElapsed := 0.0 }
  RUNG warn_step (* warning period before anything moves *)
    EQ(ScanStep, 20) ( WarnStep )
  RUNG warning_light (* flashes opposite the panel lamps during the warning *)
    WarnStep /Blink ( WarningLight1 )
  RUNG warn_timing (* time the warning *)
    WarnStep { AutoElapsed := AutoElapsed + ScanDtS }
  RUNG warn_done (* warning served: the line may run *)
    WarnStep GE(AutoElapsed, WARN_TIME_S) ( WarnDone )
  RUNG running_lamp (* seals in from the end of the warning until the mode is lost *)
    [ WarnDone | RunningPL ] /ModeChanged NE(Mode, 0) ( RunningPL )
  RUNG emit_step (* the line is waiting for the next box *)
    EQ(ScanStep, 19) ( EmitFlag )
  RUNG box_at_classifier (* slow to 60 cm/s past the colour sensor, remembering the speed *)
    +ClassifyDefuseSensor EQ(ScanStep, 19) { LastBeltRefSpeed := BeltSpeedRef } { BeltSpeedRef := 60 } { AutoStep := 22 }
  RUNG reject_call (* SORT/REJECT selector on REJECT, or a metal box at the colour sensor *)
    [ SendRejectPB | GE(VisionSensor1, VISION_REJECT_MIN) LE(VisionSensor1, VISION_REJECT_MAX) ] ( RejectCall )
  RUNG classify_reject (* reject has priority if both commands are present *)
    EQ(ScanStep, 22) RejectCall { AutoStep := 25 }
  RUNG sort_call (* selector on SORT and nothing asking for a reject *)
    EQ(ScanStep, 22) /RejectCall SendSortPB ( SortCall )
  RUNG sort_raw (* colour codes 1 and 4 are raw material: count it, resume speed *)
    SortCall [ EQ(VisionSensor1, 1) | EQ(VisionSensor1, 4) ] { AutoStep := 24 } { RawCounter := RawCounter + 1 } { BeltSpeedRef := LastBeltRefSpeed }
  RUNG sort_base (* colour codes 3 and 6 are bases: count it, resume speed *)
    SortCall [ EQ(VisionSensor1, 3) | EQ(VisionSensor1, 6) ] { AutoStep := 27 } { BaseCounter := BaseCounter + 1 } { BeltSpeedRef := LastBeltRefSpeed }
  RUNG sort_lid (* colour codes 2 and 5 are lids: count it, resume speed *)
    SortCall [ EQ(VisionSensor1, 2) | EQ(VisionSensor1, 5) ] { AutoStep := 28 } { LidCounter := LidCounter + 1 } { BeltSpeedRef := LastBeltRefSpeed }
  RUNG sort_exit_clear (* the previous box has left the exit eye *)
    [ EQ(ScanStep, 24) | EQ(ScanStep, 27) | EQ(ScanStep, 28) ] /AtExit { AutoStep := AutoStep + 100 }
  RUNG sort_exit_made (* the exit eye is made again: start the dwell *)
    [ EQ(ScanStep, 124) | EQ(ScanStep, 127) | EQ(ScanStep, 128) ] AtExit { AutoStep := AutoStep + 100 } { SortElapsed := 0.0 }
  RUNG sort_dwell (* short settle time before the next box is released *)
    [ EQ(ScanStep, 224) | EQ(ScanStep, 227) | EQ(ScanStep, 228) ] ( SortDwell )
  RUNG sort_dwell_timing (* time the dwell *)
    SortDwell { SortElapsed := SortElapsed + ScanDtS }
  RUNG sort_done (* dwell served *)
    SortDwell GE(SortElapsed, SORT_DWELL_S) ( SortDone )
  RUNG reject_at_pusher (* stop the belt with the box in front of the pusher *)
    EQ(ScanStep, 25) RejectDiffuseSensor { AutoStep := 85 } { BeltSpeedRef := 0 }
  RUNG reject_pushed (* pusher fully out: bring it home *)
    EQ(ScanStep, 85) RejPushFrontLimit { AutoStep := 86 }
  RUNG reject_done (* pusher home again *)
    EQ(ScanStep, 86) RejPushBackLimit ( RejectDone )
  RUNG next_box (* each path ends the same way: resume speed and emit one box *)
    [ WarnDone | SortDone | RejectDone ] { AutoStep := 19 } { EmitRemaining := EMIT_PULSE_S } { BeltSpeedRef := LastBeltRefSpeed }
  RUNG raw_lane (* arms this lane's pusher in Main until the box has gone *)
    InAuto [ EQ(AutoStep, 24) | EQ(AutoStep, 124) | EQ(AutoStep, 224) ] ( RawFlag )
  RUNG base_lane (* arms this lane's pusher in Main until the box has gone *)
    InAuto [ EQ(AutoStep, 27) | EQ(AutoStep, 127) | EQ(AutoStep, 227) ] ( BaseFlag )
  RUNG lid_lane (* arms this lane's pusher in Main until the box has gone *)
    InAuto [ EQ(AutoStep, 28) | EQ(AutoStep, 128) | EQ(AutoStep, 228) ] ( LidFlag )
  RUNG reject_lane (* a reject is travelling to, or sitting at, the pusher *)
    InAuto [ EQ(AutoStep, 25) | EQ(AutoStep, 85) ] ( RejectFlag )
  RUNG raw_sorting (* panel RAW light: a box has just been sent to this lane *)
    InAuto EQ(AutoStep, 24) ( RawLightInd )
  RUNG base_sorting (* panel BASE light: a box has just been sent to this lane *)
    InAuto EQ(AutoStep, 27) ( BaseLightInd )
  RUNG lid_sorting (* panel LID light: a box has just been sent to this lane *)
    InAuto EQ(AutoStep, 28) ( LidLightInd )
  RUNG emitter (* emit for as long as the pulse has time left *)
    InAuto GT(EmitRemaining, 0.0) ( Emitter )
  RUNG emitter_timing (* run the pulse down *)
    Emitter { EmitRemaining := EmitRemaining - ScanDtS }

  // ---- Manual chart: each local-panel button toggles its device ----------
  RUNG belt_pb_edge (* one toggle per press *)
    +BeltConveyor4mManPB ( BeltPbEdge )
  RUNG reject_pb_edge (* one toggle per press *)
    +RejectPusherManPB ( RejectPbEdge )
  RUNG raw_push_pb_edge (* one toggle per press of the lane's PUSH button *)
    +RawSorterBeltTurnManPB ( RawPushPbEdge )
  RUNG base_push_pb_edge (* one toggle per press of the lane's PUSH button *)
    +BaseSorterBeltTurnManPB ( BasePushPbEdge )
  RUNG lid_push_pb_edge (* one toggle per press of the lane's PUSH button *)
    +LidSorterBeltTurnManPB ( LidPushPbEdge )
  RUNG man_belt (* press to run, press again to stop; drops with manual mode *)
    InManual [ BeltPbEdge /ManBelt | ManBelt /BeltPbEdge ] ( ManBelt )
  RUNG man_belt_run (* manual belt speed is fixed at 60 cm/s *)
    InManual BeltPbEdge ManBelt { BeltSpeedRef := 60 }
  RUNG man_belt_stop (* the second press stops the belt *)
    InManual BeltPbEdge /ManBelt { BeltSpeedRef := 0 }
  RUNG man_reject (* press to extend, press again to retract *)
    InManual [ RejectPbEdge /ManReject | ManReject /RejectPbEdge ] ( ManReject )
  RUNG man_raw_push (* press to send the raw pusher out, press again to bring it home *)
    InManual [ RawPushPbEdge /ManRawPush | ManRawPush /RawPushPbEdge ] ( ManRawPush )
  RUNG man_base_push (* press to send the base pusher out, press again to bring it home *)
    InManual [ BasePushPbEdge /ManBasePush | ManBasePush /BasePushPbEdge ] ( ManBasePush )
  RUNG man_lid_push (* press to send the lid pusher out, press again to bring it home *)
    InManual [ LidPushPbEdge /ManLidPush | ManLidPush /LidPushPbEdge ] ( ManLidPush )
  RUNG reset_hold_timing (* time how long the local Reset is held in manual *)
    InManual Reset { ResetHeld := ResetHeld + ScanDtS }
  RUNG reset_hold_broken (* the hold must be continuous *)
    [ /InManual | /Reset ] { ResetHeld := 0.0 }
  RUNG totals_clear (* five seconds of Reset in manual clears the three totals *)
    InManual GE(ResetHeld, RESET_HOLD_S) { RawCounter := 0 } { BaseCounter := 0 } { LidCounter := 0 }

  // ---- Commands: the sequence in automatic, the toggles in manual --------
  // The manual toggles are only ever TRUE in manual mode. The pusher tags
  // keep their Factory I/O names (SorterBeltTurn).
  RUNG raw_pusher_call (* Main jogs the pusher from this in manual; the PUSH lamp shows it *)
    [ RawLightInd | ManRawPush ] ( RawSorterBeltTurn ) ( RawSorterBeltTurnPL )
  RUNG base_pusher_call (* Main jogs the pusher from this in manual; the PUSH lamp shows it *)
    [ BaseLightInd | ManBasePush ] ( BaseSorterBeltTurn ) ( BaseSorterBeltTurnPL )
  RUNG lid_pusher_call (* Main jogs the pusher from this in manual; the PUSH lamp shows it *)
    [ LidLightInd | ManLidPush ] ( LidSorterBeltTurn ) ( LidSorterBeltTurnPL )
  RUNG reject_pusher (* out while the reject step waits for the front limit, or on the manual toggle *)
    [ InAuto EQ(AutoStep, 85) | ManReject ] ( RejectPusher ) ( RejectPusherPL )
  RUNG no_mode_no_speed (* without a mode the belt has no reference *)
    /ResetState EQ(Mode, 0) { BeltSpeedRef := 0 }
  RUNG speed_final_clamp (* whatever set the reference, the belts get 0..300 cm/s *)
    /ResetState { BeltSpeedRef := LIMIT( 0 , BeltSpeedRef , 300 ) }
  RUNG belt_lamp (* lit while the belt is asked to move *)
    /ResetState GT(BeltSpeedRef, 0) ( BeltConveyor4mPL )
  RUNG start_lamp (* blinks to invite Start, steady once the line runs *)
    InAuto [ RunningPL | Blink ] ( StartPL )

  // ---- Panel lamps and housekeeping ---------------------------------------
  RUNG local_panel_lamp (* shows which panel is switched in *)
    /ResetState LocalControlPanel ( LocalPanelActive )
  RUNG remote_panel_lamp (* shows which panel is switched in *)
    /ResetState RemoteControlPanel ( RemotePanelActive )
  RUNG inc_100_lamp (* button feedback; the +100 button's lamp tag is IncSpdX1Light *)
    /ResetState IncSpdX100 ( IncSpdX1Light )
  RUNG inc_10_lamp (* button feedback *)
    /ResetState IncSpdX10 ( IncSpdX10Light )
  RUNG dec_10_lamp (* button feedback *)
    /ResetState DecSpdX10 ( DecSpdX10Light )
  RUNG dec_100_lamp (* button feedback *)
    /ResetState DecSpdX100 ( DecSpdX100Light )
  RUNG stop_blade (* the blade between the belts is never used: hold it down *)
    /ResetState ( R StopBlade )
  RUNG scan_end (* the RATE display shows 0; remember the mode to spot the next change *)
    /ResetState { ProductionRate := 0 } { PrevMode := Mode }
END_LD
END_FUNCTION_BLOCK
