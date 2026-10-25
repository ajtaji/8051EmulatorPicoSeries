"""Hand-written Thumb-2 handlers for the hot MCS-51 opcodes (RP2350 only).

tools/generate.py uses these for the 'pico2_t2' variant. Each one is compiled
only when its condition holds (#M51_ASM_TAIL = 1, plus #M51_8052 = 1 for @Ri
and #M51_XDATA_HOOK <> 1 for MOVX); otherwise the PureMetal handler is used,
so the plain-Goto build stays the reference. The same 7,680 vectors check both.

Registers (the core's ReserveRegister): r4 PC, r6 dispatch table, r8 bank
base, r9 A, r10 code base, r11 budget. A block uses r0-r3 only. Flags
stay in the core's raw form: CY is bit 8 of M51CyX, AC bit 4 of M51AcX, OV
bit 7 of M51OvX. The generator appends the budget check and the dispatch.

A handler whose operand may be an SFR (or the XDATA I/O page) branches to
OpXXSlow, a PureMetal path that follows the block.
"""

RESERVED = [('r4', 'M51PC'), ('r6', 'M51Table'), ('r8', 'M51RB'), ('r9', 'M51A'), ('r10', 'M51CodeBase'),
            ('r11', 'M51Left')]


def uses(lines):
    """The ASM Uses line: exactly the reserved registers the block touches (PM1130)."""
    import re
    regs = set(re.findall(r'\br\d+\b', ' '.join(lines)))
    names = [name for reg, name in RESERVED if reg in regs]
    return 'ASM Uses ' + ', '.join(names) if names else 'ASM'


STD = '#M51_ASM_TAIL = 1'
IND = '#M51_ASM_TAIL = 1 And #M51_8052 = 1'
XD = '#M51_ASM_TAIL = 1 And #M51_XDATA_HOOK <> 1'


def fetch(reg):
    """The next code byte into reg, PC advanced and wrapped."""
    return [f'  ldrb {reg}, [r10, r4]', '  adds r4, #1', '  uxth r4, r4']


def fetch_signed(reg):
    return [f'  ldrsb {reg}, [r10, r4]', '  adds r4, #1', '  uxth r4, r4']


def bank():
    """r0 = internal RAM, r3 = the bank's R0."""
    return ['  ldr r0, =global_m51iram', '  add r3, r0, r8']


def branch_if(cond):
    """r2 = the signed offset (PC already past it): take it when cond holds."""
    return [f'  it {cond}', f'  add{cond} r4, r4, r2', '  uxth r4, r4']


def add(carry):
    """r1 = operand: A = A + r1 (+ CY), with CY, AC and OV."""
    out = ['  add r0, r9, r1']
    if carry:
        out = ['  ldr r2, =global_m51cyx', '  ldr r2, [r2]', '  ubfx r2, r2, #8, #1', '  add r0, r9, r1',
               '  add r0, r0, r2']
    return out + ['  ldr r2, =global_m51cyx', '  str r0, [r2]',
                  '  eor r3, r9, r1', '  eor r3, r3, r0', '  ldr r2, =global_m51acx', '  str r3, [r2]',
                  '  eor r3, r9, r0', '  eor r2, r1, r0', '  and r3, r3, r2', '  ldr r2, =global_m51ovx',
                  '  str r3, [r2]', '  and r9, r0, #255']


def subb():
    """r1 = operand: A = A - r1 - CY, with CY, AC and OV."""
    return ['  ldr r2, =global_m51cyx', '  ldr r3, [r2]', '  ubfx r3, r3, #8, #1',
            '  sub r0, r9, r1', '  sub r0, r0, r3', '  str r0, [r2]',
            '  eor r3, r9, r1', '  eor r3, r3, r0', '  ldr r2, =global_m51acx', '  str r3, [r2]',
            '  eor r3, r9, r1', '  eor r2, r9, r0', '  and r3, r3, r2', '  ldr r2, =global_m51ovx',
            '  str r3, [r2]', '  and r9, r0, #255']


def cy_compare(a, b):
    """CY = a < b (unsigned bytes, as the raw difference); Z clear when a <> b."""
    return [f'  subs r3, {a}, {b}', '  ldr r1, =global_m51cyx', '  str r3, [r1]', '  cmp r3, #0']


def handlers():
    """{opcode: (asm lines, PureMetal slow path or None, condition)}"""
    h = {}
    for n in range(8):
        r = f'[r3, #{n}]'
        h[0xE8 + n] = (bank() + [f'  ldrb r9, {r}'], None, STD)                                   # MOV A,Rn
        h[0xF8 + n] = (bank() + [f'  strb r9, {r}'], None, STD)                                   # MOV Rn,A
        h[0x78 + n] = (fetch('r1') + bank() + [f'  strb r1, {r}'], None, STD)                     # MOV Rn,#
        h[0x08 + n] = (bank() + [f'  ldrb r1, {r}', '  adds r1, #1', f'  strb r1, {r}'], None, STD)  # INC Rn
        h[0x18 + n] = (bank() + [f'  ldrb r1, {r}', '  subs r1, #1', f'  strb r1, {r}'], None, STD)  # DEC Rn
        h[0xD8 + n] = (bank() + [f'  ldrb r1, {r}', '  subs r1, #1', f'  strb r1, {r}'] + fetch_signed('r2')
                       + ['  tst r1, #255'] + branch_if('ne'), None, STD)                         # DJNZ Rn
        h[0x28 + n] = (bank() + [f'  ldrb r1, {r}'] + add(False), None, STD)                      # ADD A,Rn
        h[0x38 + n] = (bank() + [f'  ldrb r1, {r}'] + add(True), None, STD)                       # ADDC A,Rn
        h[0x98 + n] = (bank() + [f'  ldrb r1, {r}'] + subb(), None, STD)                          # SUBB A,Rn
        h[0x48 + n] = (bank() + [f'  ldrb r1, {r}', '  orr r9, r9, r1'], None, STD)               # ORL A,Rn
        h[0x58 + n] = (bank() + [f'  ldrb r1, {r}', '  and r9, r9, r1'], None, STD)               # ANL A,Rn
        h[0x68 + n] = (bank() + [f'  ldrb r1, {r}', '  eor r9, r9, r1'], None, STD)               # XRL A,Rn
        h[0xB8 + n] = (bank() + [f'  ldrb r0, {r}'] + fetch('r1') + fetch_signed('r2')
                       + cy_compare('r0', 'r1') + branch_if('ne'), None, STD)                     # CJNE Rn,#,rel
    for i in range(2):
        r = f'[r3, #{i}]'
        h[0xE6 + i] = (bank() + [f'  ldrb r1, {r}', '  ldrb r9, [r0, r1]'], None, IND)            # MOV A,@Ri
        h[0xF6 + i] = (bank() + [f'  ldrb r1, {r}', '  strb r9, [r0, r1]'], None, IND)            # MOV @Ri,A
        h[0x06 + i] = (bank() + [f'  ldrb r1, {r}', '  ldrb r2, [r0, r1]', '  adds r2, #1',
                                 '  strb r2, [r0, r1]'], None, IND)                               # INC @Ri
    h[0x74] = (fetch('r9'), None, STD)                                                            # MOV A,#
    h[0x24] = (fetch('r1') + add(False), None, STD)                                               # ADD A,#
    h[0x34] = (fetch('r1') + add(True), None, STD)                                                # ADDC A,#
    h[0x94] = (fetch('r1') + subb(), None, STD)                                                   # SUBB A,#
    h[0x44] = (fetch('r1') + ['  orr r9, r9, r1'], None, STD)                                     # ORL A,#
    h[0x54] = (fetch('r1') + ['  and r9, r9, r1'], None, STD)                                     # ANL A,#
    h[0x64] = (fetch('r1') + ['  eor r9, r9, r1'], None, STD)                                     # XRL A,#
    h[0xB4] = (fetch('r0') + fetch_signed('r2') + cy_compare('r9', 'r0') + branch_if('ne'), None, STD)  # CJNE A,#
    h[0x04] = (['  add r9, r9, #1', '  and r9, r9, #255'], None, STD)                             # INC A
    h[0x14] = (['  sub r9, r9, #1', '  and r9, r9, #255'], None, STD)                             # DEC A
    h[0xE4] = (['  mov r9, #0'], None, STD)                                                       # CLR A
    h[0xF4] = (['  eor r9, r9, #255'], None, STD)                                                 # CPL A
    h[0xC4] = (['  lsl r0, r9, #4', '  orr r0, r0, r9, lsr #4', '  and r9, r0, #255'], None, STD)  # SWAP A
    h[0x33] = (['  ldr r2, =global_m51cyx', '  ldr r1, [r2]', '  ubfx r1, r1, #8, #1',
                '  orr r0, r1, r9, lsl #1', '  str r0, [r2]', '  and r9, r0, #255'], None, STD)   # RLC A
    h[0xC3] = (['  ldr r2, =global_m51cyx', '  movs r0, #0', '  str r0, [r2]'], None, STD)        # CLR C
    h[0xD3] = (['  ldr r2, =global_m51cyx', '  mov r0, #256', '  str r0, [r2]'], None, STD)       # SETB C
    h[0x80] = (fetch_signed('r2') + ['  add r4, r4, r2', '  uxth r4, r4'], None, STD)             # SJMP
    h[0x60] = (fetch_signed('r2') + ['  cmp r9, #0'] + branch_if('eq'), None, STD)                # JZ
    h[0x70] = (fetch_signed('r2') + ['  cmp r9, #0'] + branch_if('ne'), None, STD)                # JNZ
    cy = ['  ldr r0, =global_m51cyx', '  ldr r0, [r0]', '  tst r0, #256']
    h[0x40] = (fetch_signed('r2') + cy + branch_if('ne'), None, STD)                              # JC
    h[0x50] = (fetch_signed('r2') + cy + branch_if('eq'), None, STD)                              # JNC
    h[0x90] = (fetch('r1') + fetch('r2') + ['  orr r1, r2, r1, lsl #8', '  ldr r0, =global_m51dptr',
                                            '  str r1, [r0]'], None, STD)                         # MOV DPTR,#
    h[0xA3] = (['  ldr r0, =global_m51dptr', '  ldr r1, [r0]', '  adds r1, #1', '  uxth r1, r1',
                '  str r1, [r0]'], None, STD)                                                     # INC DPTR
    # MOVX through the array; M51XioPage is the hooked page (-1 when there is none).
    page = ['  ldr r2, =global_m51xiopage', '  ldr r2, [r2]', '  and r3, r0, #65280', '  cmp r3, r2']
    h[0xE0] = (['  ldr r0, =global_m51dptr', '  ldr r0, [r0]'] + page + ['  beq __ul_m51slice_ope0slow',
               '  ldr r1, =global_m51xdata', '  ldrb r9, [r1, r0]'], ['M51XRd(M51A, M51DPTR)'], XD)  # MOVX A,@DPTR
    h[0xF0] = (['  ldr r0, =global_m51dptr', '  ldr r0, [r0]'] + page + ['  beq __ul_m51slice_opf0slow',
               '  ldr r1, =global_m51xdata', '  strb r9, [r1, r0]'], ['M51XWr(M51DPTR, M51A)'], XD)  # MOVX @DPTR,A
    # Direct bytes: internal RAM here, an SFR through the PureMetal path.
    h[0xE5] = (fetch('r1') + ['  ldr r0, =global_m51ea', '  str r1, [r0]', '  cmp r1, #128',
                              '  bhs __ul_m51slice_ope5slow', '  ldr r0, =global_m51iram', '  ldrb r9, [r0, r1]'],
               ['M51A = M51SfrRead(M51Ea)'], STD)                                                 # MOV A,dir
    h[0xF5] = (fetch('r1') + ['  ldr r0, =global_m51ea', '  str r1, [r0]', '  cmp r1, #128',
                              '  bhs __ul_m51slice_opf5slow', '  ldr r0, =global_m51iram', '  strb r9, [r0, r1]'],
               ['M51SfrWrite(M51Ea, M51A)'], STD)                                                 # MOV dir,A
    h[0x85] = (fetch('r1') + fetch('r2') + ['  ldr r0, =global_m51tmp', '  str r1, [r0]', '  ldr r0, =global_m51ea',
                                            '  str r2, [r0]', '  orr r0, r1, r2', '  cmp r0, #128',
                                            '  bhs __ul_m51slice_op85slow', '  ldr r0, =global_m51iram',
                                            '  ldrb r3, [r0, r1]', '  strb r3, [r0, r2]'],
               ['If M51Tmp < $80', '  M51Val = M51IRam(M51Tmp)', 'Else', '  M51Val = M51SfrRead(M51Tmp)', 'EndIf',
                'If M51Ea < $80', '  M51IRam(M51Ea) = M51Val', 'Else', '  M51SfrWrite(M51Ea, M51Val)', 'EndIf'],
               STD)                                                                               # MOV dir,dir
    return h
