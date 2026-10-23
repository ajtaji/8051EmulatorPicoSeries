; Serial port, mode 1, timer 1 as the baud clock: transmit a message by
; polling TI, then a ninth-bit frame in mode 3.
        .area   CSEG    (ABS,CODE)
        .org    0x0000
        ljmp    main
        .org    0x0040
main:   mov     0x81,#0x60
        mov     0x89,#0x20      ; TMOD: timer 1 mode 2
        mov     0x8D,#0xFD      ; TH1: 9600 baud at 11.0592 MHz
        mov     0x8B,#0xFD
        setb    0x8E            ; TR1
        mov     0x98,#0x50      ; SCON: mode 1, REN
        mov     dptr,#msg
next:   clr     a
        movc    a,@a+dptr
        jz      done
        clr     0x99            ; TI
        mov     0x99,a          ; SBUF
wait:   nop
        jnb     0x99,wait
        inc     dptr
        sjmp    next
done:   mov     0x98,#0xD8      ; SCON: mode 3, REN, TB8
        clr     0x99
        mov     0x99,#0x5A
wait2:  nop
        jnb     0x99,wait2
        mov     0x40,0x98
        sjmp    .
msg:    .ascii  "8051 on a Pico"
        .db     13, 10, 0
