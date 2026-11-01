# The desktop 8051 emulator - Windows and Linux

One source, `mcs51_desktop.pb`, for both. Everything the operating system
provides - the window, OpenGL, drawing, keys held, the sound card, full
screen, the pointer, the clock, the work area, the display scale - comes from
the **Neon Arcade Display Engine** (its HOST SERVICES in `GlUtilities.pbi`).
The emulator calls no OS function itself.

You need **PureBasic 6.41, x64, C back end** and the engine, cloned beside this
repository:

```
git clone https://github.com/ajtaji/8051EmulatorPicoSeries
git clone https://github.com/ajtaji/Neon-Arcade-Dispay-Engine
```

The source finds the engine at `../../Neon-Arcade-Dispay-Engine/` relative to
`desktop/`. Set `NEON_ENGINE_DIR` (with a trailing slash) for another place.

## Windows

```
powershell -File desktop\build.ps1 -Compiler "<PureBasic>\Compilers\pbcompilerc.exe"
```

This builds `mcs51_desktop.exe` (the window) and `mcs51_console.exe` (the same
program with a console). It compiles with `/THREAD /DPIAWARE /OPTIMIZER`.

```
desktop\mcs51_desktop.exe demo\pm51_demo.hex --run
desktop\mcs51_console.exe --test
desktop\mcs51_console.exe --bench
desktop\mcs51_console.exe --frames 600 demo\pm51_demo.hex --wav out.wav
```

## Linux

```
export PUREBASIC_HOME=~/purebasic          # the PureBasic for Linux install
sh desktop/build.sh
```

This builds `desktop/mcs51_desktop` (`pbcompilerc -t -z`). On Linux there is
no separate console format, so this one program both opens the window and runs
the console modes in the terminal:

```
desktop/mcs51_desktop demo/pm51_demo.hex --run
desktop/mcs51_desktop --test
desktop/mcs51_desktop --bench
desktop/mcs51_desktop --frames 600 demo/pm51_demo.hex --wav out.wav
```

It runs on X11, or on XWayland under a Wayland desktop. The engine sets
`GDK_BACKEND=x11` itself. Sound goes to ALSA's `default` device (PulseAudio or
PipeWire behind it on most desktops). It needs the GTK 3, X11, Mesa GL and ALSA
runtime libraries.

Keys are PureBasic `#PB_Shortcut_` codes, which are virtual-key codes on
Windows and X keysyms on Linux. The table in `controls.pbi` means the same keys
on both.

The window's command-line options (`--show-tests`, `--screenshot`,
`--fullscreen-test`, `--mouse-log`, ...) are listed at the top of
`mcs51_desktop.pb`.
