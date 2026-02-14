'!org=32768
'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)
#define NEX
#include <NextLib.bas>

'------------------------------------------------------------
' ZX Spectrum Next demo (Boriel ZX Basic + NextLib)
'
' Features:
'   - Layer2 256x192 8-bit bitmap background (MG.nxi) + 9-bit palette (MG.nxp)
'   - ULA/Layer 1,1 starfield using ULANext 256-colour palette + clipping
'   - Sprite (spaceship.spr) with clipping and layer priority toggling
'   - Layer2 and ULA pixel scrolling
'
' Assets:
'   - MG.nxi        (Layer2 image, loaded via LoadSDBank)
'   - MG.nxp        (Layer2 9-bit palette, 512 bytes, streamed via NextReg $44)
'   - spaceship.spr (+3DOS CODE file; skip 128-byte header)
'------------------------------------------------------------

declare function ReadNextReg(byval r as ubyte) as ubyte

const PORT_NEXTREG_SEL as uinteger = $243B
const PORT_NEXTREG_DAT as uinteger = $253B

'------------------------------------------------------------
' Constants / buffers
'------------------------------------------------------------
const L2_START_16K  as ubyte    = 9
const PAL_SIZE      as uinteger = 512

' spaceship.spr: +3DOS CODE header + sprite pattern bytes
const SPR_FILE_SKIP  as uinteger = 128
const SPR_DATA_BYTES as uinteger = 512   ' 2 x 256-byte patterns (8-bit)
const SPR_SLOTS      as ubyte    = 2     ' upload patterns 0..1

const SPR_ID      as ubyte = 0
const SPR_PATTERN as ubyte = 0

dim palL2(511)   as ubyte
dim sprBuf(16383) as ubyte     ' safe 16K buffer for sprite data
dim palULA8(255) as ubyte

' sprite motion
dim sprX  as integer : dim sprY  as integer
dim sprVX as integer : dim sprVY as integer

' scrolling / effects
dim p     as ubyte
dim xMain as uinteger

'------------------------------------------------------------
' NextReg helpers
'------------------------------------------------------------
function ReadNextReg(byval r as ubyte) as ubyte
    out PORT_NEXTREG_SEL, r
    return in(PORT_NEXTREG_DAT)
end function

sub WriteNextReg(byval r as ubyte, byval v as ubyte)
    out PORT_NEXTREG_SEL, r
    out PORT_NEXTREG_DAT, v
end sub

'------------------------------------------------------------
' Layer ordering (NextReg $15 bits 4..2), keep sprites enabled
'------------------------------------------------------------
sub SetLayerOver(byval ord as ubyte)
    dim v as ubyte
    v = ReadNextReg($15)

    ' Clear bits 4..2 then insert new order (ord 0..7).
    v = (v BAND %11100011) BOR ((ord BAND 7) SHL 2)

    ' Ensure sprites stay enabled (bit 0).
    v = v BOR 1

    WriteNextReg($15, v)
end sub

' Make Layer2 visible via TBBlue control port ($123B).
sub EnableLayer2Visible()
    asm
        ld bc, $123B
        ld a, 2          ; bit1 = Layer2 visible, other bits 0
        out (c), a
    end asm
end sub

'------------------------------------------------------------
' 8-bit palette upload helper (NextReg $41 stream)
'   - $43 selects palette target
'   - $40 selects start index
'------------------------------------------------------------
sub PalUpload8(byval addr as uinteger, byval startIndex as ubyte)
    WriteNextReg($40, startIndex)

    dim i as uinteger
    for i = 0 to 255
        WriteNextReg($41, peek(addr + i))
    next i
end sub

'------------------------------------------------------------
' Layer2 image + palette
'------------------------------------------------------------
sub LoadLayer2_SL2()
    WriteNextReg($12, L2_START_16K)     ' Layer2 start 16K bank
    EnableLayer2Visible()

    ' MG.nxi: 48K across 8K banks, loaded by NextLib.
    LoadSDBank("MG.nxi", 0, 0, 0, 18)   ' addr=$4000 (0), len=auto (0), offset=0, start bank=18
end sub

sub LoadLayer2Palette_PAL()
    ' MG.nxp: 9-bit palette, 512 bytes (byte0/byte1 per entry) from gfx2next.
    LoadSD("MG.nxp", @palL2(0), PAL_SIZE, 0)

    ' Select Layer2 first palette for upload (bits 6..4 = 001 => $10),
    ' keep ULANext enabled (bit0 = 1).
    WriteNextReg($43, ($10 BOR 1))

    ' NextLib PalUpload streams 2 bytes/entry via NextReg $44.
    ' Passing 0 as count means 256 (DJNZ loop).
    PalUpload(@palL2(0), 0, 0, 0)
end sub

'------------------------------------------------------------
' ULA (Layer 1,1) palette + transparent-background starfield
'
' Strategy:
'   - Build a 256-entry 8-bit ULA palette (palULA8)
'   - Select ULA palette target + enable ULANext
'   - Upload via NextReg $41
'   - Enable "full ink" so ULA attributes address 0..255
'   - Use transparency index $E3 and set ULA fallback ($4A) as needed
'------------------------------------------------------------
sub DefineULAPalette()
    dim i as uinteger

    ' Simple alternating pattern (matches original demo intent).
    for i = 0 to 255
        if (i band 1) = 0 then
            palULA8(i) = $60
        else
            palULA8(i) = $03
        end if
    next i

    ' Ensure index $E3 exists for transparency use.
    palULA8($E3) = $E3

    ' Select ULA palette target + enable ULANext.
    WriteNextReg($43, %00000001)

    ' Upload palette starting at index 0.
    PalUpload8(@palULA8(0), 0)

    ' Full ink: ULA attribute byte maps directly to 0..255 palette indices.
    WriteNextReg($42, 255)

    ' Global transparency index used by ULA fallback/background.
    WriteNextReg($14, $E3)

    ' Start with a visible fallback (changed dynamically in the main loop).
    WriteNextReg($4A, 0)
end sub

sub FillStarfield()
    cls

    ' Clip ULA region (similar to NextBASIC LAYER DIM effect).
    ClipULA(10, 250, 15, 150)

    dim l as ubyte
    dim r as ubyte
    dim c as ubyte
    dim t as ubyte
    dim inkCol as ubyte

    dim lu as uinteger
    dim ru as uinteger
    dim attrAddr as uinteger

    c = 0

    for l = 1 to 20
        lu = l
        for r = 1 to 30
            ru = r

            ' Every 3rd column uses the transparency index ($E3).
            t = c
            inkCol = c
            if (r mod 3) = 0 then inkCol = $E3

            print at l, r; "*";

            ' Attribute RAM: 22528 + row*32 + col
            attrAddr = 22528 + (lu * 32) + ru
            poke attrAddr, inkCol

            c = t
            c = c + 1
            if c >= 255 then c = 0
        next r
    next l
end sub

'------------------------------------------------------------
' Sprites
'------------------------------------------------------------
sub InitMySprite()
    ' spaceship.spr is a +3DOS CODE file; skip 128-byte header.
    LoadSD("spaceship.spr", @sprBuf(0), SPR_DATA_BYTES, SPR_FILE_SKIP)

    ' Upload 2 x 256-byte patterns into sprite pattern memory.
    InitSprites(SPR_SLOTS, @sprBuf(0))

    ' 8-bit sprite transparency index.
    WriteNextReg($4B, $E3)

    sprX = 100 : sprY = 80
    sprVX = 2  : sprVY = 1

    ' Clip sprites to similar region as the ULA clip.
    ClipSprite(10, 250, 15, 150)
end sub

sub UpdateBouncingSprite()
    sprX = sprX + sprVX
    sprY = sprY + sprVY

    if sprX > 319 then sprX = 319 : sprVX = -sprVX
    if sprX <   0 then sprX =   0 : sprVX = -sprVX

    if sprY > 191 then sprY = 191 : sprVY = -sprVY
    if sprY <   0 then sprY =   0 : sprVY = -sprVY

    dim ux as uinteger
    dim uy as ubyte
    ux = sprX
    uy = sprY

    UpdateSprite(ux, uy, SPR_ID, SPR_PATTERN, 0, 0)
end sub

'------------------------------------------------------------
' ULA pixel scroll (NextRegs $26/$27)
'------------------------------------------------------------
sub ScrollULA(byval ox as ubyte, byval oy as ubyte)
    WriteNextReg($26, ox)
    WriteNextReg($27, oy)
end sub

'------------------------------------------------------------
' Main init
'------------------------------------------------------------
border 0
paper 0 : ink 7 : cls
randomize

' 28MHz
WriteNextReg($07, 3)

' Show Layer2 (NextLib helper)
ShowLayer2(1)

LoadLayer2_SL2()
LoadLayer2Palette_PAL()

DefineULAPalette()
FillStarfield()

InitMySprite()

' Initial layer order
SetLayerOver(2)

p = 0

'------------------------------------------------------------
' Main loop:
'   - Scroll Layer2 continuously
'   - Scroll ULA every third step
'   - Toggle ULA fallback colour and layer priority once per outer loop
'------------------------------------------------------------
do
    xMain = xMain + 1

    dim ii as integer
    dim ox as ubyte
    dim oy as ubyte
    dim rr as ubyte

    ' Phase A: forward
    SetLayerOver(2)
    for ii = 1 to 190
        UpdateBouncingSprite()
        ox = ii : oy = ii
        ScrollLayer(ox, oy)

        if (ii mod 3) = 0 then
            ScrollULA(p, p)
            p = p + 1
            if p >= 255 then p = 0
        end if

        if inkey$ <> "" then exit do
        WaitRetrace(1)
    next ii

    ' Phase B: reverse
    SetLayerOver(4)
    for ii = 190 to 1 step -1
        UpdateBouncingSprite()
        ox = ii : oy = ii
        ScrollLayer(ox, oy)

        if (ii mod 3) = 0 then
            p = p + 1
            if p >= 255 then p = 0
            ScrollULA(p, p)
        end if

        if inkey$ <> "" then exit do
        WaitRetrace(1)
    next ii

    ' Once per outer iteration:
    '   Even: ULA fallback transparent + sprites in front
    '   Odd : ULA fallback visible + ULA in front
    if (xMain band 1) = 0 then
        WriteNextReg($4A, $E3)
        SetLayerOver(0)
    else
        rr = int(rnd * 256)
        if rr = $E3 then rr = rr + 1
        WriteNextReg($4A, rr)
        SetLayerOver(4)
    end if

    WaitRetrace(10)
loop

RemoveSprite(SPR_ID, 0)
stop
