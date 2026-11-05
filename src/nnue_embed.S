/* Generated-link input: embeds the repository's original quantised-v14.bin. */
.section .rodata
.balign 64
.global g_kociolek_nnue_start
.type g_kociolek_nnue_start, %object
g_kociolek_nnue_start:
.incbin "quantised-v14.bin"
.global g_kociolek_nnue_end
g_kociolek_nnue_end:
.size g_kociolek_nnue_start, g_kociolek_nnue_end-g_kociolek_nnue_start
.section .note.GNU-stack,"",%progbits
