; Intel 8051 emulator for the desktop: the same MCS-51 core as the Pico build,
; in PureBasic, with a Neon Arcade Display Engine front end.
;
;   mcs51_desktop.exe                 the window
;   mcs51_desktop.exe <file.hex|bin>  the window, with a program loaded
;   mcs51_desktop.exe --test          the board's test suites, in a console
;   mcs51_desktop.exe --bench         machine cycles per second, in a console
; Window options (any order, with or without a program):
;   --show-tests       run the test suites as soon as the window is up
;   --run              start the loaded program running
;   --screenshot <png> save the window's own picture after two seconds and close
;   --shot-after <n>   ... after n window frames instead of 120
;
; Build with desktop/build.ps1 (x64, C back end, /DPIAWARE, /OPTIMIZER).

#M51_DISPATCH = 1           ; labels-as-values (measured faster than a procedure table)
#M51_TIMING = 1             ; machine cycles, as the timers need
#M51_8052 = 1
#M51_SFR_HOOK = 0
#M51_XDATA_HOOK = 2          ; XDATA is an array; the board's I/O page goes to its hooks
#M51_XIO_PAGE = $F000
#M51_CODE_HOOK = 0
#M51_SERIAL_HOOK = 0
EnableExplicit

; The engine first: the verification code's globals have plain names
; (Index, Count, ...) that the engine's procedures use as locals.
CompilerIf Not Defined(GL_ENGINE_DIR$, #PB_Constant)
  #GL_ENGINE_DIR$ = "../../Neon-Arcade-Dispay-Engine/"   ; a checkout beside this repository
CompilerEndIf
XIncludeFile #GL_ENGINE_DIR$ + "GlTypes.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUtilities.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlMath.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlSpriteFunctions.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUI.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUIChrome.pbi"

; The board's I/O hooks, called from the core's MOVX macros.
Declare.i M51HookXRead(adr.i)
Declare M51HookXWrite(adr.i, v.i)
XIncludeFile "mcs51_core.pbi"
XIncludeFile "../machine/pm51_font.pico"
XIncludeFile "../machine/pm51_board.pico"
XIncludeFile "pm51_audio.pbi"
XIncludeFile "mcs51_distable.pbi"
XIncludeFile "mcs51_tests.pbi"


; ---------------------------------------------------------------------------
; Disassembly
; ---------------------------------------------------------------------------
Procedure.s H2(v.i)
  ProcedureReturn RSet(Hex(v & $FF), 2, "0")
EndProcedure
Procedure.s H4(v.i)
  ProcedureReturn RSet(Hex(v & $FFFF), 4, "0")
EndProcedure

Procedure.s SfrName(a.i)
  Select a
    Case $80 : ProcedureReturn "P0"
    Case $81 : ProcedureReturn "SP"
    Case $82 : ProcedureReturn "DPL"
    Case $83 : ProcedureReturn "DPH"
    Case $87 : ProcedureReturn "PCON"
    Case $88 : ProcedureReturn "TCON"
    Case $89 : ProcedureReturn "TMOD"
    Case $8A : ProcedureReturn "TL0"
    Case $8B : ProcedureReturn "TL1"
    Case $8C : ProcedureReturn "TH0"
    Case $8D : ProcedureReturn "TH1"
    Case $90 : ProcedureReturn "P1"
    Case $98 : ProcedureReturn "SCON"
    Case $99 : ProcedureReturn "SBUF"
    Case $A0 : ProcedureReturn "P2"
    Case $A8 : ProcedureReturn "IE"
    Case $B0 : ProcedureReturn "P3"
    Case $B8 : ProcedureReturn "IP"
    Case $C8 : ProcedureReturn "T2CON"
    Case $CA : ProcedureReturn "RCAP2L"
    Case $CB : ProcedureReturn "RCAP2H"
    Case $CC : ProcedureReturn "TL2"
    Case $CD : ProcedureReturn "TH2"
    Case $D0 : ProcedureReturn "PSW"
    Case $E0 : ProcedureReturn "ACC"
    Case $F0 : ProcedureReturn "B"
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure.s DirName(a.i)
  Protected n.s
  If a >= $80
    n = SfrName(a)
    If n <> "" : ProcedureReturn n : EndIf
  EndIf
  ProcedureReturn H2(a) + "h"
EndProcedure

Procedure.s BitName(b.i)
  Protected byte.i, n.s
  Select b
    Case $D7 : ProcedureReturn "CY"
    Case $D6 : ProcedureReturn "AC"
    Case $D5 : ProcedureReturn "F0"
    Case $D2 : ProcedureReturn "OV"
    Case $8F : ProcedureReturn "TF1"
    Case $8E : ProcedureReturn "TR1"
    Case $8D : ProcedureReturn "TF0"
    Case $8C : ProcedureReturn "TR0"
    Case $8B : ProcedureReturn "IE1"
    Case $8A : ProcedureReturn "IT1"
    Case $89 : ProcedureReturn "IE0"
    Case $88 : ProcedureReturn "IT0"
    Case $99 : ProcedureReturn "TI"
    Case $98 : ProcedureReturn "RI"
    Case $AF : ProcedureReturn "EA"
    Case $CF : ProcedureReturn "TF2"
  EndSelect
  If b < $80
    byte = $20 + (b >> 3)
    ProcedureReturn H2(byte) + "h." + Str(b & 7)
  EndIf
  n = SfrName(b & $F8)
  If n = "" : n = H2(b & $F8) + "h" : EndIf
  ProcedureReturn n + "." + Str(b & 7)
EndProcedure

; One instruction at adr: its text, and its length in *len.
Procedure.s M51Disasm(adr.i, *len.Integer)
  Protected op.i, t.s, n.i, nxt.i, b1.i, b2.i
  op = M51Code(adr & $FFFF)
  t = M51DisText(op)
  n = M51DisLen(op)
  nxt = (adr + n) & $FFFF
  b1 = M51Code((adr + 1) & $FFFF)
  b2 = M51Code((adr + 2) & $FFFF)
  t = ReplaceString(t, "{W}", H4((b1 << 8) | b2) + "h")
  t = ReplaceString(t, "{L}", H4((b1 << 8) | b2) + "h")
  t = ReplaceString(t, "{P}", H4((nxt & $F800) | ((op >> 5) << 8) | b1) + "h")
  t = ReplaceString(t, "{I1}", H2(b1) + "h")
  t = ReplaceString(t, "{I2}", H2(b2) + "h")
  t = ReplaceString(t, "{D1}", DirName(b1))
  t = ReplaceString(t, "{D2}", DirName(b2))
  t = ReplaceString(t, "{B1}", BitName(b1))
  t = ReplaceString(t, "{R1}", H4(nxt + PeekB(@b1)) + "h")
  t = ReplaceString(t, "{R2}", H4(nxt + PeekB(@b2)) + "h")
  If *len : *len\i = n : EndIf
  ProcedureReturn t
EndProcedure

; ---------------------------------------------------------------------------
; Programs: Intel HEX (.hex / .ihx) or a raw binary loaded at 0
; ---------------------------------------------------------------------------
Global LoadedName$ = "(none)", LoadedTop.i

Procedure.i LoadProgram(path.s)
  Protected f.i, line.s, n.i, adr.i, kind.i, i.i, base.i
  If path = "" : ProcedureReturn 0 : EndIf
  FillMemory(@M51Code(0), 65536, 0)
  LoadedTop = 0
  If LCase(GetExtensionPart(path)) = "hex" Or LCase(GetExtensionPart(path)) = "ihx"
    f = ReadFile(#PB_Any, path)
    If f = 0 : ProcedureReturn 0 : EndIf
    While Not Eof(f)
      line = Trim(ReadString(f))
      If Left(line, 1) <> ":" : Continue : EndIf
      n = Val("$" + Mid(line, 2, 2))
      adr = Val("$" + Mid(line, 4, 4))
      kind = Val("$" + Mid(line, 8, 2))
      If kind = 0
        For i = 0 To n - 1
          M51Code((base + adr + i) & $FFFF) = Val("$" + Mid(line, 10 + i * 2, 2))
        Next
        If base + adr + n > LoadedTop : LoadedTop = base + adr + n : EndIf
      ElseIf kind = 4
        base = Val("$" + Mid(line, 10, 4)) << 16
      EndIf
    Wend
    CloseFile(f)
  Else
    f = ReadFile(#PB_Any, path)
    If f = 0 : ProcedureReturn 0 : EndIf
    n = Lof(f)
    If n > 65536 : n = 65536 : EndIf
    ReadData(f, @M51Code(0), n)
    CloseFile(f)
    LoadedTop = n
  EndIf
  LoadedName$ = GetFilePart(path)
  PM51Reset()
  ProcedureReturn 1
EndProcedure

; ---------------------------------------------------------------------------
; Console modes
; ---------------------------------------------------------------------------
Procedure BenchOne(name.s, prog.s)
  Protected i.i, t.q, s.i
  FillMemory(@M51Code(0), 65536, 0)
  For i = 0 To Len(prog) / 2 - 1
    M51Code(i) = Val("$" + Mid(prog, i * 2 + 1, 2))
  Next
  M51Reset()
  t = Micros()
  For i = 1 To 50
    s + M51Run(1000000)
  Next
  t = Micros() - t
  ; A 12 MHz 8051 runs one million machine cycles a second.
  PrintN(LSet(name, 40) + StrF(s / t, 1) + " M machine cycles/s = " + StrF(s / t, 0) + "x a 12 MHz 8051")
EndProcedure

Procedure.i ConsoleMain()
  Protected arg.s = LCase(ProgramParameter(0))
  If arg = "--test"
    OpenConsole()
    M51TestConsole = 1
    PM51Enabled = 0
    ProcedureReturn Bool(M51RunAllTests() <> 0)
  ElseIf arg = "--frames"
    ; --frames <n> <program> [--wav <file>] [--peek <hex address>]: runs n board
    ; frames headless and reports; the sound of those frames goes to the WAV.
    Protected n.i = Val(ProgramParameter(1)), k.i, wav.s, peek.i = -1, f.i, *pcm, t.q
    OpenConsole()
    For k = 3 To CountProgramParameters() - 1
      If LCase(ProgramParameter(k)) = "--wav" : wav = ProgramParameter(k + 1) : EndIf
      If LCase(ProgramParameter(k)) = "--peek" : peek = Val("$" + ProgramParameter(k + 1)) : EndIf
    Next
    If LoadProgram(ProgramParameter(2)) = 0
      PrintN("cannot load " + ProgramParameter(2)) : ProcedureReturn 2
    EndIf
    *pcm = AllocateMemory(n * #PM51_AUDIO_FRAME * 2 + 16)
    t = ElapsedMilliseconds()
    For k = 0 To n - 1
      PM51RunFrame()
      PM51Mix(*pcm + (k * #PM51_AUDIO_FRAME * 2), #PM51_AUDIO_FRAME, 44100)
    Next
    t = ElapsedMilliseconds() - t
    PrintN("board frames=" + Str(PM51Frame) + " machine cycles=" + Str(M51Cycles) + " ms=" + Str(t) + " PC=" + H4(M51PC))
    If peek >= 0
      PrintN("XDATA " + H4(peek) + " = " + Str(M51XData(peek) | (M51XData(peek + 1) << 8)))
    EndIf
    If wav <> ""
      f = CreateFile(#PB_Any, wav)
      WriteString(f, "RIFF", #PB_Ascii) : WriteLong(f, 36 + n * #PM51_AUDIO_FRAME * 2) : WriteString(f, "WAVEfmt ", #PB_Ascii)
      WriteLong(f, 16) : WriteWord(f, 1) : WriteWord(f, 1) : WriteLong(f, 44100) : WriteLong(f, 88200)
      WriteWord(f, 2) : WriteWord(f, 16) : WriteString(f, "data", #PB_Ascii) : WriteLong(f, n * #PM51_AUDIO_FRAME * 2)
      WriteData(f, *pcm, n * #PM51_AUDIO_FRAME * 2)
      CloseFile(f)
      PrintN("wrote " + wav)
    EndIf
    ProcedureReturn 0
  ElseIf arg = "--bench"
    OpenConsole()
    PrintN("8051 desktop core, timed build, 50 million machine cycles per mix")
    BenchOne("register/branch DJNZ", "DFFE80FC")
    BenchOne("arithmetic ADD/ADDC/XRL/RLC/SUBB", "2401396455339A80F7")
    BenchOne("internal-memory MOV/@R0/dir,dir/CJNE", "7830E6F54085404108B850F680F2")
    BenchOne("external-memory MOVX/INC DPTR/CJNE", "904000E0F4F0A3E583B448F780F2")
    ProcedureReturn 0
  EndIf
  ProcedureReturn -1
EndProcedure

; ---------------------------------------------------------------------------
; The window
; ---------------------------------------------------------------------------
Global Win.i, Gl.i
Global Running.i, BreakAt.i = -1, BreakText.String, BreakCaret.i
Global Status$ = "Load a program, or press Run tests."
Global RateCycles.d, RateShown.d, RateWindowCycles.i, RateWindowStart.q
Global DisTop.i, MemTab.i, MemTop.i, LogTab.i, LogTop.i, SerialLog$
Global Wheel.i, KeyCode.i, KeyChar.i
Global TestsRun.i, TestsFailed.i, ShotPath$, ShotFrames.i
Global ShotAfter.i = 120, Turbo.i, BoardFrames.i, BoardClock.q, ScreenSpr.GLSprite, *ScreenBuf

Procedure DrainSerial()
  Protected w.i
  Repeat
    w = M51SerialTxGet()
    If w < 0 : Break : EndIf
    If (w & 255) = 13
    ElseIf (w & 255) = 10 Or ((w & 255) >= 32 And (w & 255) < 127)
      SerialLog$ + Chr(w & 255)
    Else
      SerialLog$ + "<" + H2(w) + ">"
    EndIf
  ForEver
  If Len(SerialLog$) > 20000 : SerialLog$ = Right(SerialLog$, 16000) : EndIf
EndProcedure

; Self-jump detection: SJMP $ or LJMP / AJMP to itself is how a program ends.
Procedure.i AtSelfJump()
  Protected op.i = M51Code(M51PC)
  If op = $80 And M51Code((M51PC + 1) & $FFFF) = $FE : ProcedureReturn 1 : EndIf
  If op = $02 And ((M51Code((M51PC + 1) & $FFFF) << 8) | M51Code((M51PC + 2) & $FFFF)) = M51PC : ProcedureReturn 1 : EndIf
  ProcedureReturn 0
EndProcedure

Procedure StepOne()
  M51Run(1)
  DrainSerial()
EndProcedure

; One 60 Hz board frame; with a breakpoint set, instruction by instruction.
Procedure BoardFrame()
  Protected target.i, ran.i, c0.i = M51Cycles
  If BreakAt >= 0
    M51SetPins(1, (~PM51Buttons) & 255)
    PM51Frame + 1 : PM51Status = 1
    M51SetInt0(0) : M51SetInt0(1)
    target = PM51FrameCycles() - PM51Carry
    While ran < target
      ran + M51Run(1)
      If M51PC = BreakAt
        Running = 0 : Status$ = "Stopped at the breakpoint " + H4(BreakAt) + "h."
        Break
      EndIf
      If M51Stopped Or M51PowerDown : Break : EndIf
    Wend
    PM51Carry = ran - target
    If PM51Carry < 0 : PM51Carry = 0 : EndIf
  Else
    PM51RunFrame()
  EndIf
  BoardFrames + 1
  PM51AudioFrame()
  RateWindowCycles + (M51Cycles - c0)
EndProcedure

; Runs the board in real time (60 frames a second by the wall clock), or as
; fast as it goes for about budgetMs with Turbo; stops at the breakpoint, at the
; program's final jump-to-self, on $A5 or in power-down.
Procedure RunFor(budgetMs.i)
  Protected t0.q = ElapsedMilliseconds(), due.i, n.i
  If BoardClock = 0 : BoardClock = t0 - ((BoardFrames * 1000) / #PM51_FRAME_HZ) : EndIf
  While Running
    If Turbo
      If ElapsedMilliseconds() - t0 >= budgetMs : Break : EndIf
    Else
      due = ((ElapsedMilliseconds() - BoardClock) * #PM51_FRAME_HZ) / 1000
      If due - BoardFrames > 10        ; far behind (a breakpoint, a stall): carry on from now
        BoardClock = ElapsedMilliseconds() - ((BoardFrames * 1000) / #PM51_FRAME_HZ)
        due = BoardFrames + 1
      EndIf
      If BoardFrames >= due Or n >= 6 : Break : EndIf
    EndIf
    BoardFrame()
    n + 1
    If M51Stopped
      Running = 0 : Status$ = "Stopped: $A5 at " + H4(M51PC) + "h is not an instruction."
    ElseIf M51PowerDown
      Running = 0 : Status$ = "Power-down (PCON.1): only Reset continues."
    ElseIf AtSelfJump() And M51Idle = 0 And (M51Sfr($28) & $80) = 0
      Running = 0 : Status$ = "The program ended: a jump to itself at " + H4(M51PC) + "h."
    EndIf
  Wend
  DrainSerial()
EndProcedure

Procedure.i ColourOf332(v.i, part.i)
  Select part
    Case 0 : ProcedureReturn ((v >> 5) * 255) / 7
    Case 1 : ProcedureReturn (((v >> 2) & 7) * 255) / 7
  EndSelect
  ProcedureReturn ((v & 3) * 255) / 3
EndProcedure

; The board's picture into the screen texture (BGRA), line by line.
Procedure UpdateScreen()
  Protected y.i, x.i, v.i, *p
  If ScreenSpr\TextureID = 0
    *ScreenBuf = AllocateMemory(160 * 128 * 4)
    ScreenSpr\Width = 160 : ScreenSpr\Height = 128
    glGenTextures_(1, @ScreenSpr\TextureID)
    glBindTexture_(#GL_TEXTURE_2D, ScreenSpr\TextureID)
    glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MIN_FILTER, #GL_NEAREST)
    glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MAG_FILTER, #GL_NEAREST)
    glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_S, #GL_CLAMP_TO_EDGE)
    glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_T, #GL_CLAMP_TO_EDGE)
    glTexImage2D_(#GL_TEXTURE_2D, 0, #GL_RGBA, 160, 128, 0, #GL_BGRA_EXT, #GL_UNSIGNED_BYTE, *ScreenBuf)
  EndIf
  ; DrawGLSprite takes rows bottom-up (as from a DIB): line y goes to row 127 - y.
  For y = 0 To 127
    PM51ComposeLine(y)
    *p = *ScreenBuf + ((127 - y) * 640)
    For x = 0 To 159
      v = PM51Line(x)
      PokeL(*p, $FF000000 | (ColourOf332(v, 0) << 16) | (ColourOf332(v, 1) << 8) | ColourOf332(v, 2))
      *p + 4
    Next
  Next
  glBindTexture_(#GL_TEXTURE_2D, ScreenSpr\TextureID)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, 160, 128, #GL_BGRA_EXT, #GL_UNSIGNED_BYTE, *ScreenBuf)
EndProcedure

; Keyboard -> the board's buttons (P1, read active low by the program).
Procedure ReadButtons()
  Protected b.i
  If GetForegroundWindow_() <> WindowID(Win) Or Neon_FocusID <> 0
    PM51Buttons = 0
    ProcedureReturn
  EndIf
  If GetAsyncKeyState_(#VK_UP) & $8000 : b | 1 : EndIf
  If GetAsyncKeyState_(#VK_DOWN) & $8000 : b | 2 : EndIf
  If GetAsyncKeyState_(#VK_LEFT) & $8000 : b | 4 : EndIf
  If GetAsyncKeyState_(#VK_RIGHT) & $8000 : b | 8 : EndIf
  If GetAsyncKeyState_('Z') & $8000 : b | 16 : EndIf
  If GetAsyncKeyState_('X') & $8000 : b | 32 : EndIf
  If GetAsyncKeyState_(#VK_RETURN) & $8000 : b | 64 : EndIf
  If GetAsyncKeyState_(#VK_SPACE) & $8000 : b | 128 : EndIf
  PM51Buttons = b
EndProcedure

Procedure.s FlagString(p.i)
  Protected s.s, names.s = "CY AC F0 RS1RS0OV F1 P  ", i.i
  For i = 0 To 7
    If p & (128 >> i)
      s + Trim(Mid(names, i * 3 + 1, 3)) + " "
    Else
      s + LCase(Trim(Mid(names, i * 3 + 1, 3))) + " "
    EndIf
  Next
  ProcedureReturn s
EndProcedure

Procedure DrawLine(x.f, y.f, t.s, r.f = -1, g.f = 0, b.f = 0)
  If r < 0
    Neon_Text(*Neon_FontMono, x, y, t, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
  Else
    Neon_Text(*Neon_FontMono, x, y, t, r, g, b)
  EndIf
EndProcedure

Procedure DrawCpuPanel(x.f, y.f, w.f, h.f)
  Protected lh.f = Neon_S(18), yy.f, i.i, s.s, psw.i = M51Psw()
  Neon_Panel(x, y, w, h, "CPU", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  yy = y + Neon_S(34)
  DrawLine(x + Neon_S(10), yy, "PC   " + H4(M51PC) + "    A  " + H2(M51A) + "   B  " + H2(M51B)) : yy + lh
  DrawLine(x + Neon_S(10), yy, "SP   " + H2(M51SP) + "      DPTR " + H4(M51DPTR)) : yy + lh
  DrawLine(x + Neon_S(10), yy, "PSW  " + H2(psw) + "   bank " + Str((psw >> 3) & 3)) : yy + lh
  DrawLine(x + Neon_S(10), yy, FlagString(psw), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB) : yy + lh * 1.4
  For i = 0 To 7
    s + "R" + Str(i) + "=" + H2(M51IRam(M51RB + i)) + " "
    If i = 3
      DrawLine(x + Neon_S(10), yy, s) : yy + lh : s = ""
    EndIf
  Next
  DrawLine(x + Neon_S(10), yy, s) : yy + lh * 1.4
  DrawLine(x + Neon_S(10), yy, "cycles     " + Str(M51Cycles)) : yy + lh
  DrawLine(x + Neon_S(10), yy, "interrupts " + Str(M51IntCount) + "  level " + Str(M51IntActive)) : yy + lh
  s = "running"
  If Running = 0 : s = "stopped" : EndIf
  If M51Idle : s + ", idle" : EndIf
  DrawLine(x + Neon_S(10), yy, "state      " + s) : yy + lh * 1.4
  DrawLine(x + Neon_S(10), yy, "TCON " + H2(M51Sfr($08)) + " TMOD " + H2(M51Sfr($09)) + " IE " + H2(M51Sfr($28)) + " IP " + H2(M51Sfr($38))) : yy + lh
  DrawLine(x + Neon_S(10), yy, "T0 " + H2(M51Sfr($0C)) + H2(M51Sfr($0A)) + "  T1 " + H2(M51Sfr($0D)) + H2(M51Sfr($0B)) + "  T2 " + H2(M51Sfr($4D)) + H2(M51Sfr($4C))) : yy + lh
  DrawLine(x + Neon_S(10), yy, "T2CON " + H2(M51Sfr($48)) + " RCAP2 " + H2(M51Sfr($4B)) + H2(M51Sfr($4A))) : yy + lh
  DrawLine(x + Neon_S(10), yy, "SCON " + H2(M51Sfr($18)) + " SBUF " + H2(M51SbufRx) + " PCON " + H2(M51Sfr($07))) : yy + lh
  DrawLine(x + Neon_S(10), yy, "P0 " + H2(M51Sfr($00)) + " P1 " + H2(M51Sfr($10)) + " P2 " + H2(M51Sfr($20)) + " P3 " + H2(M51Sfr($30)))
EndProcedure

Procedure DrawDisasm(x.f, y.f, w.f, h.f)
  Protected lh.f = Neon_S(18), rows.i, i.i, adr.i, n.i, t.s, yy.f, k.i, found.i, bytes.s
  Neon_Panel(x, y, w, h, "Disassembly  (click a line for a breakpoint)", Neon_C_VioR, Neon_C_VioG, Neon_C_VioB)
  rows = Int((h - Neon_S(40)) / lh)
  ; Keep the PC on screen: re-anchor when it leaves the listed range.
  adr = DisTop
  For i = 0 To rows - 3
    If adr = M51PC : found = 1 : Break : EndIf
    M51Disasm(adr, @n) : adr = (adr + n) & $FFFF
  Next
  If found = 0 : DisTop = M51PC : EndIf
  adr = DisTop
  yy = y + Neon_S(32)
  For i = 0 To rows - 1
    t = M51Disasm(adr, @n)
    If adr = M51PC
      Neon_Box(x + Neon_S(4), yy - Neon_S(2), w - Neon_S(8), lh, Neon_C_AccR, Neon_C_AccG, Neon_C_AccB, 0.18)
    EndIf
    If adr = BreakAt
      Neon_Box(x + Neon_S(6), yy + Neon_S(3), Neon_S(8), Neon_S(8), Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    EndIf
    If Neon_MouseClicked And Neon_Hit(x, yy - Neon_S(2), w, lh)
      If BreakAt = adr : BreakAt = -1 : BreakText\s = "" : Else : BreakAt = adr : BreakText\s = H4(adr) : EndIf
    EndIf
    bytes = ""
    For k = 0 To n - 1
      bytes + H2(M51Code((adr + k) & $FFFF)) + " "
    Next
    DrawLine(x + Neon_S(20), yy, H4(adr) + "  " + LSet(bytes, 10) + t, -1)
    yy + lh
    adr = (adr + n) & $FFFF
  Next
EndProcedure

Procedure DrawMemory(x.f, y.f, w.f, h.f)
  Protected lh.f = Neon_S(18), rows.i, total.i, r.i, c.i, a.i, s.s, yy.f, base.i
  Protected sc.f, bx.f, by.f, bw.f, bh.f, bv.i
  Neon_Panel(x, y, w, h, "PM51 board and memory", Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
  MemTab = Neon_TabStrip(101, x + Neon_S(2), y + Neon_S(28), w - Neon_S(4), Neon_S(26), "Screen|Internal RAM|SFR|XDATA|Code", MemTab)
  If MemTab = 0
    UpdateScreen()
    sc = (w - Neon_S(40)) / 160.0
    If (h - Neon_S(110)) / 128.0 < sc : sc = (h - Neon_S(110)) / 128.0 : EndIf
    sc = Int(sc)
    If sc < 1 : sc = 1 : EndIf
    bw = 160 * sc : bh = 128 * sc
    bx = x + (w - bw) / 2 : by = y + Neon_S(70)
    bv = M51XData($F004)
    Neon_Box(bx - Neon_S(12), by - Neon_S(12), bw + Neon_S(24), bh + Neon_S(24), ColourOf332(bv, 0) / 255.0, ColourOf332(bv, 1) / 255.0, ColourOf332(bv, 2) / 255.0)
    DrawGLSprite(@ScreenSpr, bx, by, 0, sc, 1, 1, 1, 1, #True, -1, -1, -1, -1, #True)
    DrawLine(x + Neon_S(12), by + bh + Neon_S(22), "frame " + Str(PM51Frame) + "   buttons " + RSet(Bin(PM51Buttons), 8, "0") + "   keys: arrows, Z = A, X = B, Enter = start, Space = select", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
    ProcedureReturn
  EndIf
  rows = Int((h - Neon_S(70)) / lh)
  Select MemTab
    Case 1 : total = 16
    Case 2 : total = 8
    Default : total = 4096
  EndSelect
  If Neon_Hit(x, y, w, h) And Wheel : MemTop - Wheel * 3 : EndIf
  Neon_ScrollBarV(102, x + w - Neon_S(14), y + Neon_S(58), Neon_S(12), h - Neon_S(62), total, rows, @MemTop)
  If MemTop > total - rows : MemTop = total - rows : EndIf
  If MemTop < 0 : MemTop = 0 : EndIf
  yy = y + Neon_S(62)
  For r = MemTop To MemTop + rows - 1
    If r >= total : Break : EndIf
    base = r * 16
    If MemTab = 2 : base + $80 : EndIf
    s = H4(base) + "  "
    For c = 0 To 15
      a = base + c
      Select MemTab
        Case 1 : s + H2(M51IRam(a)) + " "
        Case 2 : s + H2(M51Sfr(a & $7F)) + " "
        Case 3 : s + H2(M51XData(a)) + " "
        Default : s + H2(M51Code(a)) + " "
      EndSelect
    Next
    DrawLine(x + Neon_S(10), yy, s)
    yy + lh
  Next
EndProcedure

Procedure DrawLog(x.f, y.f, w.f, h.f)
  Protected lh.f = Neon_S(17), rows.i, n.i, i.i, t.s, yy.f, line.s
  Neon_Panel(x, y, w, h, "Output", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  LogTab = Neon_TabStrip(201, x + Neon_S(2), y + Neon_S(28), w - Neon_S(4), Neon_S(26), "Test results|Serial port output", LogTab)
  If LogTab = 0 : t = M51TestLog$ : Else : t = SerialLog$ : EndIf
  If t = "" : t = "(nothing yet)" : EndIf
  n = CountString(t, #LF$) + 1
  rows = Int((h - Neon_S(66)) / lh)
  If Neon_Hit(x, y, w, h) And Wheel : LogTop - Wheel * 3 : EndIf
  Neon_ScrollBarV(202, x + w - Neon_S(14), y + Neon_S(58), Neon_S(12), h - Neon_S(62), n, rows, @LogTop)
  If LogTop > n - rows : LogTop = n - rows : EndIf
  If LogTop < 0 : LogTop = 0 : EndIf
  yy = y + Neon_S(60)
  For i = LogTop To LogTop + rows - 1
    If i >= n : Break : EndIf
    line = StringField(t, i + 1, #LF$)
    If FindString(line, "FAIL")
      DrawLine(x + Neon_S(10), yy, line, Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    ElseIf FindString(line, "PASS")
      DrawLine(x + Neon_S(10), yy, line, Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    Else
      DrawLine(x + Neon_S(10), yy, line)
    EndIf
    yy + lh
  Next
EndProcedure

Procedure RunTestsInWindow()
  Protected keep.i, saveCode.i
  Running = 0
  ; The suites load their own programs into the core; keep the user's.
  saveCode = AllocateMemory(65536)
  CopyMemory(@M51Code(0), saveCode, 65536)
  PM51Enabled = 0
  TestsFailed = M51RunAllTests()
  PM51Enabled = 1
  TestsRun = 1
  CopyMemory(saveCode, @M51Code(0), 65536)
  FreeMemory(saveCode)
  PM51Reset()
  LogTab = 0 : LogTop = 0
  If TestsFailed = 0
    Status$ = "All test suites passed on the desktop core (the same suites as the board)."
  Else
    Status$ = Str(TestsFailed) + " test suite(s) FAILED - see Test results."
  EndIf
EndProcedure

Procedure DrawToolbar(w.f)
  Protected x.f = Neon_S(10), y.f = Neon_S(8), bh.f = Neon_S(30), f.s, label.s, r.f, k.i
  Neon_Box(0, 0, w, Neon_S(46), Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  If Neon_Button(x, y, Neon_S(86), bh, "Open...")
    f = OpenFileRequester("Load an 8051 program", "", "Intel HEX (*.hex;*.ihx)|*.hex;*.ihx|Binary (*.bin)|*.bin|All files (*.*)|*.*", 0)
    If f <> ""
      Running = 0
      If LoadProgram(f) : Status$ = "Loaded " + LoadedName$ + " (" + Str(LoadedTop) + " bytes)." : DisTop = 0
      Else : Status$ = "Could not read " + f : EndIf
    EndIf
  EndIf
  x + Neon_S(94)
  If Neon_Button(x, y, Neon_S(70), bh, "Reset")
    Running = 0 : PM51Reset() : SerialLog$ = "" : Status$ = "Reset." : BoardFrames = 0
  EndIf
  x + Neon_S(78)
  label = "Run"
  If Running : label = "Stop" : EndIf
  If Neon_Button(x, y, Neon_S(70), bh, label, Running)
    Running = Bool(Running = 0)
    If Running
      If M51Stopped Or M51PowerDown : Running = 0 : Status$ = "Reset first." : EndIf
      ; From a breakpoint, step off it first.
      If Running And M51PC = BreakAt : StepOne() : EndIf
      If Running : Status$ = "Running." : EndIf
    Else
      Status$ = "Stopped at " + H4(M51PC) + "h."
    EndIf
  EndIf
  x + Neon_S(78)
  If Neon_Button(x, y, Neon_S(70), bh, "Step", #False, Bool(Running = 0))
    StepOne() : Status$ = "Stepped to " + H4(M51PC) + "h."
  EndIf
  x + Neon_S(78)
  If Neon_Button(x, y, Neon_S(90), bh, "Step 100", #False, Bool(Running = 0))
    For k = 1 To 100
      StepOne()
      If M51PC = BreakAt Or M51Stopped : Break : EndIf
    Next
    Status$ = "Stepped to " + H4(M51PC) + "h."
  EndIf
  x + Neon_S(98)
  Neon_Text(*Neon_FontUI, x, y + Neon_S(6), "Break at", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  x + Neon_S(64)
  If Neon_TextInput(301, x, y, Neon_S(80), bh, @BreakText, "hex", @BreakCaret)
    If Trim(BreakText\s) = ""
      BreakAt = -1
    Else
      BreakAt = Val("$" + Trim(BreakText\s)) & $FFFF
    EndIf
  EndIf
  x + Neon_S(88)
  If Neon_Button(x, y, Neon_S(110), bh, "Run tests", Bool(TestsRun And TestsFailed = 0))
    RunTestsInWindow()
  EndIf
  x + Neon_S(118)
  If Neon_Button(x, y, Neon_S(80), bh, "Turbo", Turbo)
    Turbo = Bool(Turbo = 0) : BoardClock = 0
  EndIf
  r = RateShown / 1000000.0
  Neon_TextRight(*Neon_FontUI, w - Neon_S(12), y + Neon_S(6), StrF(r, 1) + " M machine cycles/s  =  " + StrF(r, 0) + "x a 12 MHz 8051",
                 Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
EndProcedure

; The window's own back buffer, read before the flip, written as a PNG.
Procedure SaveShot(pw.i, ph.i)
  Protected *px = AllocateMemory(pw * ph * 4), img.i, x.i, y.i, c.l
  glReadPixels_(0, 0, pw, ph, #GL_RGBA, #GL_UNSIGNED_BYTE, *px)
  img = CreateImage(#PB_Any, pw, ph, 24)
  If img And StartDrawing(ImageOutput(img))
    For y = 0 To ph - 1
      For x = 0 To pw - 1
        c = PeekL(*px + ((ph - 1 - y) * pw + x) * 4)
        Plot(x, y, RGB(c & 255, (c >> 8) & 255, (c >> 16) & 255))
      Next
    Next
    StopDrawing()
    SaveImage(img, ShotPath$, #PB_ImagePlugin_PNG)
  EndIf
  FreeMemory(*px)
  ShotPath$ = ""
  ShotFrames = -1
EndProcedure

Procedure Frame()
  Protected r.RECT, pw.i, ph.i, cw.i, ch.i, mx.i, my.i, down.b, w.f, h.f, colW.f, top.f, logH.f, now.q
  SetGadgetAttribute(Gl, #PB_OpenGL_SetContext, #True)
  cw = GadgetWidth(Gl) : ch = GadgetHeight(Gl)
  GetClientRect_(WindowID(Win), @r)
  pw = r\right - r\left : ph = r\bottom - r\top
  If pw < 1 Or ph < 1 : ProcedureReturn : EndIf
  Util_BaseWidth = pw : Util_BaseHeight = ph
  ; Util_Win* must be the size that DesktopScaledX/Y() turns back into the
  ; PHYSICAL drawable (Neon_PhysWinHeight flips scissor rectangles with it).
  ; GadgetWidth() is not that here: DesktopResolutionX() reports 1.0 under
  ; per-monitor awareness, so the gadget's logical size came out 1.25x short
  ; and every tab strip lost its tabs inside an off-screen scissor.
  Util_WinWidth = Round(pw / DesktopResolutionX(), #PB_Round_Nearest)
  Util_WinHeight = Round(ph / DesktopResolutionY(), #PB_Round_Nearest)
  GL_ViewportX = 0 : GL_ViewportY = 0 : GL_ViewportW = pw : GL_ViewportH = ph
  mx = WindowMouseX(Win) : my = WindowMouseY(Win)
  down = Bool(GetAsyncKeyState_(#VK_LBUTTON) & $8000)
  Neon_ChromeBeginFrame(mx, my, down, Wheel, KeyCode, KeyChar, 1.0 / 60.0)
  Wheel = 0 : KeyCode = 0 : KeyChar = 0
  glBindFramebuffer(#GL_FRAMEBUFFER, 0)
  glDisable_(#GL_SCISSOR_TEST)
  glViewport_(0, 0, pw, ph)
  glClearColor_(Neon_C_BgR, Neon_C_BgG, Neon_C_BgB, 1.0)
  glClear_(#GL_COLOR_BUFFER_BIT)

  ReadButtons()
  If Running : RunFor(12) : Else : BoardClock = 0 : EndIf
  now = ElapsedMilliseconds()
  If now - RateWindowStart >= 500
    RateShown = RateWindowCycles * 1000.0 / (now - RateWindowStart)
    RateWindowCycles = 0 : RateWindowStart = now
  EndIf

  w = pw : h = ph
  top = Neon_S(52)
  logH = Neon_S(230)
  colW = Neon_S(330)
  DrawToolbar(w)
  DrawCpuPanel(Neon_S(8), top, colW, h - top - logH - Neon_S(40))
  DrawDisasm(colW + Neon_S(16), top, Neon_S(470), h - top - logH - Neon_S(40))
  DrawMemory(colW + Neon_S(494), top, w - colW - Neon_S(502), h - top - logH - Neon_S(40))
  DrawLog(Neon_S(8), h - logH - Neon_S(32), w - Neon_S(16), logH)
  Neon_Box(0, h - Neon_S(26), w, Neon_S(26), Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  Neon_Text(*Neon_FontSmall, Neon_S(10), h - Neon_S(21), "Program: " + LoadedName$ + "     " + Status$, Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  Neon_ChromeEndFrame()
  If ShotPath$ <> ""
    ShotFrames + 1
    If ShotFrames = ShotAfter
      SaveShot(pw, ph)
    EndIf
  EndIf
  SetGadgetAttribute(Gl, #PB_OpenGL_FlipBuffers, #True)
EndProcedure

Procedure.f DisplayScale()
  Protected lib.i, fn.i, dpi.i
  lib = OpenLibrary(#PB_Any, "user32.dll")
  If lib
    fn = GetFunction(lib, "GetDpiForWindow")
    If fn And Win : dpi = CallFunctionFast(fn, WindowID(Win)) : EndIf
    CloseLibrary(lib)
  EndIf
  If dpi <= 0 : ProcedureReturn 1.0 : EndIf
  ProcedureReturn dpi / 96.0
EndProcedure

Procedure WindowMain()
  Protected lib.i, fn.i, ev.i, s.f, w.i = 1440, h.i = 900, quit.i, et.i
  lib = OpenLibrary(#PB_Any, "user32.dll")
  If lib
    fn = GetFunction(lib, "SetProcessDpiAwarenessContext")
    If fn : CallFunctionFast(fn, -4) : EndIf
    CloseLibrary(lib)
  EndIf
  ExamineDesktops()
  If w > DesktopWidth(0) - 40 : w = DesktopWidth(0) - 40 : EndIf
  If h > DesktopHeight(0) - 80 : h = DesktopHeight(0) - 80 : EndIf
  Gl = OpenGLWindow("8051 emulator - PureBasic, Neon Arcade", w, h,
                    #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget)
  Win = Util_MainWindowID
  s = DisplayScale()
  Neon_UIScale = s
  *Neon_FontUI = Neon_CreateFontPx("Segoe UI", Round(14 * s, #PB_Round_Nearest))
  *Neon_FontSmall = Neon_CreateFontPx("Segoe UI", Round(12 * s, #PB_Round_Nearest))
  *Neon_FontBold = Neon_CreateFontPx("Segoe UI", Round(15 * s, #PB_Round_Nearest), #PB_Font_Bold)
  *Neon_FontMono = Neon_CreateFontPx("Consolas", Round(14 * s, #PB_Round_Nearest))
  GLFontSetSnapToPixel(*Neon_FontUI, #True)
  GLFontSetSnapToPixel(*Neon_FontSmall, #True)
  GLFontSetSnapToPixel(*Neon_FontBold, #True)
  GLFontSetSnapToPixel(*Neon_FontMono, #True)
  RateWindowStart = ElapsedMilliseconds()
  PM51AudioOpen()
  Repeat
    Repeat
      ev = WindowEvent()
      If ev = #PB_Event_CloseWindow : quit = 1 : EndIf
      If ev = #PB_Event_Gadget And EventGadget() = Gl
        et = EventType()
        If et = #PB_EventType_MouseWheel
          Wheel + GetGadgetAttribute(Gl, #PB_OpenGL_WheelDelta)
        ElseIf et = #PB_EventType_KeyDown
          KeyCode = GetGadgetAttribute(Gl, #PB_OpenGL_Key)
        ElseIf et = #PB_EventType_Input
          KeyChar = GetGadgetAttribute(Gl, #PB_OpenGL_Input)
        EndIf
      EndIf
    Until ev = 0
    Frame()
    If ShotFrames < 0 : quit = 1 : EndIf
    If Running = 0 : Delay(10) : EndIf
  Until quit
  PM51AudioClose()
EndProcedure

UsePNGImageEncoder()
M51DisInit()
PM51Reset()
Define rc.i = ConsoleMain()
If rc >= 0
  End rc
EndIf
Define argi.i, arg$, showTests.i, startRun.i
For argi = 0 To CountProgramParameters() - 1
  arg$ = ProgramParameter(argi)
  If LCase(arg$) = "--show-tests"
    showTests = 1
  ElseIf LCase(arg$) = "--run"
    startRun = 1
  ElseIf LCase(arg$) = "--screenshot"
    argi + 1
    ShotPath$ = ProgramParameter(argi)
  ElseIf LCase(arg$) = "--shot-after"
    argi + 1
    ShotAfter = Val(ProgramParameter(argi))
  ElseIf LoadProgram(arg$)
    Status$ = "Loaded " + LoadedName$ + " (" + Str(LoadedTop) + " bytes)."
  EndIf
Next
If showTests : RunTestsInWindow() : EndIf
If startRun
  Running = 1
  If showTests = 0 : LogTab = 1 : EndIf
EndIf
WindowMain()
