; Timers counting machine cycles.
; Part A, with interrupts: timer 0 mode 2 (period 200) and timer 2 16-bit
; auto-reload (period 1000) count their overflows in interrupt routines while
; the main loop waits for free-running timer 1 to reach $4E00 cycles. Both
; counts sit well away from an overflow boundary (19968 = 99*200 + 168 =
; 19*1000 + 968, a margin of 32 cycles), so they do not depend on how long the
; interrupt entry or the wait loop takes.
; Part B, polled, no interrupts: exact register values of timer 0 in mode 0
; (13 bits) and mode 3 (two 8-bit halves), and timer 1 mode 2 reloading.
        .area   CSEG    (ABS,CODE)
        .org    0x0000
        ljmp    main
        .org    0x000B
        inc     0x52            ; timer 0 overflows
        reti
        .org    0x002B
        clr     0xCF            ; TF2
        inc     0x53
        reti
        .org    0x0040
main:   mov     0x81,#0x60
        mov     0x52,#0
        mov     0x53,#0
        ; ---- Part A
        mov     0x89,#0x12      ; TMOD: timer 1 mode 1, timer 0 mode 2
        mov     0x8C,#0x38      ; TH0 = 256-200
        mov     0x8A,#0x38
        mov     0x8B,#0
        mov     0x8D,#0
        mov     0xCA,#0x18      ; RCAP2 = 65536-1000
        mov     0xCB,#0xFC
        mov     0xCC,#0x18
        mov     0xCD,#0xFC
        mov     0xA8,#0xA2      ; EA ET2 ET0
        mov     0xC8,#0x04      ; TR2
        mov     0x88,#0x50      ; TR1 TR0
wa:     mov     a,0x8D          ; TH1
        cjne    a,#0x4E,wa
        mov     0x88,#0         ; stop timers 0 and 1
        mov     0xC8,#0         ; stop timer 2
        clr     0xAF            ; EA off for part B
        ; ---- Part B: timer 0 mode 0, 13 bits, from $1E1C for 600 cycles
        mov     0x89,#0x00
        mov     0x8A,#0x1C
        mov     0x8C,#0xF0
        mov     r6,#200
        setb    0x8C            ; TR0
w3:     nop                     ; 3 cycles a pass (a loop that is not a jump to itself)
        djnz    r6,w3
        clr     0x8C
        mov     0x45,0x8A
        mov     0x46,0x8C
        mov     0x47,0x88       ; TCON: TF0 set by the 13-bit overflow
        ; Timer 0 mode 3: TL0 run by TR0, TH0 by TR1 into TF1.
        mov     0x88,#0
        mov     0x89,#0x03
        mov     0x8A,#0
        mov     0x8C,#0x80
        mov     r6,#250
        mov     0x88,#0x50      ; TR1 TR0
w4:     nop
        djnz    r6,w4
        mov     0x88,#0x00
        mov     0x48,0x8A
        mov     0x49,0x8C
        ; Timer 1 mode 2 (auto-reload from TH1 = $F0): count TF1 by polling.
        mov     0x89,#0x20
        mov     0x8D,#0xF0
        mov     0x8B,#0xF0
        mov     0x54,#0
        mov     r6,#100
        setb    0x8E            ; TR1
w5:     jbc     0x8F,hit        ; TF1
        sjmp    nx
hit:    inc     0x54
nx:     djnz    r6,w5
        clr     0x8E
        mov     0x4A,0x8B       ; TL1
        mov     0x4B,0x88       ; TCON
        sjmp    .
