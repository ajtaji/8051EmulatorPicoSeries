"""Writes demo/pm51_demo.pm51: the PM51 board demo, a PureMetal program for
PureMetal Forge's PM51 display board (an 8052 target, extension .pm51). The 8051 target has no DataSection, so the
tables go in a DataSection (code memory, read with MOVC) that InitTables() copies into XDATA.

The tune is original (written for this demo): four bars in A minor,
Am - F - C - G, lead on a square voice, bass on a triangle, drums on noise.

  py -3 demo/make_demo.py
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent

NOTES = {'C': -9, 'C#': -8, 'D': -7, 'D#': -6, 'E': -5, 'F': -4, 'F#': -3, 'G': -2, 'G#': -1, 'A': 0, 'A#': 1, 'B': 2}


def note(name):
    """A MIDI note number (A4 = 69); '-' holds (0), '.' rests (1)."""
    if name == '-':
        return 0
    if name == '.':
        return 1
    n, octave = name[:-1], int(name[-1])
    return 69 + NOTES[n] + 12 * (octave - 4)


def freq(midi):
    return round(440 * 2 ** ((midi - 69) / 12))


LEAD = """A4 - C5 - E5 - D5 C5 B4 - A4 - - - E4 -
          F4 - A4 - C5 - B4 A4 G4 - F4 - - - C5 -
          E5 - G5 - E5 - D5 C5 D5 - E5 - - - G4 -
          D5 - B4 - G4 - A4 B4 D5 - C5 - B4 - . -""".split()
BASS = """A2 - A3 - A2 - A3 - A2 - A3 - E2 - G2 -
          F2 - F3 - F2 - F3 - F2 - F3 - C3 - E3 -
          C3 - C4 - C3 - C4 - C3 - C4 - G2 - B2 -
          G2 - G3 - G2 - G3 - G2 - G3 - D3 - B2 -""".split()
DRUM = [1 if s % 8 == 0 else 2 if s % 8 == 4 else 3 if s % 2 == 1 else 0 for s in range(64)]
assert len(LEAD) == 64 and len(BASS) == 64

MESSAGE = ("     PUREMETAL 8051 ON THE PM51 BOARD ... COMPILED BY PUREMETAL FORGE, "
           "RUN BY A COMPUTED-GOTO MCS-51 CORE ON A RASPBERRY PI PICO ... "
           "ARROWS STEER THE FIRST BALL, A TURNS THE SCROLL, B MUTES THE MUSIC ...     ")


def rgb332(r, g, b):
    return (r & 0xE0) | ((g >> 3) & 0x1C) | (b >> 6)


def rainbow(i, n=32):
    import colorsys
    r, g, b = colorsys.hsv_to_rgb(i / n, 1.0, 1.0)
    return rgb332(int(r * 255), int(g * 255), int(b * 255))


# Where the tables live: the board's free XDATA RAM (the program reads them
# with PeekA). One constant PokeA per byte is the smallest code that sets one.
T_LEAD, T_BASS, T_DRUM, T_FREQ, T_RAINBOW, T_MSG = 0xE000, 0xE040, 0xE080, 0xE100, 0xE200, 0xE300


def main():
    data = {}
    for i, n in enumerate(LEAD):
        data[T_LEAD + i] = note(n)
    for i, n in enumerate(BASS):
        data[T_BASS + i] = note(n)
    for i, d in enumerate(DRUM):
        data[T_DRUM + i] = d
    used = sorted({note(n) for n in LEAD + BASS if note(n) > 1})
    for m in used:
        f = freq(m)
        data[T_FREQ + 2 * m] = f & 255
        data[T_FREQ + 2 * m + 1] = f >> 8
    for i in range(32):
        data[T_RAINBOW + i] = rainbow(i)
    for i, ch in enumerate(MESSAGE):
        data[T_MSG + i] = ord(ch)
    # The DataSection, in InitTables' order: lead, bass, drums, the 256-byte
    # frequency table, the rainbow, the message.
    blob = []
    for base, n in ((T_LEAD, 64), (T_BASS, 64), (T_DRUM, 64), (T_FREQ, 256), (T_RAINBOW, 32), (T_MSG, len(MESSAGE))):
        blob += [data.get(base + i, 0) for i in range(n)]
    lines = ['  Data.a ' + ','.join(str(v) for v in blob[i:i + 32]) for i in range(0, len(blob), 32)]
    src = (HERE / 'pm51_demo.template').read_text()
    src = src.replace('@@MSGLEN@@', str(len(MESSAGE))).replace('@@TABLES@@', '\n'.join(lines))
    (HERE / 'pm51_demo.pm51').write_text(src, newline='\n')
    print('demo/pm51_demo.pm51 written,', len(blob), 'table bytes')


if __name__ == '__main__':
    main()
