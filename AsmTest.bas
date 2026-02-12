'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)

asm

start:  DI
        LD E,0

loop:   LD A,E
        AND 7
        OUT ($FE),A      ; border colour
        INC E

        ; delay
        LD BC,20000
dly:    DEC BC
        LD A,B
        OR C
        JR NZ,dly

        ; SPACE test
        LD BC,$7FFE
        IN A,(C)
        AND 1            ; 0 when SPACE pressed
        JR NZ,loop

        DI
        ret
end asm
