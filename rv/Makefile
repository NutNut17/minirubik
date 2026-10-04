# RV32I build of the solver: the C reference the hand-written assembly must beat.
#   make            generate tables.h on the host and build ida_rv.elf
#   make run        run on Ripes RV32_ISS (set PROC=RV32_5S for a pipelined model)
#   make size       section sizes: .rodata + .data + .bss is the static data (limit 131072 B)
RVCC   ?= riscv64-elf-gcc
CFLAGS  = -O2 -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -static -Wall -Wextra
RIPES  ?= ../../Ripes/build/Ripes.app/Contents/MacOS/Ripes
PROC   ?= RV32_ISS

all: ida_rv.elf

../ida: ../ida.c ../ida_core.h
	cc -std=c99 -O2 -Wall -Wextra -o $@ ../ida.c

tables.h: ../ida
	../ida --emit $@

ida_rv.elf: ida_rv.c start.S link.ld tables.h ../ida_core.h
	$(RVCC) $(CFLAGS) -T link.ld $(EXTRA) -o $@ start.S ida_rv.c

run: ida_rv.elf
	$(RIPES) --mode cli --src ida_rv.elf -t elf --proc $(PROC) --iret --cycles

size: ida_rv.elf
	riscv64-elf-size -A ida_rv.elf | grep -E '^\.(text|rodata|data|bss)'

clean:
	rm -f ida_rv.elf tables.h ../ida

.PHONY: all run size clean
