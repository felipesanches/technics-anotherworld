# KN5000 programs as style converters (.CNV)

The KN5000's DISK MENU > STYLE CONVERT loads a `.CNV` file from the floppy and runs it on the main
CPU, with the stock firmware. This directory holds programs that use that door.

## The mechanism (v7 disassembly, `technics-roms-disasm/v7/maincpu/sequencer/accompaniment_engine.s`)

- STYLE CONVERT lists `*.CNV` on the floppy (STYLE TYPE SELECT); OK loads the chosen one.
- `StylCnvModl_OK_SelectItem` opens it, zeroes 192 KB at `0x80000`, reads the whole file there,
  clears the flag at `0xFFBFE`, writes `0xFF` to the mailbox byte `0xFFC00` and 0 to `0xFFC01`, and
  jumps to `0x80000` (`TableData_JumpToEntry`), with a return address on the stack.
- The converter returns with a request in `0xFFC00`. `FloppyState_Dispatch` serves it. Request 1
  copies the string at `0xFFC01`, writes `0xFF` and calls the converter again at once
  (`StylCnv_ClearAndFinalize`, `StylCnv_FinalizeAndCheckStatus`). Request `0xFE` ends the run: the
  firmware shows "Continue Next?" (title `0x16`). Requests 0, 2, 3, 4 and 5 are the converter
  services (store, names, file loading, file I/O, text); they are the KN7000's request codes.

A converter is TLCS-900/H code linked at `0x80000`, assembled with ASL (`cpu 96c141`).

## probes/hello: the smallest converter (2026-10-22)

`hello.asm` (80 bytes) counts its calls at `0xA0004`, writes `CNV5` at `0xA0000`, fills LCD rows
100-139 (VRAM `0x1A0000`, 320 bytes a row) with the count's low byte, and answers request 1 until the
600th call, then `0xFE`.

Measured in MAME (published `kn7000` binary, md5 `7f1205b746cde8c45781ba9eed5a2565`, machine
`kn5000`, default firmware): STYLE TYPE SELECT lists `HELLO.CNV`; after OK (right button 4) the
signature is there and the count climbs about 97 calls per second (20 at 1.0 s after OK, 310 at
4.0 s, 600 at 7.0 s), the band is drawn over the firmware's screen, and after the 600th call the
mailbox reads `0xFE` and the firmware shows "Continue Next?".

```sh
cd probes/hello
~/compartilhado/tools/asl/asl -q -w -L -olist hello.lst hello.asm -o hello.p
~/compartilhado/tools/asl/p2bin hello.p HELLO.CNV -r 0x80000-\$
python3 -I ../../tools/mkfloppy.py hello.img HELLO HELLO.CNV
cd .. && ./run.sh ~/compartilhado/tmp/kn5000cnv/run1 hello/hello.img \
    "25:DISK;28:L3;33:R4;34:snap;35:snap;37:snap;40:snap;45:snap;50:quit"
```

## Tools

| file                | what it does                                                                                           |
|---------------------|--------------------------------------------------------------------------------------------------------|
| `tools/mkfloppy.py` | `mkfloppy.py OUT.img LABEL FILE...`: a FAT12 1.44 MB image, files contiguous in the root, reproducible |
| `probes/seq.lua`    | presses panel buttons on a schedule (`SEQ="t:button;t:snap;t:quit"`), reports the converter's state    |
| `probes/run.sh`     | `run.sh OUT FLOPPY SEQ`: one KN5000 run in the published emulator with that floppy                     |
