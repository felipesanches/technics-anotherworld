# kn5000cnv/Makefile -- Another World for the KN5000 as a style converter: AW.CNV and its floppy.
#
#   make AW_DATA=<dir with the MS-DOS release's MEMLIST.BIN + BANK01..0D>
#
# build/AW.CNV       the program (DISK MENU > STYLE CONVERT loads it at 0x80000)
# build/files/       AWnn.BIN, the game's resources, one per file
# build/aw5000.img   a 1.44 MB DOS floppy holding both (tools/mkfloppy.py)
# The game data is not in this repository; it is extracted from your own copy.

AW_DATA     ?= ../../MSDOS
ASL_DIR     ?= ../../tools/asl
DISASM_REPO ?= ../../technics-roms-disasm
PYTHON      ?= python3
# START_PART=03E82h starts the game in that part instead of the intro (test builds only)
START_PART  ?=

ASL   := $(ASL_DIR)/asl
P2BIN := $(ASL_DIR)/p2bin
INCS  := -i src -i build -i ../src -i ../src/includes -i $(DISASM_REPO) -i $(DISASM_REPO)/archive/asl \
         -i $(DISASM_REPO)/archive/asl/shared

all: build/aw5000.img

build/res/memlist.tsv: ../kn7000/tools/aw_extract.py $(AW_DATA)/MEMLIST.BIN
	mkdir -p build/res
	$(PYTHON) -I ../kn7000/tools/aw_extract.py $(AW_DATA) build/res

build/awfiles.inc: tools/make_awdisk.py build/res/memlist.tsv
	$(PYTHON) -I tools/make_awdisk.py build/res build

build/aw_cnv.p: src/aw_cnv.asm src/cnv_platform.asm src/cnv_ram.inc build/awfiles.inc ../src/another_world_vm.asm ../src/vm_ram.inc
	$(ASL) -w -q -L -D TARGET_CNV $(if $(START_PART),-D START_PART=$(START_PART)) -olist build/aw_cnv.lst $(INCS) \
		src/aw_cnv.asm -o $@

build/AW.CNV: build/aw_cnv.p
	$(P2BIN) $< $@ -r 0x80000-\$$ -l 0
	$(PYTHON) -I tools/lst2sym.py build/aw_cnv.lst build/aw_cnv.sym
	@ls -l $@

build/aw5000.img: build/AW.CNV build/awfiles.inc tools/mkfloppy.py
	$(PYTHON) -I tools/mkfloppy.py $@ AW5000 build/AW.CNV $$(ls build/files/AW*.BIN)

clean:
	rm -rf build

.PHONY: all clean
