; Two priority levels. INT0 (low) raises TF1 (high), which preempts it;
; TF1's routine raises IE1 (low), which must wait for both to return.
        .area   CSEG    (ABS,CODE)
        .org    0x0000
        ljmp    main
        .org    0x0003
        ljmp    isr0
        .org    0x0013
        ljmp    isr1
        .org    0x001B
        ljmp    isrt1
        .org    0x0040
isr0:   mov     @r0,#0x10
        inc     r0
        setb    0x8F            ; TF1: high level, preempts this routine
        mov     @r0,#0x11
        inc     r0
        setb    0x8B            ; IE1: low level, must wait
        mov     @r0,#0x12
        inc     r0
        mov     @r0,#0x13
        inc     r0
        reti
isr1:   mov     @r0,#0x30
        inc     r0
        reti
isrt1:  mov     @r0,#0x20
        inc     r0
        setb    0x8B            ; IE1: low, cannot interrupt a high routine
        mov     @r0,#0x21
        inc     r0
        reti
main:   mov     0x81,#0x60
        mov     r0,#0x30
        setb    0x88            ; IT0
        setb    0x8A            ; IT1
        mov     0xB8,#0x08      ; IP: PT1 high
        mov     0xA8,#0x8D      ; IE: EA EX0 EX1 ET1
        setb    0x89            ; IE0
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        mov     0x5F,r0
        sjmp    .
