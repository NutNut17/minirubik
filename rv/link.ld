ENTRY(_start)
SECTIONS {
  . = 0x0;
  .text : { *(.text.init) *(.text*) }
  . = 0x10000000;
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
}
