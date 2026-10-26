    .syntax unified
    .arch armv7-a
    .eabi_attribute Tag_CPU_arch, 10
    .eabi_attribute Tag_THUMB_ISA_use, 2
    .thumb
@ libCarPlayUtils.so: the five AudioConverter* exports (stubs that always failed)
@ now forward to libleafia.so: dlopen("libleafia.so") + dlsym("lfa_<name>") and a
@ tail call with the caller's registers and stack untouched. If the library or symbol
@ is missing they return -6735 (kUnsupportedErr), the same as the old stubs.

    .section .t_new, "ax", %progbits
    .p2align 1
    .thumb_func
ent_new:
    push    {r0-r4, lr}
    movs    r4, #0
common:
    adr.w   r0, libname
    movs    r1, #0
    blx     dlopen_plt
    cbz     r0, fail
    adr.w   r1, names
    add.w   r1, r1, r4, lsl #5
    blx     dlsym_plt
    cbz     r0, fail
    mov     r12, r0
    pop.w   {r0-r4, lr}
    bx      r12
fail:
    pop.w   {r0-r4, lr}
    movw    r0, #0xe5b1
    movt    r0, #0xffff
    bx      lr
    .balign 4
libname:
    .asciz  "libleafia.so"
    .balign 4
names:
    .asciz  "lfa_AudioConverterNew"
    .org    names + 32
    .asciz  "lfa_AudioConverterDispose"
    .org    names + 64
    .asciz  "lfa_AudioConverterReset"
    .org    names + 96
    .asciz  "lfa_AudioConverterSetProperty"
    .org    names + 128
    .asciz  "lfa_AudioConverterFillComplexBuffer"
    .balign 4

    .section .t_dispose, "ax", %progbits
    .thumb_func
ent_dispose:
    push    {r0-r4, lr}
    movs    r4, #1
    b.w     common

    .section .t_reset, "ax", %progbits
    .thumb_func
ent_reset:
    push    {r0-r4, lr}
    movs    r4, #2
    b.w     common

    .section .t_setprop, "ax", %progbits
    .thumb_func
ent_setprop:
    push    {r0-r4, lr}
    movs    r4, #3
    b.w     common

    .section .t_fill, "ax", %progbits
    .thumb_func
ent_fill:
    push    {r0-r4, lr}
    movs    r4, #4
    b.w     common
