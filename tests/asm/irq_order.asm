; Software-raised interrupts, all at the low level, all pending at once:
; they must be taken in the fixed polling order IE0 TF0 IE1 TF1 RI/TI TF2,
; and the instruction after a write to IE, and after each RETI, must run
; before the next one. Each routine logs (its number, the main counter).
        .area   CSEG    (ABS,CODE)
        .org    0x0000
        ljmp    main
        .org    0x0003
        mov     a,#1
        sjmp    log
        .org    0x000B
        mov     a,#2
        sjmp    log
        .org    0x0013
        mov     a,#3
        sjmp    log
        .org    0x001B
        mov     a,#4
        sjmp    log
        .org    0x0023
        clr     0x99            ; TI
        mov     a,#5
        sjmp    log
        .org    0x002B
        clr     0xCF            ; TF2
        mov     a,#6
        sjmp    log
        .org    0x0033
log:    mov     @r0,a
        inc     r0
        mov     @r0,0x50
        inc     r0
        reti
main:   mov     0x81,#0x60      ; SP
        mov     r0,#0x30
        mov     0x50,#0
        setb    0x88            ; IT0: INT0 edge-triggered
        setb    0x8A            ; IT1
        mov     0xA8,#0x3F      ; IE: every source, EA still off
        setb    0x89            ; IE0
        setb    0x8D            ; TF0
        setb    0x8B            ; IE1
        setb    0x8F            ; TF1
        setb    0x99            ; TI
        setb    0xCF            ; TF2
        setb    0xAF            ; EA
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        inc     0x50
        mov     0x5F,r0
        sjmp    .
