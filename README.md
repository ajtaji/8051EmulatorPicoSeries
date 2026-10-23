# Intel 8051 (MCS-51) on the Raspberry Pi Pico — PureMetal

A fast MCS-51 instruction-set core for the Raspberry Pi Pico series, written in
PureMetal. The Pico W (RP2040) is the tested board; the Pico 2 W (RP2350)
build compiles from the same generator.

The CPU loop runs from SRAM and dispatches through a 256-entry `.Label` table.
Every handler ends in its own copy of the dispatch tail, so there is no
procedure call per guest instruction. Instruction semantics are PureMetal; only
the dispatch tail is inline assembly, and a plain computed-`Goto` tail is
available and tested too.

@@RESULTS@@

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
| `M51Stopped`, `M51BadOpcode` | Set when the undefined opcode $A5 is reached: PC stays on it, it is not counted, `M51Run` returns 0 until `M51Reset`. |
| `M51Idle`, `M51PowerDown` | PCON states. |

Interrupt requests are evaluated between instructions whenever one can have
changed: a timer overflow ends a run slice exactly there, and so does any write
to TCON, SCON, IE, IP, PCON, the timer registers or SBUF, and RETI. A program
that raises a request from outside (`M51SetInt0`, `M51SerialReceive`) does it
between `M51Run` calls; it is taken at the start of the next one.

The core has one global CPU and is not reentrant; keep it on one core.
**Reserved registers** (application-wide): Pico W r4 `M51PC`, r5 `M51Left`,
r6 `M51RB`, r9 `M51A`, r10 `M51Res`; Pico 2 W r4 `M51PC`, r6 `M51Table`,
r8 `M51RB`, r9 `M51A`, r10 `M51Res`, r11 `M51Left`. PureMetal checks every
library and assembly block against them.

@@VERIFICATION@@
