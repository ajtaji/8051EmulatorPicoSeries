; The PM51 board's sound: 44,100 Hz, 16-bit, through the engine's sound out
; (GL_AudioOpen / Next / Play: waveOut on Windows, ALSA on Linux), one buffer
; per 60 Hz frame (735 samples), eight buffers. A frame's samples are mixed by
; PM51Mix() (mono) when the frame has run and go out as stereo pairs; with no
; buffer free the frame is dropped rather than waited for.

#PM51_AUDIO_RATE = 44100
#PM51_AUDIO_FRAME = 735
#PM51_AUDIO_BUFFERS = 8

Global PM51AudioDropped.i, PM51AudioOn.i
Global *PM51AudioMono

Procedure PM51AudioOpen()
  If GL_AudioOpen(#PM51_AUDIO_RATE, #PM51_AUDIO_FRAME, #PM51_AUDIO_BUFFERS) = #False
    ProcedureReturn
  EndIf
  *PM51AudioMono = AllocateMemory(#PM51_AUDIO_FRAME * 2)
  PM51AudioOn = 1
EndProcedure

; After each emulated frame: that frame's sound.
Procedure PM51AudioFrame()
  Protected *dst, i.i, v.w
  If PM51AudioOn = 0
    ProcedureReturn
  EndIf
  *dst = GL_AudioNext()
  If *dst = 0
    PM51AudioDropped + 1
    ProcedureReturn
  EndIf
  PM51Mix(*PM51AudioMono, #PM51_AUDIO_FRAME, #PM51_AUDIO_RATE)
  For i = 0 To #PM51_AUDIO_FRAME - 1
    v = PeekW(*PM51AudioMono + i * 2)
    PokeW(*dst + i * 4, v) : PokeW(*dst + i * 4 + 2, v)
  Next
  GL_AudioPlay(*dst)
EndProcedure

Procedure PM51AudioClose()
  If PM51AudioOn
    GL_AudioClose()
    PM51AudioOn = 0
  EndIf
  If *PM51AudioMono : FreeMemory(*PM51AudioMono) : *PM51AudioMono = 0 : EndIf
EndProcedure
