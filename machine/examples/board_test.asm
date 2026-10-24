; PM51 board smoke test (assembly): every display layer, the tone unit and
; the buttons. Assemble: sdas8051 -plosgff board_test.asm ; sdld -i board_test.ihx board_test.rel
        .area   CSEG    (ABS,CODE)
        .org    0x0000
        ljmp    main
        .org    0x0040
main:   mov     0x81,#0x60
        ; Bitmap: a diagonal colour gradient, colour = x + y (0 skipped: 0 shows the line colour).
        mov     dptr,#0x8000
        mov     r7,#0           ; y
by:     mov     r6,#0           ; x
bx:     mov     a,r6
        add     a,r7
        anl     a,#0xFC         ; wide stripes
        jz      bz
        movx    @dptr,a
bz:     inc     dptr
        inc     r6
        cjne    r6,#160,bx
        inc     r7
        cjne    r7,#128,by
        ; A black band through the middle: pixel 0, drawn in the line colours.
        mov     dptr,#0x8000+48*160
        mov     r5,#32
cb:     mov     r6,#160
cc:     clr     a
        movx    @dptr,a
        inc     dptr
        djnz    r6,cc
        djnz    r5,cb
        ; Text "PM51 BOARD OK" on row 7, column 3, in white.
        mov     dptr,#msg
        mov     r0,#0
tx:     mov     a,r0
        movc    a,@a+dptr
        jz      txd
        push    dpl
        push    dph
        mov     dptr,#0xD000+7*20+3
        mov     r1,a
        mov     a,dpl
        add     a,r0
        mov     dpl,a
        mov     a,r1
        movx    @dptr,a
        mov     a,dph
        add     a,#2            ; the colour byte: +$200
        mov     dph,a
        mov     a,#0xFF
        movx    @dptr,a
        pop     dph
        pop     dpl
        inc     r0
        sjmp    tx
txd:    ; Sprite pattern 0: an 8x8 yellow ring.
        mov     dptr,#0xD800
        mov     r6,#64
sp:     mov     a,r6
        dec     a
        anl     a,#0x09         ; a checker of yellow and transparent
        jz      sp0
        mov     a,#0xFC
        sjmp    sp1
sp0:    clr     a
sp1:    movx    @dptr,a
        inc     dptr
        djnz    r6,sp
        ; Sprite 0 at (20, 100), shown.
        mov     dptr,#0xD400
        mov     a,#20
        movx    @dptr,a
        inc     dptr
        mov     a,#100
        movx    @dptr,a
        inc     dptr
        clr     a
        movx    @dptr,a
        inc     dptr
        mov     a,#1
        movx    @dptr,a
        ; Voice 0: 440 Hz square, volume 8.
        mov     dptr,#0xF010
        mov     a,#0xB8
        movx    @dptr,a
        inc     dptr
        mov     a,#0x01
        movx    @dptr,a
        inc     dptr
        mov     a,#8
        movx    @dptr,a
        inc     dptr
        clr     a
        movx    @dptr,a
        ; Each frame: wait for STATUS, rainbow line colours from the frame
        ; number, sprite 0 moves right (left while P1.2 is held), the bitmap
        ; scrolls down, and the tone stops at frame 100.
frame:  mov     dptr,#0xF001
wf:     movx    a,@dptr
        jz      wf
        mov     dptr,#0xF000
        movx    a,@dptr
        mov     r4,a            ; frame number
        mov     dptr,#0xDC00
        mov     r6,#128
lc:     mov     a,r6
        add     a,r4
        rl      a
        rl      a
        movx    @dptr,a
        inc     dptr
        djnz    r6,lc
        mov     dptr,#0xD400
        movx    a,@dptr
        jb      0x92,right      ; P1.2 (left) reads 1 when not pressed
        dec     a
        dec     a
right:  inc     a
        movx    @dptr,a
        mov     dptr,#0xF003
        movx    a,@dptr
        inc     a
        anl     a,#0x7F
        movx    @dptr,a
        cjne    r4,#100,frame
        mov     dptr,#0xF012
        clr     a
        movx    @dptr,a
        sjmp    frame
msg:    .ascii  "PM51 BOARD OK"
        .db     0
