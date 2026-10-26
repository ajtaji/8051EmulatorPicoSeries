; The controls: every key the window answers to, in ONE table. ReadButtons (the
; PM51 board's buttons), the window's shortcut handler, the Controls tab and the
; key hint under the screen all read it, so what the window shows is what the
; input code does. Include after the engine.

; The window's own shortcuts (CtlKeys entries with bit 0; action = the code).
#CTL_FULLSCREEN = 1
#CTL_LEAVEFULL = 2

Structure CtlBinding
  bit.i         ; the PM51 button's bit in BUTTONS / P1 (1 up ... 128 select), 0 for a shortcut
  action.i      ; for a shortcut: #CTL_*
  key.i         ; the Windows virtual-key code (also PureBasic's #PB_Shortcut_* value)
  name$         ; the key as the window shows it
EndStructure
Global NewList CtlKeys.CtlBinding()
Global Dim CtlButtonName$(7)

Procedure CtlInit()
  Protected b.i, a.i, k.i, n$
  ClearList(CtlKeys())
  Restore CtlButtonNames
  For b = 0 To 7 : Read.s n$ : CtlButtonName$(b) = n$ : Next
  Restore CtlKeyTable
  Repeat
    Read.i b : If b < 0 : Break : EndIf
    Read.i a : Read.i k : Read.s n$
    AddElement(CtlKeys()) : CtlKeys()\bit = b : CtlKeys()\action = a : CtlKeys()\key = k : CtlKeys()\name$ = n$
  ForEver
EndProcedure

; The PM51 buttons the keyboard holds now (1 = pressed, BUTTONS' bit order).
Procedure.i CtlButtonsHeld()
  Protected m.i
  ForEach CtlKeys()
    If CtlKeys()\bit And (GetAsyncKeyState_(CtlKeys()\key) & $8000)
      m | CtlKeys()\bit
    EndIf
  Next
  ProcedureReturn m
EndProcedure

; The window action a key starts (0: none).
Procedure.i CtlAction(key.i)
  ForEach CtlKeys()
    If CtlKeys()\bit = 0 And CtlKeys()\key = key : ProcedureReturn CtlKeys()\action : EndIf
  Next
  ProcedureReturn 0
EndProcedure

; The keys bound to a PM51 button, or to a window action.
Procedure.s CtlKeyNames(bit.i, action.i = 0)
  Protected t$
  ForEach CtlKeys()
    If CtlKeys()\bit = bit And (bit Or CtlKeys()\action = action)
      If t$ <> "" : t$ + " / " : EndIf
      t$ + CtlKeys()\name$
    EndIf
  Next
  ProcedureReturn t$
EndProcedure

; One short line for under the screen: "arrows, Z = A, X = B, ...". The four
; directions are written "arrows" when each is bound to its own arrow key.
Procedure.s CtlSummary()
  Protected b.i, t$, first.i = 0
  If CtlKeyNames(1) = "Up arrow" And CtlKeyNames(2) = "Down arrow" And CtlKeyNames(4) = "Left arrow" And CtlKeyNames(8) = "Right arrow"
    t$ = "arrows" : first = 4
  EndIf
  For b = first To 7
    If t$ <> "" : t$ + ", " : EndIf
    t$ + CtlKeyNames(1 << b) + " = " + CtlButtonName$(b)
  Next
  ProcedureReturn t$
EndProcedure

DataSection
  CtlButtonNames:
  Data.s "up", "down", "left", "right", "A", "B", "start", "select"
  ; bit, action, key, name - the PM51 buttons, then the window's shortcuts
  CtlKeyTable:
  Data.i 1, 0, #VK_UP : Data.s "Up arrow"
  Data.i 2, 0, #VK_DOWN : Data.s "Down arrow"
  Data.i 4, 0, #VK_LEFT : Data.s "Left arrow"
  Data.i 8, 0, #VK_RIGHT : Data.s "Right arrow"
  Data.i 16, 0, 'Z' : Data.s "Z"
  Data.i 32, 0, 'X' : Data.s "X"
  Data.i 64, 0, #VK_RETURN : Data.s "Enter"
  Data.i 128, 0, #VK_SPACE : Data.s "Space"
  Data.i 0, #CTL_FULLSCREEN, #VK_F11 : Data.s "F11"
  Data.i 0, #CTL_LEAVEFULL, #VK_ESCAPE : Data.s "Esc"
  Data.i -1
EndDataSection
