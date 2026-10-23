; The board's verification, run on the desktop core: the SAME test code
; (tests/verify_body.pico, valid PureBasic as well as PureMetal) and the same
; embedded test data. These are the helpers the board gets from io.pico and
; its libraries, written for the PC: the report goes to the console when one
; is open, and always into M51TestLog$ for the window.
Global M51TestLog$, M51TestConsole.i, M51TestTimerFreq.q

Procedure Say(t.s)
  M51TestLog$ + t
  If M51TestConsole
    Print(t)
  EndIf
EndProcedure
Procedure SayAt(p.i)
  Say(PeekS(p, -1, #PB_Ascii))
EndProcedure
Procedure Num(v.i)
  Say(Str(v))
EndProcedure
Procedure Hex2(v.i)
  Say(RSet(Hex(v & 255), 2, "0"))
EndProcedure
Procedure Eol()
  Say(#LF$)
EndProcedure
Procedure.i Micros()
  Protected now.q
  If M51TestTimerFreq = 0
    QueryPerformanceFrequency_(@M51TestTimerFreq)
  EndIf
  QueryPerformanceCounter_(@now)
  ProcedureReturn now * 1000000 / M51TestTimerFreq
EndProcedure
Procedure UsbSerialTask()
EndProcedure
Procedure SafetyPet()
EndProcedure
Procedure.i Rate(count.i, us.i)
  If us <= 0
    ProcedureReturn 0
  EndIf
  ProcedureReturn count * 1000000 / us
EndProcedure

XIncludeFile "../tests/test_counts.pico"
XIncludeFile "../tests/program_data.pico"
XIncludeFile "../tests/test_data.pico"
XIncludeFile "../tests/verify_body.pico"

; Runs every suite; returns the number that failed.
Procedure.i M51RunAllTests()
  Protected failed.i
  M51TestLog$ = ""
  Say("8051 verification on the desktop core")
  CompilerIf #M51_TIMING = 1
    Say(" timed")
  CompilerElse
    Say(" untimed")
  CompilerEndIf
  Say(" vectors=") : Num(#VECTOR_COUNT) : Eol()
  ApiTests()
  If ApiFailures : failed + 1 : EndIf
  VectorTests()
  If Failures : failed + 1 : EndIf
  ProgramTests()
  If PBad : failed + 1 : EndIf
  AsmTests()
  If PBad : failed + 1 : EndIf
  Say("verification complete, suites failed=") : Num(failed) : Eol()
  ProcedureReturn failed
EndProcedure
