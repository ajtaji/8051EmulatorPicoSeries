"""Single-instruction vectors for the 8051 core, with uCsim as the oracle.

No published single-instruction test suite exists for the MCS-51, so the
expected states come from uCsim 0.8.15 (ucsim_51, the simulator SDCC's own
regression tests run on), simulating an 8052. Each vector is one random
machine state plus one instruction; uCsim runs that instruction and its
internal RAM, SFRs and the touched XDATA are read back.

This file decodes the instruction set on its own (operand formats, effective
addresses) and shares nothing with tools/generate.py.

Oracle correction, applied to every vector: uCsim leaves PSW.P as written by
an instruction that writes PSW (and as set from the command line) until ACC
next changes. On the chip P is recomputed from ACC every machine cycle, so
the expected PSW always carries parity(final ACC). Every vector where this
changed uCsim's answer is counted and reported.

Run from the repository root:  py -3 tools/make_vectors.py [ucsim_51.exe]
"""
import random
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UCSIM = Path(sys.argv[1] if len(sys.argv) > 1 else r'C:\PMFBuild\downloads\sdcc\extract\bin\ucsim_51.exe')
OUT_BIN = ROOT / 'tests' / 'vectors.bin'
OUT_COUNT = ROOT / 'tests' / 'vector_count.pico'

rng = random.Random(0x8051C0DE)

# SFRs a vector may address directly: the CPU's own registers, and timer
# registers whose timers are stopped. Ports, SBUF, IE, IP, TCON, SCON and
# PCON are left to the program-level tests: touching them in a one-step
# vector would start transmissions or interrupts in the oracle.
SAFE_SFR = [0x81, 0x82, 0x83, 0xD0, 0xE0, 0xF0, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0xCA, 0xCB, 0xCC, 0xCD]
CPU_SFR = {0x81, 0x82, 0x83, 0xD0, 0xE0, 0xF0}
EXTRA_SFR = [a for a in SAFE_SFR if a not in CPU_SFR]
SAFE_BIT_BYTES = [0xD0, 0xE0, 0xF0]


def parity(v):
    return bin(v & 255).count('1') & 1


def lcg_fill(seed):
    """The board regenerates internal RAM from the seed with the same LCG."""
    x = seed
    out = []
    for _ in range(256):
        x = (x * 1103515245 + 12345) & 0xFFFFFFFF
        out.append((x >> 16) & 255)
    return out


def operands(op):
    """Operand formats of each opcode, in instruction-byte order."""
    lo, hi = op & 15, op >> 4
    if lo == 1:
        return ['addr11']
    if op in (0x02, 0x12):
        return ['addr16']
    if op == 0x90:
        return ['imm16']
    if op == 0x85:
        return ['dir', 'dir']
    if op in (0x10, 0x20, 0x30):
        return ['bit', 'rel']
    if op in (0x40, 0x50, 0x60, 0x70, 0x80):
        return ['rel']
    if op in (0x72, 0x82, 0x92, 0xA0, 0xA2, 0xB0, 0xB2, 0xC2, 0xD2):
        return ['bit']
    if op in (0x43, 0x53, 0x63, 0x75):
        return ['dir', 'imm']
    if op == 0xB4 or 0xB6 <= op <= 0xBF:
        return ['imm', 'rel']
    if op in (0xB5, 0xD5):
        return ['dir', 'rel']
    if 0xD8 <= op <= 0xDF:
        return ['rel']
    if op in (0x05, 0x15, 0x42, 0x52, 0x62, 0xC0, 0xD0, 0xC5, 0xE5, 0xF5) or (0x86 <= op <= 0x8F) or (0xA6 <= op <= 0xAF):
        return ['dir']
    if hi in (2, 3, 4, 5, 6, 9) and lo == 5:
        return ['dir']
    if hi in (2, 3, 4, 5, 6, 7, 9) and lo == 4:
        return ['imm']
    if 0x76 <= op <= 0x7F:
        return ['imm']
    return []


def pick_dir():
    if rng.random() < 0.75:
        return rng.randrange(0x80)
    return rng.choice(SAFE_SFR)


def pick_bit():
    if rng.random() < 0.75:
        return rng.randrange(0x80)
    return rng.choice(SAFE_BIT_BYTES) + rng.randrange(8)


ARITH = {0xD4, 0xA4, 0x84} | {r + l for r in (0x20, 0x30, 0x90) for l in range(4, 16)}


def make_case(op):
    seed = rng.randrange(1, 1 << 32)
    iram = lcg_fill(seed)
    acc, b, sp = rng.randrange(256), rng.randrange(256), rng.randrange(256)
    psw = rng.randrange(256) & 0xFE
    dpl, dph = rng.randrange(256), rng.randrange(256)
    r = rng.random()
    if r < 0.05:
        pc = 0xFFFF
    elif r < 0.10:
        pc = 0xFFFE
    else:
        pc = rng.randrange(0x10000)
    body = [op]
    fmt = operands(op)
    for kind in fmt:
        if kind == 'dir':
            body.append(pick_dir())
        elif kind == 'bit':
            body.append(pick_bit())
        elif kind in ('imm', 'rel', 'addr11'):
            body.append(rng.randrange(256))
        elif kind in ('addr16', 'imm16'):
            body += [rng.randrange(256), rng.randrange(256)]
    bank = psw & 0x18
    # Steer the interesting outcomes so each appears often enough.
    if op == 0x84 and rng.random() < 0.15:
        b = 0
    if op in (0x60, 0x70) and rng.random() < 0.4:
        acc = 0
    if (op == 0xB4 or 0xB6 <= op <= 0xBF) and rng.random() < 0.3:
        if op == 0xB4:
            body[1] = acc
        elif op >= 0xB8:
            body[1] = iram[bank + (op & 7)]
        else:
            body[1] = iram[iram[bank + (op & 1)]]
    if 0xD8 <= op <= 0xDF and rng.random() < 0.3:
        iram[bank + (op & 7)] = 1
    if op == 0xD5 and body[1] < 0x80 and rng.random() < 0.3:
        iram[body[1]] = 1
    psw |= parity(acc)
    pokes = []          # (space 0 code / 1 xdata, address, value)
    xread = []          # XDATA addresses whose final value is expected
    length = len(body)
    code_addrs = {(pc + i) & 0xFFFF for i in range(length)}
    after = (pc + length) & 0xFFFF
    dptr = (dph << 8) | dpl
    if op == 0x93 or op == 0x83:
        tgt = (acc + (dptr if op == 0x93 else after)) & 0xFFFF
        if tgt not in code_addrs:
            pokes.append((0, tgt, rng.randrange(256)))
    if op in (0xE0, 0xF0, 0xE2, 0xE3, 0xF2, 0xF3):
        addr = dptr if op in (0xE0, 0xF0) else (0xFF << 8) | iram[bank + (op & 1)]
        pokes.append((1, addr, rng.randrange(256)))
        xread.append(addr)
    return dict(seed=seed, iram=iram, pc=pc, body=body, acc=acc, b=b, psw=psw, sp=sp, dpl=dpl, dph=dph,
                pokes=pokes, xread=xread)


def ucsim_script(cases):
    # uCsim refuses to run an instruction whose stack access wraps past $FF;
    # the chip just wraps SP. Turn that check off.
    lines = ['set error stack off', 'set error non-classified off']
    for idx, c in enumerate(cases):
        lines.append('reset')
        for start in range(0, 256, 32):
            lines.append(f'set mem iram {start} ' + ' '.join(str(v) for v in c['iram'][start:start + 32]))
        for i, v in enumerate(c['body']):
            lines.append(f'set mem rom {(c["pc"] + i) & 0xFFFF} {v}')
        for space, addr, v in c['pokes']:
            lines.append(f'set mem {"rom" if space == 0 else "xram"} {addr} {v}')
        for adr, key in [(0xE0, 'acc'), (0xF0, 'b'), (0x81, 'sp'), (0x82, 'dpl'), (0x83, 'dph'), (0xD0, 'psw')]:
            lines.append(f'set mem sfr {adr} {c[key]}')
        lines.append(f'pc {c["pc"]}')
        lines.append(f'echo @@S{idx}')
        lines.append('step')
        lines.append(f'echo @@D{idx}')
        lines.append('dump /h iram 0 0xff 16')
        lines.append('dump /h sfr 0x80 0xff 16')
        lines.append(f'echo @@X{idx}')
        for addr in c['xread']:
            lines.append(f'dump /h xram {addr} {addr} 16')
        lines.append(f'echo @@E{idx}')
    lines.append('quit')
    return '\n'.join(lines) + '\n'


def parse_hex_lines(lines, start, count):
    data = {}
    for line in lines:
        tok = line.split()
        if not tok or not tok[0].startswith('0x'):
            continue
        base = int(tok[0], 16)
        for i in range(16):
            a = base + i
            if a >= start + count or 1 + i >= len(tok):
                break
            data[a] = int(tok[1 + i], 16)
    return [data[a] for a in range(start, start + count)]


def run_ucsim(cases):
    # Fed through stdin, uCsim echoes the input in chunks interleaved with
    # the output. Run from a script with `exec`, each command is echoed on
    # its own line just before its own output.
    script_path = ROOT / 'tests' / 'ucsim_script.tmp'
    stdin_path = ROOT / 'tests' / 'ucsim_stdin.tmp'
    script_path.write_text(ucsim_script(cases).replace('quit\n', ''))
    stdin_path.write_text(f'exec "{script_path.as_posix()}"\nquit\n')
    with open(stdin_path) as stdin:
        out = subprocess.run([str(UCSIM), '-q', '-t', '8052'], stdin=stdin, capture_output=True, text=True,
                             timeout=3600).stdout.splitlines()
    script_path.unlink()
    stdin_path.unlink()
    out = [l for l in out if not re.match(r'(echo|dump|set|pc|step|reset) ', l + ' ')]
    pos = {}
    for i, line in enumerate(out):
        if re.fullmatch(r'@@[SDXE]\d+', line.strip()):
            pos[line.strip()] = i
    results = []
    for idx in range(len(cases)):
        s, d, x, e = pos[f'@@S{idx}'], pos[f'@@D{idx}'], pos[f'@@X{idx}'], pos[f'@@E{idx}']
        step = '\n'.join(out[s:d])
        m = re.search(r'Stop at 0x([0-9a-fA-F]+).*?stepped (\d+) ticks', step)
        if not m:
            raise SystemExit(f'case {idx}: no step result:\n{step}')
        dumps = out[d + 1:x]
        iram = parse_hex_lines(dumps[:16], 0, 256)
        sfr = parse_hex_lines(dumps[16:24], 0x80, 128)
        xs = []
        for k, addr in enumerate(cases[idx]['xread']):
            line = out[x + 1 + k].split()
            xs.append(int(line[1], 16))
        results.append(dict(pc=int(m.group(1), 16) & 0xFFFF, ticks=int(m.group(2)), iram=iram, sfr=sfr, xdata=xs))
    return results


def main():
    if not UCSIM.exists():
        raise SystemExit(f'uCsim not found: {UCSIM}')
    cases = []
    for op in range(256):
        if op == 0xA5:
            continue
        n = 64 if op in ARITH else 24
        for _ in range(n):
            cases.append(make_case(op))
    results = []
    for start in range(0, len(cases), 500):
        results += run_ucsim(cases[start:start + 500])
        print('uCsim', start + len(results[start:]), 'of', len(cases), flush=True)
    blob = bytearray()
    parity_fixed = 0
    other_sfr = 0
    for c, r in zip(cases, results):
        sfr = r['sfr']
        f_acc, f_b, f_psw = sfr[0xE0 - 0x80], sfr[0xF0 - 0x80], sfr[0xD0 - 0x80]
        f_sp, f_dpl, f_dph = sfr[0x81 - 0x80], sfr[0x82 - 0x80], sfr[0x83 - 0x80]
        fixed = (f_psw & 0xFE) | parity(f_acc)
        if fixed != f_psw:
            parity_fixed += 1
        # Every SFR outside the CPU's registers must be where reset put it,
        # except the stopped timer registers a vector may have written.
        init_extra = {a: 0 for a in EXTRA_SFR}
        changed = []
        for a in range(0x80, 0x100):
            if a in CPU_SFR:
                continue
            v = sfr[a - 0x80]
            if a in init_extra:
                if v != init_extra[a]:
                    changed.append((a, v))
        if r['ticks'] % 12:
            raise SystemExit(f'odd tick count {r["ticks"]}')
        cycles = r['ticks'] // 12
        idiff = [(a, v) for a, v in enumerate(r['iram']) if v != c['iram'][a]]
        blob += struct.pack('<IH', c['seed'], c['pc'])
        blob += bytes([len(c['body'])] + c['body'])
        blob += bytes([c['acc'], c['b'], c['psw'], c['sp'], c['dpl'], c['dph']])
        blob += bytes([len(c['pokes'])])
        for space, addr, v in c['pokes']:
            blob += struct.pack('<BHB', space, addr, v)
        blob += struct.pack('<H', r['pc'])
        blob += bytes([f_acc, f_b, fixed, f_sp, f_dpl, f_dph, cycles])
        blob += bytes([len(idiff)])
        for a, v in idiff:
            blob += bytes([a, v])
        blob += bytes([len(changed)])
        for a, v in changed:
            blob += bytes([a, v])
        blob += bytes([len(c['xread'])])
        for addr, v in zip(c['xread'], r['xdata']):
            blob += struct.pack('<HB', addr, v)
        other_sfr += len(changed)
    OUT_BIN.parent.mkdir(exist_ok=True)
    OUT_BIN.write_bytes(blob)
    OUT_COUNT.write_text(f'#VECTOR_COUNT = {len(cases)}\n#VECTOR_BYTES = {len(blob)}\n')
    print(len(cases), 'vectors,', len(blob), 'bytes;', parity_fixed, 'PSW.P corrections;', other_sfr,
          'timer-register writes')


if __name__ == '__main__':
    main()
