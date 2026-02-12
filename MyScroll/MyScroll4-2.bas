'!org=32768
'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)

#include <NextLib.bas>

' -----------------------------
' NextReg helper (portable)
' -----------------------------
const PORT_NEXTREG_SEL as uinteger = $243B
const PORT_NEXTREG_DAT as uinteger = $253B

sub WriteNextReg(byval r as ubyte, byval v as ubyte)
    out PORT_NEXTREG_SEL, r
    out PORT_NEXTREG_DAT, v
end sub

' -----------------------------
' Assets / constants
' -----------------------------
const L2_START_16K as ubyte = 9
const PAL_SIZE     as uinteger = 512

' Sprite
const SPR_BYTES    as uinteger = $4000    ' 16K
const SPR_ID       as ubyte = 0
const SPR_PATTERN  as ubyte = 0

' -----------------------------
' Globals
' -----------------------------
dim pal(511) as ubyte
dim sprBuf(16383) as ubyte     ' safe 16K buffer (instead of $C000)

dim sprX as integer : dim sprY as integer
dim sprVX as integer : dim sprVY as integer

dim cx1 as integer : dim cy1 as integer
dim cx2 as integer : dim cy2 as integer
dim cvx as integer : dim cvy as integer

dim layerOver as ubyte
dim frame as uinteger

' -----------------------------
' Helpers
' -----------------------------
sub SetLayerOver(byval ord as ubyte)
    dim v as ubyte
    v = (ord SHL 2) OR 1
    WriteNextReg($15, v)
end sub

sub LoadLayer2_SL2()
    ' Set Layer2 start 16K bank
    WriteNextReg($12, L2_START_16K)

    ' L2_START_16K = 9  => base 8K bank = 18
    ' We must use constants in LoadSDBank so NextBuild can parse it.
    LoadSDBank("nutter.sl2", 0, 8192,     0, 18)
    LoadSDBank("nutter.sl2", 0, 8192,  8192, 19)
    LoadSDBank("nutter.sl2", 0, 8192, 16384, 20)
    LoadSDBank("nutter.sl2", 0, 8192, 24576, 21)
    LoadSDBank("nutter.sl2", 0, 8192, 32768, 22)
    LoadSDBank("nutter.sl2", 0, 8192, 40960, 23)
end sub



sub LoadLayer2Palette_PAL()
    LoadSD("nutter.pal", @pal(0), PAL_SIZE, 0)
    PalUpload(@pal(0), 256, 0, 0)
end sub


sub InitSystem()
    ' 28MHz
    WriteNextReg($07, 3)

    ' transparency
    WriteNextReg($14, 0)

    ' show Layer2
    ShowLayer2(1)
    CLS256(0)

    layerOver = 0
    SetLayerOver(layerOver)

    LoadLayer2Palette_PAL()
    LoadLayer2_SL2()



    cx1 = 10 : cy1 = 15
    cx2 = 250 : cy2 = 150
    cvx = 1   : cvy = 1

    ' NextLib clip functions generally want UBYTE parameters,
    ' so we pass via typed temporaries.
    dim ux1 as ubyte : dim ux2 as ubyte : dim uy1 as ubyte : dim uy2 as ubyte
    ux1 = cx1 : ux2 = cx2 : uy1 = cy1 : uy2 = cy2
    ClipLayer2(ux1, ux2, uy1, uy2)
    ClipSprite(ux1, ux2, uy1, uy2)

    ' Load/init sprites from safe RAM buffer
    LoadSD("spaceship.spr", @sprBuf(0), SPR_BYTES, 0)
    InitSprites(1, @sprBuf(0))

    sprX = 100 : sprY = 100
    sprVX = 1  : sprVY = 1
end sub

sub DrawStars()
    dim i as ubyte
    dim ry as ubyte
    dim rx as ubyte
    for i = 0 to 3
        ry = INT(RND * 24)
        rx = INT(RND * 32)
        print at ry, rx; "*";
    next i
end sub

sub UpdateClipWindow()
    cx1 = cx1 + cvx : cx2 = cx2 + cvx
    cy1 = cy1 + cvy : cy2 = cy2 + cvy

    if cx1 < 0 then
        cx1 = 0 : cx2 = cx1 + 240 : cvx = -cvx
    end if
    if cy1 < 0 then
        cy1 = 0 : cy2 = cy1 + 135 : cvy = -cvy
    end if
    if cx2 > 255 then
        cx2 = 255 : cx1 = cx2 - 240 : cvx = -cvx
    end if
    if cy2 > 191 then
        cy2 = 191 : cy1 = cy2 - 135 : cvy = -cvy
    end if

    dim ux1 as ubyte : dim ux2 as ubyte : dim uy1 as ubyte : dim uy2 as ubyte
    ux1 = cx1 : ux2 = cx2 : uy1 = cy1 : uy2 = cy2
    ClipLayer2(ux1, ux2, uy1, uy2)
    ClipSprite(ux1, ux2, uy1, uy2)
end sub

sub UpdateBouncingSprite()
    sprX = sprX + sprVX
    sprY = sprY + sprVY

    if sprX > 319 then sprVX = -sprVX : sprX = 319
    if sprX < 0   then sprVX = -sprVX : sprX = 0

    if sprY > 191 then sprVY = -sprVY : sprY = 191
    if sprY < 0   then sprVY = -sprVY : sprY = 0

    ' UpdateSprite wants (x as UINTEGER, y as UBYTE, ...)
    dim ux as uinteger
    dim uy as ubyte
    ux = sprX
    uy = sprY
    UpdateSprite(ux, uy, SPR_ID, SPR_PATTERN, $10, 0)
end sub

' -----------------------------
' Main
' -----------------------------
InitSystem()

border 0 : paper 0 : ink 7 : cls

do
    DrawStars()
    UpdateClipWindow()
    UpdateBouncingSprite()

    frame = frame + 1
    if (frame and 31) = 0 then
        if layerOver = 0 then
            layerOver = 2
        elseif layerOver = 2 then
            layerOver = 4
        else
            layerOver = 0
        end if
        SetLayerOver(layerOver)

        WriteNextReg($4A, INT(RND * 255))
    end if

    WaitRetrace(1)
loop while inkey$ = ""

RemoveSprite(SPR_ID, 0)
stop
