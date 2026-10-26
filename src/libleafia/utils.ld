SECTIONS {
  .t_new 0x4554 : { *(.t_new) }
  .t_dispose 0x46c8 : { *(.t_dispose) }
  .t_reset 0x471c : { *(.t_reset) }
  .t_setprop 0x4764 : { *(.t_setprop) }
  .t_fill 0x4980 : { *(.t_fill) }
}
