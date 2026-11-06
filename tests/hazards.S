    .section .text
    .globl _start
_start:
# forwarding
    addi  x1, x0, 5
    addi  x2, x1, 3
    add   x3, x1, x2
    sub   x4, x3, x1
    add   x4, x4, x4
    addi  x4, x4, 1
    addi  x4, x4, 1
    xor   x5, x4, x3
    addi  x0, x0, 99
    add   x6, x0, x1
    lui   x7, 0xABCDE
    addi  x7, x7, -1
    auipc x8, 0
    srai  x9, x7, 4
    srli  x10, x7, 4
    slli  x11, x1, 31
    slt   x12, x11, x1
    sltu  x13, x11, x1
    sltiu x14, x1, -1

# loads, stores and load-use stalls
    la    x20, data_buf
    sw    x7, 0(x20)
    lw    x21, 0(x20)
    addi  x22, x21, 1
    lw    x23, 0(x20)
    add   x24, x1, x23
    lw    x25, 0(x20)
    sw    x25, 4(x20)
    lw    x26, 4(x20)
    addi  x26, x20, 16
    sw    x1, 0(x26)
    lw    x26, 4(x20)
    nop
    add   x27, x26, x1
    sb    x7, 8(x20)
    sb    x1, 9(x20)
    sh    x7, 10(x20)
    lb    x28, 8(x20)
    lbu   x29, 8(x20)
    lh    x30, 10(x20)
    lhu   x31, 10(x20)
    lw    x15, 8(x20)
    lw    x16, 0(x20)
    beq   x16, x7, 1f
    addi  x17, x0, 111
1:
    li    x5, 0
# loops, so the predictor can learn
    li    x6, 20
loop1:
    addi  x5, x5, 1
    bne   x5, x6, loop1

    li    x5, 0
    li    x8, 0
outer:
    li    x9, 0
inner:
    addi  x8, x8, 1
    addi  x9, x9, 1
    blt   x9, x6, inner
    addi  x5, x5, 1
    li    x10, 5
    bltu  x5, x10, outer

# every branch type
    li    x11, -3
    li    x12, 4
    bge   x11, x12, bad
    bgeu  x11, x12, 2f
    j     bad
2:  blt   x12, x11, bad
    bltu  x12, x11, 3f
    j     bad
3:  addi  x13, x11, 3
    beq   x13, x0, 4f
    j     bad
4:
    li    x10, 0
# calls and returns
    li    x18, 6
call_loop:
    jal   ra, func
    addi  x18, x18, -1
    bnez  x18, call_loop
    la    x19, tbl_target
    jalr  x0, 0(x19)
    j     bad
tbl_target:
    jal   x0, done

func:
    addi  x10, x10, 7
    ret

bad:
    li    x31, 0xBAD
    j     bad

done:
    li    gp, 1
write_tohost:
    sw    gp, tohost, t5
    j     write_tohost

    .section .tohost, "aw"
    .align 6
    .globl tohost
tohost:   .dword 0
    .globl fromhost
fromhost: .dword 0

    .section .data
    .align 4
data_buf: .space 64
