; The PM51 board's sound on Windows: 44,100 Hz, 16-bit mono through waveOut,
; one buffer per 60 Hz frame (735 samples), eight buffers in a ring. A frame's
; samples are mixed by PM51Mix() when the frame has run; a buffer the device
; has not finished with is skipped (the frame is dropped) rather than waited for.

#PM51_AUDIO_RATE = 44100
#PM51_AUDIO_FRAME = 735
#PM51_AUDIO_BUFFERS = 8

Global PM51AudioDev.i, PM51AudioNext.i, PM51AudioDropped.i, PM51AudioOn.i
Global Dim PM51AudioHdr.WAVEHDR(#PM51_AUDIO_BUFFERS)
Global *PM51AudioMem

Procedure PM51AudioOpen()
  Protected fmt.WAVEFORMATEX, i.i
  fmt\wFormatTag = #WAVE_FORMAT_PCM
  fmt\nChannels = 1
  fmt\nSamplesPerSec = #PM51_AUDIO_RATE
  fmt\wBitsPerSample = 16
  fmt\nBlockAlign = 2
  fmt\nAvgBytesPerSec = #PM51_AUDIO_RATE * 2
  If waveOutOpen_(@PM51AudioDev, #WAVE_MAPPER, @fmt, 0, 0, #CALLBACK_NULL) <> #MMSYSERR_NOERROR
    PM51AudioDev = 0
    ProcedureReturn
  EndIf
  *PM51AudioMem = AllocateMemory(#PM51_AUDIO_FRAME * 2 * #PM51_AUDIO_BUFFERS)
  For i = 0 To #PM51_AUDIO_BUFFERS - 1
    PM51AudioHdr(i)\lpData = *PM51AudioMem + (i * #PM51_AUDIO_FRAME * 2)
    PM51AudioHdr(i)\dwBufferLength = #PM51_AUDIO_FRAME * 2
    PM51AudioHdr(i)\dwFlags = 0
    waveOutPrepareHeader_(PM51AudioDev, @PM51AudioHdr(i), SizeOf(WAVEHDR))
    PM51AudioHdr(i)\dwFlags = PM51AudioHdr(i)\dwFlags | #WHDR_DONE
  Next
  PM51AudioOn = 1
EndProcedure

; After each emulated frame: that frame's sound.
Procedure PM51AudioFrame()
  Protected *h.WAVEHDR
  If PM51AudioDev = 0 Or PM51AudioOn = 0
    ProcedureReturn
  EndIf
  *h = @PM51AudioHdr(PM51AudioNext)
  If (*h\dwFlags & #WHDR_DONE) = 0
    PM51AudioDropped + 1
    ProcedureReturn
  EndIf
  PM51Mix(*h\lpData, #PM51_AUDIO_FRAME, #PM51_AUDIO_RATE)
  *h\dwFlags = *h\dwFlags & ~#WHDR_DONE
  waveOutWrite_(PM51AudioDev, *h, SizeOf(WAVEHDR))
  PM51AudioNext = (PM51AudioNext + 1) % #PM51_AUDIO_BUFFERS
EndProcedure

Procedure PM51AudioClose()
  Protected i.i
  If PM51AudioDev
    waveOutReset_(PM51AudioDev)
    For i = 0 To #PM51_AUDIO_BUFFERS - 1
      waveOutUnprepareHeader_(PM51AudioDev, @PM51AudioHdr(i), SizeOf(WAVEHDR))
    Next
    waveOutClose_(PM51AudioDev)
    PM51AudioDev = 0
  EndIf
EndProcedure
