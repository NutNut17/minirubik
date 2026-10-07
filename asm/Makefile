# LED template and hand-written solver for Ripes.
#
#   make cli            build_cli.s : no drawing, for the command line (--iret measurements)
#   make run            build + run build_cli.s on RV32_ISS, print the retired instructions
#   make suite       one program with 4 built-in cases (solved, short, sample, hardest); exit code = failures
#   make selftest       headless check of the LED drawing (fake LED symbols) frame by frame
#   make gui            build_gui.s : open this file in the Ripes GUI (LED matrix 35 x 25)
#   make tables.s       regenerate the solver tables (only needed when USE_TABLES=1)
#
# Variables:  PROC=RV32_5S   USE_TABLES=0 (the solver reads the tables, so the default is 1)
#             SOLVER=versions/solver_v2_registers.s   another solver file;  FULL=1 with SOLVER=versions/solver_dummy.s: selftest compares every frame   RVCC=cc (any C compiler that can run as a preprocessor)
#             STATE=<14 digits> LEN=<optimal length>   another test case (default: the LED demo case)
#   make test        run the whole test list (run_tests.sh) on RV32_ISS and RV32_5S
# An exported $RIPES in your shell is ignored on purpose (it may be a stale path); override with RIPES_BIN=...
RIPES_BIN ?= ../../Ripes/build/Ripes.app/Contents/MacOS/Ripes
RIPES      = $(RIPES_BIN)
RVCC       ?= riscv64-elf-gcc
PROC       ?= RV32_ISS
USE_TABLES ?= 1
SOLVER     ?= solver.s
FULL       ?= 0
CASE        = $(if $(STATE),-DTEST_STATE='"$(STATE)"') $(if $(LEN),-DTEST_LEN=$(LEN))
CPP         = $(RVCC) -E -P -x assembler-with-cpp -DUSE_TABLES=$(USE_TABLES) -DSOLVER_FILE='"$(SOLVER)"' -DSELFTEST_FULL=$(FULL) $(CASE)
SRCS        = main.s $(SOLVER) led_data.s $(if $(filter 1,$(USE_TABLES)),tables.s)

led_data.s expected_frames.txt: gen_led_data.py ../solver.c
	python3 gen_led_data.py

tables.s: ../ida ../ida.c ../ida_core.h ../records.h
	../ida --emit-asm $@
../ida: ../ida.c ../ida_core.h ../ida_core4.h ../records.h
	cc -std=c99 -O2 -Wall -Wextra -o $@ ../ida.c

cli build_cli.s: $(SRCS)
	$(CPP) -DRENDER=0 main.s > build_cli.s
gui build_gui.s: $(SRCS)
	$(CPP) -DRENDER=1 main.s > build_gui.s
build_selftest.s: $(SRCS)
	{ echo '    .equ LED_MATRIX_0_BASE, 0xf0000000'; $(CPP) -DRENDER=1 -DSELFTEST=1 main.s; } > $@

build_suite.s: $(SRCS)
	$(CPP) -DRENDER=0 -DSUITE=1 main.s > build_suite.s
suite: build_suite.s
	$(RIPES) --mode cli --src build_suite.s -t asm --proc $(PROC) --iret --cycles

run: build_cli.s
	$(RIPES) --mode cli --src build_cli.s -t asm --proc $(PROC) --iret --cycles --exectime
selftest: build_selftest.s
	$(RIPES) --mode cli --src build_selftest.s -t asm --proc $(PROC) --iret

test:
	./run_tests.sh $(TESTARGS)

clean:
	rm -f build_cli.s build_gui.s build_selftest.s build_suite.s tables.s ../ida

# the flat build files depend on the variables (STATE, LEN, USE_TABLES), not only on files: always rebuild them
.PHONY: cli gui run selftest suite test clean build_cli.s build_gui.s build_selftest.s build_suite.s
