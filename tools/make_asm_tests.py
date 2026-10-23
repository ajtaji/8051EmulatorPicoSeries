"""Interrupt, timer and serial programs, with uCsim's end state as the oracle.

Each tests/asm/<name>.asm is assembled with SDCC's sdas8051 and linked with
sdld, then run in uCsim (8052) until its final jump-to-self. Recorded for the
board: the code image, internal RAM $30-$7F, the bytes the serial port sent,
and uCsim's instruction and machine-cycle counts.

  flags bit 0: compare cycles and instructions (not for serial.asm, whose
               wait loops depend on the frame time the core does not model)
  flags bit 1: timed builds only (timer results count machine cycles)

Run from the repository root:  py -3 tools/make_asm_tests.py
"""
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASM = ROOT / 'tests' / 'asm'
BIN = Path(r'C:\PMFBuild\downloads\sdcc\extract\bin')
TESTS = [('irq_order', 1), ('irq_nest', 1), ('timers', 3), ('serial', 2)]


def assemble(name):
    src = ASM / f'{name}.asm'
    r = subprocess.run([str(BIN / 'sdas8051.exe'), '-plosgff', str(src)], capture_output=True, text=True, cwd=ASM)
    if r.returncode != 0:
        raise SystemExit(f'{name}: sdas8051 failed\n{r.stdout}{r.stderr}')
    r = subprocess.run([str(BIN / 'sdld.exe'), '-i', f'{name}.ihx', f'{name}.rel'], capture_output=True, text=True,
                       cwd=ASM)
    image = bytearray(0x10000)
    top = 0
    for line in (ASM / f'{name}.ihx').read_text().splitlines():
        n, addr, kind = int(line[1:3], 16), int(line[3:7], 16), int(line[7:9], 16)
        if kind == 0:
            image[addr:addr + n] = bytes.fromhex(line[9:9 + 2 * n])
            top = max(top, addr + n)
    for ext in ('rel', 'sym', 'hlr', 'map', 'mem', 'rst'):
        (ASM / f'{name}.{ext}').unlink(missing_ok=True)
    return bytes(image[:top])


def run_ucsim(name):
    script = ASM / 'ucsim.tmp'
    stdin = ASM / 'ucsim_stdin.tmp'
    serial_out = ASM / f'{name}.serial.tmp'
    script.write_text('\n'.join([
        f'file "{(ASM / (name + ".ihx")).as_posix()}"',
        'fill iram 0 0xff 0',
        'fill xram 0 0xffff 0',
        'set option selfjump_stop 1',
        'run',
        'echo @@STATE',
        'state',
        'echo @@I',
        'dump /h iram 0x30 0x7f 16',
        'echo @@END']) + '\n')
    stdin.write_text(f'exec "{script.as_posix()}"\nquit\n')
    with open(stdin) as f:
        out = subprocess.run([str(BIN / 'ucsim_51.exe'), '-q', '-t', '8052', '-X', '11.0592M',
                              '-S', f'uart=0,out={serial_out.as_posix()}'], stdin=f, capture_output=True,
                             text=True, timeout=600).stdout
    script.unlink()
    stdin.unlink()
    sent = serial_out.read_bytes() if serial_out.exists() else b''
    # uCsim writes its serial output file in text mode: each LF the program
    # sent arrives as CR LF.
    sent = sent.replace(b'\r\n', b'\n')
    serial_out.unlink(missing_ok=True)
    state = out[out.index('\n@@STATE'):out.index('\n@@I')]
    pc = int(re.search(r'PC= 0x([0-9a-fA-F]+)', state).group(1), 16)
    inst = int(re.search(r'Inst= (\d+)', state).group(1))
    clks = int(re.search(r'Total time since last reset= [0-9.]+ sec \((\d+) clks\)', state).group(1))
    iram = bytearray(0x50)
    for line in out[out.index('\n@@I'):out.index('\n@@END')].splitlines():
        tok = line.split()
        if len(tok) > 1 and tok[0].startswith('0x') and not line.startswith('dump'):
            base = int(tok[0], 16)
            for i in range(16):
                if 1 + i < len(tok) and re.fullmatch(r'[0-9a-f]{2}', tok[1 + i]) and 0x30 <= base + i < 0x80:
                    iram[base + i - 0x30] = int(tok[1 + i], 16)
    return pc, inst, clks, bytes(iram), sent


def main():
    blob = bytearray()
    for name, flags in TESTS:
        code = assemble(name)
        pc, inst, clks, iram, sent = run_ucsim(name)
        if name == 'irq_order':
            # uCsim deviation: it vectors to the first interrupt straight after
            # SETB EA. The MCS-51 User's Manual (interrupt response, blocking
            # condition 3): after RETI or any write to IE or IP, at least one more
            # instruction executes before an interrupt is vectored to. uCsim
            # applies that after RETI but not after the IE write, so on the chip
            # each logged main counter is one higher: (n, n) not (n, n-1).
            log = bytearray(iram)
            assert list(log[0:12]) == [1, 0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5], log[:12].hex()
            for k in range(1, 12, 2):
                log[k] += 1
            iram = bytes(log)
            print('irq_order: corrected for the uCsim IE-write deviation')
        if clks % 12:
            raise SystemExit(f'{name}: {clks} clocks is not whole machine cycles')
        print(f'{name}: {len(code)} bytes, stops at PC=${pc:04X} after {inst} instructions, {clks // 12} cycles; '
              f'iram $30-$5F: {iram[:0x30].hex(" ")}; serial {sent!r}')
        blob += name.encode() + b'\0'
        blob += struct.pack('<BHHII', flags, len(code), pc, inst, clks // 12)
        blob += code
        blob += iram
        blob += bytes([len(sent)]) + sent
    (ROOT / 'tests' / 'asm_tests.bin').write_bytes(blob)
    (ROOT / 'tests' / 'asm_count.pico').write_text(f'#ASM_TEST_COUNT = {len(TESTS)}\n')
    print(len(TESTS), 'programs,', len(blob), 'bytes')


if __name__ == '__main__':
    main()
