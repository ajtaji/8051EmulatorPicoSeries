; A loop for watching the speed meter: copies and inverts 2 KB of XDATA,
; counts passes in internal RAM, and never ends.
        .area   CSEG    (ABS,CODE)
        .org    0x0000
        mov     0x81,#0x60
loop:   mov     dptr,#0x4000
        mov     r7,#8
outer:  mov     r6,#0
inner:  movx    a,@dptr
        cpl     a
        add     a,r6
        movx    @dptr,a
        inc     dptr
        djnz    r6,inner
        djnz    r7,outer
        inc     0x30
        mov     a,0x30
        jnz     loop
        inc     0x31
        sjmp    loop
