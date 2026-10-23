; Timers counting machine cycles. Timer 0 mode 2 (auto-reload) and timer 2
; (16-bit auto-reload) interrupt and count their overflows; timer 1 mode 1
; runs freely. Then timer 0 mode 0 (13 bits) and mode 3 (two 8-bit halves).
        .area   CSEG    (ABS,CODE)
        .org    0x0000
        ljmp    main
        .org    0x000B
        inc     0x52            ; timer 0 overflows
        reti
        .org    0x001B
        inc     0x55            ; TH0 overflows in mode 3 (TF1)
        reti
        .org    0x002B
        clr     0xCF            ; TF2
        inc     0x53
        reti
        .org    0x0040
main:   mov     0x81,#0x60
        mov     0x52,#0
        mov     0x53,#0
        mov     0x55,#0
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
        mov     r7,#40
w1:     mov     r6,#100
w2:     nop                     ; (a loop that is not a jump to itself)
        djnz    r6,w2
        djnz    r7,w1
        mov     0x88,#0         ; stop timers 0 and 1
        mov     0xC8,#0         ; stop timer 2
        mov     0x40,0x8A       ; TL0
        mov     0x41,0x8B       ; TL1
        mov     0x42,0x8D       ; TH1
        mov     0x43,0xCC       ; TL2
        mov     0x44,0xCD       ; TH2
        ; Mode 0: 13 bits, no interrupt.
        clr     0xA9            ; ET0
        mov     0x89,#0x00
        mov     0x8A,#0x1C
        mov     0x8C,#0xF0
        setb    0x8C            ; TR0
        mov     r6,#200
w3:     nop                     ; (a loop that is not a jump to itself)
        djnz    r6,w3
        clr     0x8C
        mov     0x45,0x8A
        mov     0x46,0x8C
        mov     0x47,0x88       ; TCON: TF0 must be set by the 13-bit overflow
        ; Mode 3: TL0 run by TR0, TH0 by TR1 into TF1.
        mov     0x88,#0
        mov     0x89,#0x03
        mov     0x8A,#0
        mov     0x8C,#0x80
        setb    0xAB            ; ET1
        mov     0x88,#0x50      ; TR1 TR0
        mov     r6,#250
w4:     nop                     ; (a loop that is not a jump to itself)
        djnz    r6,w4
        mov     0x88,#0
        mov     0x48,0x8A
        mov     0x49,0x8C
        clr     0xAF
        sjmp    .
