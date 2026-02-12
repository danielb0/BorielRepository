'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)

declare function GetAttribute(x as ubyte, y as ubyte) as ubyte

dim n as ubyte
cls
print at 10,8;paper 3;ink 1;bright 1;"X"
print at 0,0; GetAttribute(8,10)

function GetAttribute(x as ubyte,y as ubyte) as ubyte
    asm
        ld hl,$5800
        ld a,(ix+7)
        ld b,a
        ld de,32
calcy:
        add hl,de
        djnz calcy
        ld a,(ix+5)
        ld d,0
        ld e,a
        add hl,de
        ld a,(hl)
    end asm
end function