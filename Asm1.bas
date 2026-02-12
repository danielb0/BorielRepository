#include<nextlib.bas>
#define BBREAK
#define NEX
dim n as ubyte
cls
Print"Colour test"
while inkey$=""
    changecolour(n)
    n=n+1
wend

sub changecolour(attribute as ubyte)
    asm
        ;BREAK
        ld hl,$5800
        ld (hl),a
        ld de,$5801
        ld bc,767
        inc (hl)
        ldir
    end asm
    waitretrace(1)
end sub