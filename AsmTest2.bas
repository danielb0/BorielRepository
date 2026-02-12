'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)
#include<NextLib.bas>
#define BBREAK

asm

        DI
        LD E,0
        EI

LOOP:
        HALT

        LD A,E
        OUT (254),A

        INC E
        LD A,E
        BREAK
        AND 7
        LD E,A

        CALL SPACEDOWN
        JR NZ,LOOP
        RET

SPACEDOWN:
        LD BC,$7FFE
        IN A,(C)
        AND 1
        ret
end asm
