# Intel 8051 (MCS-51) on the Raspberry Pi Pico — PureMetal

A fast MCS-51 instruction-set core for the Raspberry Pi Pico series, written in
PureMetal. The Pico W (RP2040) is the tested board; the Pico 2 W (RP2350)
build compiles from the same generator.

The CPU loop runs from SRAM and dispatches through a 256-entry `.Label` table.
Every handler ends in its own copy of the dispatch tail, so there is no
procedure call per guest instruction. Instruction semantics are PureMetal; only
the dispatch tail is inline assembly, and a plain computed-`Goto` tail is
available and tested too.

Every test below ran on a physical Pico W (RP2040 at 200 MHz) on 2026-10-23,
and all three builds pass every suite. The Pico 2 W (RP2350, 150 MHz) builds
compile from the same sources; no Pico 2 W was available to this work, so they
have not been run on a board yet.

## Measured speed (Pico W, 200 MHz)

Each sample runs exactly 1,000,000 guest instructions with the untimed,
assembly-tail build; USB and setup are outside the timed interval.

| Instruction mix | First build | Tuned |
|---|---:|---:|
| `DJNZ R7,$` / `SJMP` | 3.58 M instructions/s | **4.36 M instructions/s** |
| `ADD #` / `ADDC Rn` / `XRL #` / `RLC A` / `SUBB Rn` | 3.66 M | **3.91 M** |
| `MOV A,@R0` / `MOV dir,A` / `MOV dir,dir` / `INC R0` / `CJNE` | 3.82 M | **4.14 M** |
| `MOVX` / `CPL A` / `INC DPTR` / `MOV A,DPH` / `CJNE` | 4.08 M | **4.63 M** |

Programs compiled by PureMetal Forge's 8051 target (whole runs, in windows of
10,000):

| Program | Untimed build | Timed build | Goto tail, timed |
|---|---:|---:|---:|
| primes (sieve below 2000) | 5.00 M instructions/s | 8.65 M machine cycles/s | 6.63 M cycles/s |
| fibcrc (32-bit Fibonacci, CRC-16, gcd) | 5.44 M | 9.69 M | 7.28 M |
| sort (bubble sort of 48 words) | 4.98 M | 8.51 M | 6.51 M |

A 12 MHz 8051 runs 1 million machine cycles a second, so the timed core runs
compiled code at about **8.5 to 11 times the speed of an original 8051**. The
plain PureMetal computed-`Goto` tail is about 25% slower than the assembly tail.

The tuning, measured (`docs/benchmark-*.log`): on the M0+, PC and the run budget
live in the LOW registers r4/r5, so the dispatch tail indexes with r4 directly,
wraps PC with one UXTH, and the budget check is SUBS + BLE (it had been a move
out of r11 and back). Each arm of a conditional branch dispatches by itself
instead of jumping to a shared tail, and branch offsets use a signed byte load.
Putting the bank base in r6 as well starved the compiler of low registers (it
spilled to the stack inside the handlers), so the bank base stays in r8.

## Desktop version

`desktop/` holds the same core for Windows, in PureBasic (C back end), with a
front end drawn by the Neon Arcade Display Engine. It shows the CPU and
peripheral registers, a disassembly with click-to-set breakpoints, internal
RAM / SFR / XDATA / code views, test results and serial output, and the speed,
with Open, Reset, Run/Stop, Step and Step 100 controls. The handlers are
generated from the same text as the Pico core's (`tools/generate_desktop.py`).

| Dispatch, measured on this PC (untimed) | DJNZ | arithmetic | internal memory | MOVX |
|---|---:|---:|---:|---:|
| labels-as-values (inline C `goto *table[op]`), used | 298 M instructions/s | 459 M | 443 M | 495 M |
| table of procedure addresses | 234 M | 373 M | 343 M | 417 M |

The program itself uses the timed core: 536–730 M machine cycles/s
(`mcs51_console.exe --bench`), and 782 M in the window running
`desktop/examples/speed_loop.ihx`.

```powershell
desktop\build.ps1                        # mcs51_desktop.exe and mcs51_console.exe
desktop\mcs51_desktop.exe program.hex    # the window, with an Intel HEX or .bin loaded
desktop\mcs51_console.exe --test         # the board's test suites; exit code 0 = all pass
desktop\mcs51_console.exe --bench
```

`--test` runs `tests/verify_body.pico` itself (the same verification code the
board runs, compiled as PureBasic) and passes everything
(`docs/desktop-verification.log`). The window's **Run tests** button runs it
too; `docs/desktop-*.png` are captures of the window.

## Scope

- **All 255 opcodes** of the MCS-51 (`$A5` is not an instruction: the core stops
  on it, see below). Every addressing mode, register banks 0–3 through PSW,
  PSW with CY, AC, F0, RS1, RS0, OV, PSW.1 and P (parity, always from ACC).
- **Separate address spaces**: 64 KB code (`M51Code`), 64 KB XDATA
  (`M51XData`, or hooks), 256 bytes internal RAM (`M51IRam`; the upper 128 only
  by indirect address and the stack, on the 8052), SFR space, bit space
  ($20–$2F and the bit-addressable SFRs).
- **MUL AB, DIV AB, DA A** with the flag rules of the MCS-51 User's Manual.
- **Interrupts** with the two priority levels: IE0, TF0, IE1, TF1, RI/TI and (8052)
  TF2/EXF2, polled in that fixed order; a high-level routine cannot be
  interrupted, a low-level one only by a high-level request; after RETI and after
  any write to IE or IP one more instruction always runs first; hardware clears
  TF0/TF1 and the edge-triggered IE0/IE1 on vectoring.
- **Timers 0 and 1** in modes 0–3 (mode 3 splits timer 0, TH0 using TR1/TF1),
  timer or counter, GATE with the INT0/INT1 pin; **timer 2** (8052) auto-reload,
  capture (T2EX), baud-rate generator.
- **Serial port**: SBUF write delivers the byte (9-bit in modes 2/3) to a hook or a
  queue and sets TI at once; received frames are offered by the program and set
  RI, RB8, honouring REN and the SM2 address filter.
- **Ports** P0–P3: latch plus input pins. Instructions that read a port read
  latch AND pins; read-modify-write instructions (ANL, ORL, XRL, INC, DEC, DJNZ,
  JBC, CPL, CLR, SETB and MOV bit,C) read the latch, as on the chip.
- **PCON** idle (stops instructions until an interrupt) and power-down (stops
  until `M51Reset`).
- **Machine cycles**: with `#M51_TIMING = 1` the run budget and `M51Cycles` count
  machine cycles (12 oscillator clocks each) per the MCS-51 instruction table;
  with `#M51_TIMING = 0` they count instructions, which is fastest.

Not modelled: the serial frame time (TI is set at once), the oscillator and
reset pins, ALE/PSEN bus timing, the 8052's T2 output and T2MOD of later
derivatives, and anything beyond the Intel 8051/8052 SFR set (the SFR hook is
there for that).

## The PM51 display board (the machine around the core)

A small 8051 computer defined for this emulator, so programs (and the demo in
`demo/`) have a screen, sound and buttons. It is shown on the Pico's panel and
in the desktop program. Everything is reached the way an 8051 reaches external
hardware: MOVX into XDATA, and port P1. A compiled PureMetal program, whose
variables all live in XDATA from $0000, uses `PokeA`/`PeekA` on these
addresses; it has no interrupt handlers (the compiler's 8051 target refuses
them), so everything can be polled. Assembly programs may also take INT0.

**CPU**: an 8052 at 24 MHz, 12 clocks a machine cycle: 2,000,000 machine
cycles a second, 40,000 per frame. Code: 64 KB at $0000.

**Frames**: 50 a second. At the start of each frame the board latches the
picture as it is in memory, increments FRAME, sets STATUS bit 0 and pulls INT0
low for one cycle (a falling edge: IE0 when IT0 = 1).

| XDATA | Size | What |
|---|---|---|
| $0000-$7FFF | 32 KB | RAM (the compiler's variables start at $0000) |
| $8000-$CFFF | 20,480 | **Bitmap**, 160 x 128, one byte a pixel, RGB332 (bits 7-5 red, 4-2 green, 1-0 blue): $8000 + y*160 + x |
| $D000-$D13F | 320 | **Text**: 20 columns x 16 rows of 8x8 characters over the bitmap, $D000 + row*20 + col. ASCII 32-126 in the board's font; 0 = no character |
| $D200-$D33F | 320 | **Text colour**, one RGB332 byte per cell (the character's pixels; its background is transparent) |
| $D400-$D43F | 64 | **Sprites**: 8 x 8 bytes - X, Y (top-left, in bitmap pixels; X 0-159, Y 0-127), PATTERN (0-15), FLAGS (bit 0 shown, bit 1 mirror X, bit 2 mirror Y), 4 spare |
| $D800-$DBFF | 1,024 | **Sprite patterns**: 16 x 8x8 pixels, one RGB332 byte each, 0 = transparent |
| $DC00-$DC7F | 128 | **Line colours**: bitmap pixel value 0 on line y is drawn in colour LINE[(y + LINEOFS) & 127] (raster bars) |
| $DD00-$EFFF | | RAM |
| $F000-$F0FF | | **I/O registers** (below) |
| $F100-$FFFF | | RAM |

| I/O | R/W | What |
|---|---|---|
| $F000 FRAME | R | frame counter, +1 every frame (wraps) |
| $F001 STATUS | R | bit 0: a frame began since the last read (cleared by the read) |
| $F002 SCROLLX | R/W | the bitmap is shown from column SCROLLX, wrapping at 160 |
| $F003 SCROLLY | R/W | the bitmap is shown from line SCROLLY, wrapping at 128 |
| $F004 BORDER | R/W | colour around the 160x128 picture |
| $F005 LAYERS | R/W | bit 0 bitmap, bit 1 text, bit 2 sprites (reset: 7) |
| $F006 FILL | W | fills the whole bitmap with the value written (takes no CPU time) |
| $F007 TEXTCLR | W | any value: clears the text layer |
| $F008 BUTTONS | R | the buttons, 1 = pressed, in P1's bit order (for compiled programs, whose `PeekA` reaches XDATA, not ports) |
| $F009-$F00D RX, RY, RW, RH, RCOLOUR | R/W | the **rectangle unit**: left, top, width, height, colour |
| $F00E RECT | W | any value: fills that rectangle of the bitmap (clipped; takes no CPU time) |
| $F00F LINEOFS | R/W | line y is drawn in LINE[(y + LINEOFS) & 127]: one write moves every raster bar |
| $F010-$F01B TONE 0-2 | R/W | per voice, 4 bytes at $F010 + 4*n: FREQ low, FREQ high (Hz, 0 = silent), VOLUME (0-15), WAVE (0 square, 1 triangle, 2 sawtooth, 3 noise) |
| $F01C MASTER | R/W | master volume 0-15 (reset: 12) |

**Port P1** (inputs, a pressed button reads 0): P1.0 up, P1.1 down, P1.2
left, P1.3 right, P1.4 A, P1.5 B, P1.6 start, P1.7 select. **Serial**: what the
program writes to SBUF appears on the Pico's USB serial and in the desktop's
serial pane.

On the Pico W (`machine/pm51_picow.picow`; `pm51_pico2w.pico2w` for the
Pico 2 W) the picture is drawn on the LAFVIN ST7796 panel at twice the size
(320x256, centred), and the LAFVIN controls are the buttons: the stick is
up/down/left/right, BTN1 (GP15) is A, BTN2 (GP14) is B, both together are
start. The Pico build is **silent for now**: its sound would go to the
Bluetooth speaker the NES uses, whose address lives in a private wrapper this
repository does not have. On the desktop the picture is drawn in the window,
the keyboard is the buttons (arrows, Z = A, X = B, Enter = start, Space =
select) and the sound plays through Windows.

The demo (`demo/`) is a PureMetal program built by PureMetal Forge's 8051
target: `py -3 demo/make_demo.py` writes `demo/pm51_demo.i8051` (its tables
go into XDATA with one constant `PokeA` each, because the 8051 target has no
DataSection), the compiler makes `pm51_demo.hex`/`.bin`, and
`py -3 tools/embed_program.py demo/pm51_demo.bin` puts it in the Pico
firmware. The desktop loads the `.hex` directly.

## Configure and include

Every constant must be defined before `XIncludeFile "src/mcs51.pico"` (Pico W)
or `"src/mcs51.pico2"` (Pico 2 W):

| Constant | 1 | 0 |
|---|---|---|
| `#M51_TIMING` | `M51Run(n)` counts machine cycles | counts instructions (fastest) |
| `#M51_ASM_TAIL` | inline-assembly dispatch tail | plain PureMetal computed `Goto` |
| `#M51_8052` | 8052: 256 bytes internal RAM, timer 2 | 8051: 128 bytes (upper indirect reads $FF, writes dropped) |
| `#M51_SFR_HOOK` | program supplies `M51HookSfrRead(adr)` / `M51HookSfrWrite(adr, v)` | unmodelled SFRs are plain storage |
| `#M51_XDATA_HOOK` | MOVX through `M51HookXRead(adr)` / `M51HookXWrite(adr, v)` | 64 KB array `M51XData` |
| `#M51_CODE_HOOK` | MOVC through `M51HookCodeRead(adr)` | MOVC reads `M51Code` |
| `#M51_SERIAL_HOOK` | each SBUF write goes to `M51HookSerialTx(w)` | queued for `M51SerialTxGet()` |

Instruction fetch always reads `M51Code`, for speed: bank-switched code is
done by copying into it.

With `#M51_SFR_HOOK = 1` the hooks receive: reads and writes of every SFR the
core does not model; every port latch write (after it is stored); and port pin
reads (the hook returns the pin byte, the core ANDs it with the latch).

## API

| Call / state | Meaning |
|---|---|
| `M51Reset()` | Power-on reset of registers and SFRs (SP=7, ports $FF, PC=0). Internal RAM, code and XDATA are left as they are. |
| `M51Run(n)` | Run n machine cycles (timed) or n instructions (untimed); returns how many ran. Whole instructions only, so a timed run can end up to 3 cycles past n. Returns 0 when stopped. |
| `M51Code(a)`, `M51XData(a)`, `M51IRam(a)` | The memories, byte arrays. |
| `M51PC`, `M51A`, `M51B`, `M51SP`, `M51DPTR` | Registers (keep them in range when writing them). |
| `M51Psw()` / `M51SetPsw(v)` | PSW as a byte, P computed from A. Setting it also selects the bank. |
| `M51ReadDirect(a)` / `M51WriteDirect(a, v)` | A direct address as an instruction sees it: internal RAM below $80, SFRs from $80, with every side effect. |
| `M51Sfr(a & $7F)` | Raw SFR storage (no side effects). |
| `M51SetPins(port, v)` | Input pin levels of P0–P3 (without the SFR hook). |
| `M51SetInt0(l)`, `M51SetInt1(l)` | INT0/INT1 pin levels: a falling edge sets IE0/IE1 when edge-triggered; level-triggered flags follow the pin; GATE uses them. |
| `M51SetT2Ex(l)` | T2EX pin (8052): a falling edge with EXEN2 sets EXF2 and captures or reloads. |
| `M51CountPulses(t, n)` | n external pulses on T0/T1/T2 for a timer in counter mode. |
| `M51SerialReceive(w)` | Offer a received frame (bit 8 = ninth bit). 1 = taken (or dropped by SM2), 0 = receiver off or RI still set: offer it again later. |
| `M51SerialTxGet()` | Next byte written to SBUF, or -1 (without the serial hook). `M51TxLost` counts queue overflows. |
| `M51Cycles` | Machine cycles (timed) or instructions (untimed) run since `M51Reset`. |
| `M51IntCount` | Interrupts taken since `M51Reset`. |
| `M51Stopped`, `M51BadOpcode` | Set when the undefined opcode $A5 is reached: PC stays on it, it is not counted, `M51Run` returns 0 until `M51Reset`. |
| `M51Idle`, `M51PowerDown` | PCON states. |

Interrupt requests are evaluated between instructions whenever one can have
changed: a timer overflow ends a run slice exactly there, and so does any write
to TCON, SCON, IE, IP, PCON, the timer registers or SBUF, and RETI. A program
that raises a request from outside (`M51SetInt0`, `M51SerialReceive`) does it
between `M51Run` calls; it is taken at the start of the next one.

The core has one global CPU and is not reentrant; keep it on one core.
**Reserved registers** (application-wide): Pico W r4 `M51PC`, r5 `M51Left`,
r8 `M51RB`, r9 `M51A`, r10 `M51Res`; Pico 2 W r4 `M51PC`, r6 `M51Table`,
r8 `M51RB`, r9 `M51A`, r10 `M51Res`, r11 `M51Left`. PureMetal checks every
library and assembly block against them.

## Verification

No published single-instruction test suite exists for the MCS-51, so four
kinds of evidence are used. All of it ran on the Pico W in three builds:
timed with the assembly tail, untimed with the assembly tail, and timed with
the plain computed `Goto` (`docs/picow-verification-*.log`).

1. **7,680 single-instruction vectors** (`tools/make_vectors.py`): 24 random
   states per opcode and 64 for the arithmetic ones (ADD, ADDC, SUBB, DA, MUL,
   DIV), with steered edge cases (zero divisors, equal CJNE operands, DJNZ
   reaching zero, 16-bit wraps at PC $FFFE/$FFFF and DPTR $FFxx). Expected
   states come from **uCsim 0.8.15**, SDCC's simulator (`ucsim_51 -t 8052`): all
   256 bytes of internal RAM, the CPU registers and PSW, the timer registers,
   touched XDATA, the new PC and the machine-cycle count. The board regenerates
   each vector's internal RAM from a seed and compares all of it.
2. **Six programs built by PureMetal Forge's own 8051 target**
   (`tests/programs`, `tools/make_programs.py`): the compiler's three shipped
   examples plus a prime sieve, Fibonacci/CRC-16/gcd and a bubble sort. Each
   result's expected value is computed in Python from the algorithm, checked
   against uCsim's run first, and then checked on the board, together with
   uCsim's exact instruction and machine-cycle counts to the program's end.
3. **Interrupt, timer and serial programs** (`tests/asm`, assembled with
   sdas8051): the polling order of all six sources and the one-instruction rule
   after RETI and IE writes; two-level nesting; timers 0, 1 and 2 in modes 0-3,
   with interrupts (overflow counts built so they do not depend on how long an
   interrupt entry takes) and with exact polled register values; serial
   transmission in modes 1 and 3.
4. **API checks**: zero and negative budgets, $A5 stopping uncounted, the reset
   state, bank selection, port pins against the latch, the serial queue.

uCsim was corrected where it disagrees with the MCS-51 User's Manual. Each
correction is counted when the vectors are generated:

| uCsim | The manual / the chip | Effect |
|---|---|---|
| keeps a PSW.P that was written | P is recomputed from ACC every cycle | expected P = parity(final A); 6 vectors |
| does not wrap the 16-bit sum of `MOVC A,@A+PC`, `MOVC A,@A+DPTR`, `JMP @A+DPTR` | the 16-bit address wraps | 11 vectors |
| `PUSH SP` stores SP from before the increment | `(SP) <- (SP)+1; ((SP)) <- (direct)` | 1 vector; not settled on silicon (no 8051 chip here) |
| vectors to an interrupt straight after the instruction that set EA | after a write to IE or IP one more instruction runs first | the irq_order log |
| charges 1 machine cycle for the interrupt's hardware call | "the call itself takes two cycles" | +1 cycle per interrupt taken |

Also found by these tests: the compiler's 8051 target returns quotient 0 and
remainder 0 for a division by zero (its ruling of 2026-07-29), while the
comment in the shipped example `i8051_basic` still says -1 and the dividend.

## Build and run on the board

```powershell
.\tools\build.ps1                                         # firmware\8051-picow.uf2 (the demo)
.\tools\build.ps1 -Source src/demo.pico2w -Output firmware/8051-pico2w.uf2
```

On a shared board use `tools/board.ps1`: it compiles every image first, then
takes the board through the shared `C:\PMFBuild\board-leases\lease.ps1`
(`Get-BoardLease` / `Release-BoardLease`), uploads and captures each image
through the compiler (`--port`), and gives the board back:

```powershell
.\tools\board.ps1 -Port COM7 -Jobs 'tests/verify.picow:firmware/verify.uf2:45', 'src/demo.picow:firmware/8051-picow.uf2:25'
```

Images stay below flash $10050000 (the NES ROM store); the build script refuses
one that does not.

Regenerating (Python 3; the vector and program tools also need SDCC 4.5.0's
`ucsim_51`, `sdas8051` and `sdld`):

```powershell
py -3 tools/generate.py            # src/mcs51.pico and .pico2
py -3 tools/generate_desktop.py    # desktop/mcs51_core.pbi and mcs51_distable.pbi
py -3 tools/make_vectors.py
py -3 tools/make_programs.py
py -3 tools/make_asm_tests.py
py -3 tools/embed_tests.py         # the DataSections and the .pico2 copies
```

## Design

It follows the PureMetal 6502 and PDP-11 cores: one SRAM-resident
`ProcedureRAM` holding every handler, a 256-entry `.Label` table, an inlined
dispatch tail per handler, and reserved registers for the hot state. Flags are
kept raw: CY is bit 8 of the last result, AC bit 4 of `A xor operand xor
result`, OV bit 7 of the sign-overflow expression, and PSW is assembled only
when it is read. Direct addresses below $80 are an array index; SFR accesses go
through one procedure, which also brings the timers up to date. Timers advance
lazily, at the end of every run slice and before any timer or control SFR
access, and a slice never runs past the next timer overflow, so an interrupt is
taken on the instruction boundary where it becomes due.
