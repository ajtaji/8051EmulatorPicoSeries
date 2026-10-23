"""Programs built by PureMetal Forge's own 8051 target, with known results.

For each tests/programs/<name>.i8051:
  1. compile it with PureMetalForge.exe (target i8051) -> .bin, .hex, .slots.txt
  2. compute the expected value of each result variable here, in Python,
     from the program's algorithm (independent of every 8051 implementation)
  3. run the .hex in uCsim until the program's final jump-to-self, and check
     uCsim's XDATA against those values (so the program and the expectations
     are both right before the board ever sees them)
  4. record uCsim's instruction count and machine cycles to that point
Then tests/programs.bin carries, per program: the code image, the result
slots with expected values, and uCsim's instruction and cycle counts.

Run from the repository root:  py -3 tools/make_programs.py
"""
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROGRAMS = ROOT / 'tests' / 'programs'
COMPILER = Path(r'C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe')
UCSIM = Path(r'C:\PMFBuild\downloads\sdcc\extract\bin\ucsim_51.exe')


def primes():
    comp = [0] * 2000
    count = total = largest = 0
    for i in range(2, 2000):
        if not comp[i]:
            count += 1
            total += i
            largest = i
            for j in range(i + i, 2000, i):
                comp[j] = 1
    return {'count': (2, count), 'sum': (4, total), 'largest': (2, largest)}


def fibcrc():
    a, b = 0, 1
    for _ in range(30):
        a, b = b, a + b
    c = 0xFFFF
    for n in range(256):
        c ^= n << 8
        for _ in range(8):
            c = ((c << 1) ^ 0x1021) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
    x, y = 27720, 17160
    while y:
        x, y = y, x % y
    return {'fib30': (4, a), 'crc': (2, c), 'gcdv': (2, x)}


def sort():
    seed = 12345
    v = []
    for _ in range(48):
        seed = (seed * 25173 + 13849) & 0xFFFF
        v.append(seed & 0x3FFF)
    v.sort()
    check = sum((i + 1) * x for i, x in enumerate(v)) & 0xFFFF
    return {'check': (2, check), 'ordered': (2, 1), 'first': (2, v[0]), 'last': (2, v[-1])}


EXPECTED = {
    'i8051_basic': {'r1': (2, 13), 'r2': (2, 7), 'r3': (2, 30), 'r4': (2, 5535), 'r5': (2, 10), 'r6': (2, 14),
                    'r7': (2, 2), 'r8': (2, -14), 'r9': (2, -2), 'r10': (2, -14),
                    # Divide by zero gives quotient 0 and remainder 0: the compiler's ruling of
                    # 2026-07-29 (I8051Generator). The example's own comment predates it.
                    'r11': (2, 0), 'r12': (2, 0)},
    'i8051_flow': {'r1': (2, 1), 'r2': (2, 5), 'r3': (2, 15)},
    'i8051_array': {'r_const': (2, 77), 'r_var': (2, 220), 'r_sum': (2, 105), 'r_last': (2, -5), 'r_byte': (2, 56),
                    'r_longlo': (2, 7), 'r_fx': (2, 10), 'r_fsum': (2, 42), 'r_neigh': (2, 1234)},
    'primes': primes(),
    'fibcrc': fibcrc(),
    'sort': sort(),
}


def compile_program(name):
    src = PROGRAMS / f'{name}.i8051'
    hex_path = PROGRAMS / f'{name}.hex'
    r = subprocess.run([str(COMPILER), '--compile', str(src), '-S', '-o', str(hex_path)], capture_output=True,
                       text=True)
    if r.returncode != 0 or 'pmfc: OK' not in r.stdout:
        raise SystemExit(f'{name}: compile failed\n{r.stdout}\n{r.stderr}')
    slots = {}
    for line in (PROGRAMS / f'{name}.hex.slots.txt').read_text().splitlines():
        k, _, v = line.partition('=')
        slots[k.strip()] = int(v)
    return (PROGRAMS / f'{name}.bin').read_bytes(), slots


def run_ucsim(name):
    script = PROGRAMS / 'ucsim.tmp'
    stdin = PROGRAMS / 'ucsim_stdin.tmp'
    script.write_text('\n'.join([
        f'file "{(PROGRAMS / (name + ".hex")).as_posix()}"',
        'set option selfjump_stop 1',
        'run',
        'echo @@STATE',
        'state',
        'echo @@X',
        'dump /h xram 0 0x7ff 16',
        'echo @@END']) + '\n')
    stdin.write_text(f'exec "{script.as_posix()}"\nquit\n')
    with open(stdin) as f:
        out = subprocess.run([str(UCSIM), '-q', '-t', '8052'], stdin=f, capture_output=True, text=True,
                             timeout=600).stdout
    script.unlink()
    stdin.unlink()
    state = out[out.index('\n@@STATE'):out.index('\n@@X')]
    pc = int(re.search(r'PC= 0x([0-9a-fA-F]+)', state).group(1), 16)
    inst = int(re.search(r'Inst= (\d+)', state).group(1))
    clks = int(re.search(r'Total time since last reset= [0-9.]+ sec \((\d+) clks\)', state).group(1))
    xram = bytearray(0x800)
    for line in out[out.index('\n@@X'):out.index('\n@@END')].splitlines():
        tok = line.split()
        if len(tok) > 1 and tok[0].startswith('0x') and not line.startswith('dump'):
            base = int(tok[0], 16)
            for i in range(16):
                if 1 + i < len(tok) and re.fullmatch(r'[0-9a-f]{2}', tok[1 + i]) and base + i < 0x800:
                    xram[base + i] = int(tok[1 + i], 16)
    return pc, inst, clks, xram


def main():
    blob = bytearray()
    names = sorted(EXPECTED)
    for name in names:
        code, slots = compile_program(name)
        pc, inst, clks, xram = run_ucsim(name)
        if clks % 12:
            raise SystemExit(f'{name}: {clks} clocks is not whole machine cycles')
        checks = []
        for var, (width, value) in EXPECTED[name].items():
            addr = slots['global_' + var]
            got = int.from_bytes(xram[addr:addr + width], 'little')
            want = value & ((1 << (8 * width)) - 1)
            if got != want:
                raise SystemExit(f'{name}: uCsim has {var} = {got}, Python expects {want}')
            checks.append((addr, width, want))
        print(f'{name}: {len(code)} bytes, uCsim stops at PC=${pc:04X} after {inst} instructions, '
              f'{clks // 12} machine cycles; {len(checks)} results agree with Python')
        blob += name.encode() + b'\0'
        blob += struct.pack('<HHII', len(code), pc, inst, clks // 12)
        blob += code
        blob += bytes([len(checks)])
        for addr, width, want in checks:
            blob += struct.pack('<HBI', addr, width, want)
    (ROOT / 'tests' / 'programs.bin').write_bytes(blob)
    (ROOT / 'tests' / 'program_count.pico').write_text(f'#PROGRAM_COUNT = {len(names)}\n')
    print(len(names), 'programs,', len(blob), 'bytes')


if __name__ == '__main__':
    main()
