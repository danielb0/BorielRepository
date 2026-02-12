'!org=32768
'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)
#define NEX
#include <NextLib.bas>

declare function ReadNextReg(byval r as ubyte) as ubyte
'------------------------------------------------------------
' Minimal NextReg write helper (avoids relying on NextLib macro)
'------------------------------------------------------------
const PORT_NEXTREG_SEL as uinteger = $243B
const PORT_NEXTREG_DAT as uinteger = $253B



'------------------------------------------------------------
' Constants / buffers
'------------------------------------------------------------
const L2_START_16K as ubyte = 9

const PAL_SIZE     as uinteger = 512

' spaceship.spr is typically 16K => 64 x 256-byte patterns
const SPR_BYTES    as uinteger = $4000
const SPR_BLOCKS   as ubyte    = 64

const SPR_ID       as ubyte = 0
const SPR_PATTERN  as ubyte = 0           ' pattern 0, like your NextBASIC SPRITE ...,0,1

dim palL2(511)  as ubyte
dim palULA(511) as ubyte
dim sprBuf(16383) as ubyte                ' safe 16K buffer
dim palULA8(255) as ubyte

' sprite motion
dim sprX as integer : dim sprY as integer
dim sprVX as integer : dim sprVY as integer

' scrolling / effects
dim p as ubyte
dim frame as uinteger
dim layerOver as ubyte




'------------------------------------------------------------
' Layer ordering (NextReg $15 bits 4..2, keep sprites enabled)
'------------------------------------------------------------
function ReadNextReg(byval r as ubyte) as ubyte
    out PORT_NEXTREG_SEL, r
    return in(PORT_NEXTREG_DAT)
end function

sub WriteNextReg(byval r as ubyte, byval v as ubyte)
    out PORT_NEXTREG_SEL, r
    out PORT_NEXTREG_DAT, v
end sub

sub SetLayerOver(byval ord as ubyte)
    dim v as ubyte
    v = ReadNextReg($15)

    ' Bitwise mask/merge (NOT logical AND/OR)
    v = (v BAND %11100011) BOR ((ord BAND 7) SHL 2)

    ' keep sprites enabled
    v = v BOR 1

    WriteNextReg($15, v)
end sub

sub PalUpload8(byval addr as uinteger, byval startIndex as ubyte)
    ' Upload 256 bytes (8-bit palette entries) via NextReg $41
    ' Assumes pal target already selected in $43, and $40 sets start index
    WriteNextReg($40, startIndex)

    dim i as uinteger
    for i = 0 to 255
        WriteNextReg($41, peek(addr + i))
    next i
end sub

'------------------------------------------------------------
' Layer2 load (must be constants for NextBuild parser)
'------------------------------------------------------------
sub LoadLayer2_SL2()
    ' Set Layer2 start 16K bank
    WriteNextReg($12, L2_START_16K)

    ' 16K bank 9 => 8K banks 18..23 (48K total)
    LoadSDBank("nutter.sl2", 0, 8192,     0, 18)
    LoadSDBank("nutter.sl2", 0, 8192,  8192, 19)
    LoadSDBank("nutter.sl2", 0, 8192, 16384, 20)
    LoadSDBank("nutter.sl2", 0, 8192, 24576, 21)
    LoadSDBank("nutter.sl2", 0, 8192, 32768, 22)
    LoadSDBank("nutter.sl2", 0, 8192, 40960, 23)
end sub

sub LoadLayer2Palette_PAL()
    LoadSD("nutter.pal", @palL2(0), PAL_SIZE, 0)

    ' Select Layer2 first palette in NextReg $43 (bits 6..4 = %001)
    ' Keep ULANext enable bit (bit0) set as well -> OR 1
    ' Select Layer2 first palette for upload: bits 6..4 = 001 => $10
    WriteNextReg($43, ($10 BOR 1))

    ' Upload 256 colours (0 in NextLib means 256, because the loop uses DJNZ)
    PalUpload(@palL2(0), 0, 0, 0)
    ' Also upload the same palette to Sprites first palette (bits 6..4 = 010 => $20)
    WriteNextReg($43, ($20 BOR 1))
    PalUpload(@palL2(0), 0, 0, 0)

end sub

'------------------------------------------------------------
' Layer2 circle drawing using NextLib PlotL2
'------------------------------------------------------------
sub CircleL2_Custom(byval cx as ubyte, byval cy as ubyte, byval r as ubyte, byval col as ubyte)
    dim x as integer
    dim y as integer
    dim d as integer
    x = 0 : y = r : d = 1 - r

    while x <= y
        PlotL2(cx + x, cy + y, col)
        PlotL2(cx - x, cy + y, col)
        PlotL2(cx + x, cy - y, col)
        PlotL2(cx - x, cy - y, col)
        PlotL2(cx + y, cy + x, col)
        PlotL2(cx - y, cy + x, col)
        PlotL2(cx + y, cy - x, col)
        PlotL2(cx - y, cy - x, col)

        if d < 0 then
            d = d + (2 * x) + 3
        else
            d = d + (2 * (x - y)) + 5
            y = y - 1
        end if
        x = x + 1
    wend
end sub

sub DrawCirclesOnLayer2()
    dim i as ubyte
    for i = 0 to 19
        CircleL2_Custom( 70,  70, 10 + i, i)
        CircleL2_Custom(180,  90, 10 + i, 40 + i)
    next i
end sub

'------------------------------------------------------------
' ULA (Layer 1,1) palette + transparent-background starfield
'
' This matches the NextBASIC sequence:
'   LAYER 1,1
'   LAYER PALETTE 0 BANK 43,0
'
' Idea:
' - Build a 256-byte "8-bit" ULA palette table (palULA8), like BANK 43 in NextBASIC.
' - Select the ULA palette target and enable ULANext:
'     NextReg $43: bits 6..4 = 000 (ULA palette), bit0 = 1 (ULANext on)
' - Upload the 256 entries via NextReg $41 (8-bit palette upload), starting at index 0.
' - Enable "full ink" so ULA attributes can address 0..255 palette indices:
'     NextReg $42 = $FF
' - Set global transparency index and make the ULA background transparent by setting
'   the fallback colour to the transparent index:
'     NextReg $14 = $E3, NextReg $4A = $E3
' - Draw the starfield on the ULA layer; colour is then controlled by the attribute byte
'   (and/or classic INK/PAPER), while transparent background lets Layer2 show through.
'------------------------------------------------------------

sub DefineULAPalette()
    dim i as uinteger

    ' Build the same pattern you used in NextBASIC BANK 43
    for i = 0 to 255
        if (i and 1) = 0 then
            palULA8(i) = $60
        else
            palULA8(i) = $03
        end if
    next i

    ' Your explicit front entries (translated to 8-bit form):
    ' In your 9-bit stream you were setting pairs (byte0/byte1).
    ' Here we set just the single 8-bit entry per index.
    palULA8(0)  = $CD
    'palULA8(1)  = $03
    'palULA8(2)  = $04
    'palULA8(3)  = $1C
    'palULA8(4)  = $05
    'palULA8(5)  = $07
    'palULA8(6)  = $0B
    'palULA8(7)  = $0B

    ' If you relied on index $E3 for transparency "colour", keep it defined:
    palULA8($E3) = $E3

    ' --- Apply to Layer 1,1 (ULA) ---
    ' Select ULA palette target + enable ULANext
    WriteNextReg($43, %00000001)

    ' Upload palette #0 starting at index 0
    PalUpload8(@palULA8(0), 0)

    ' ULA full-ink mode + global transparency index
    WriteNextReg($42, 255)          ' full ink (attributes become 0..255)
    WriteNextReg($14, $E3)          ' global transparency index

    ' Background/fallback transparent so Layer2 shows through
    WriteNextReg($4A, 0)
end sub

sub FillStarfield()
    cls

    ' Clip ULA (equivalent "layer dim" effect for the ULA plane)
    ' NextLib ClipULA expects UBYTEs
    ClipULA(10, 250, 15, 150)

    dim r as ubyte
    dim c as ubyte
    dim col as ubyte
    dim attrAddr as uinteger

    col = 0
    for r = 0 to 23
        for c = 0 to 31
            if (c mod 3) = 0 then
                col = $E3            ' transparent star
            end if
            print at r, c; "*";
            attrAddr = 22528 + (r * 32) + c
            poke attrAddr, col

            if (c mod 3) <> 0 then
                col = col + 1
            end if
        next c
    next r
end sub

'------------------------------------------------------------
' Sprites
'------------------------------------------------------------
sub InitMySprite()
    LoadSD("spaceship.spr", @sprBuf(0), SPR_BYTES, 0)

    ' IMPORTANT: 16K SPR => 64 blocks of 256 bytes
    InitSprites(SPR_BLOCKS, @sprBuf(0))
    ' Sprite transparency index (NextReg $4B). Many .spr tools use 0 for 4-bit transparency.
    WriteNextReg($4B, 3)   ' 4-bit sprite default transparency index ([wiki.specnext.dev](https://wiki.specnext.dev/Sprites))


    sprX = 100 : sprY = 80
    sprVX = 2  : sprVY = 1

    ' Clip sprites to roughly the same region
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

    ' palette offset nibble = $10 (palette "1"), like SPRITE ...,0,1 in NextBASIC
    UpdateSprite(ux, uy, SPR_ID, SPR_PATTERN, $10, $80)   ' $80 => 4-bit anchor, bytes 0..127 ([wiki.specnext.dev](https://wiki.specnext.dev/Sprites))
end sub

'------------------------------------------------------------
' ULA pixel scroll (what your REG 38/39 were doing)
' NextRegs $26/$27 are ULA X/Y offsets in your NextLib.
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

' Show Layer2
ShowLayer2(1)

' Draw circles FIRST, then load the picture OVER them (so circles disappear)
'DrawCirclesOnLayer2()

' Load Layer2 image + palette (should overwrite circles)
LoadLayer2_SL2()
LoadLayer2Palette_PAL()

' ULA palette + starfield with transparency
DefineULAPalette()
FillStarfield()

' Sprites
InitMySprite()

' Start state
layerOver = 2
SetLayerOver(layerOver)

p = 0
frame = 0

'------------------------------------------------------------
' Main loop (adds actual scrolling to Layer2 + ULA, and cycles priorities)
'------------------------------------------------------------
do
   ' Phase A forward
dim ii as integer
dim ox as ubyte
dim oy as ubyte
dim l as ubyte
SetLayerOver(2)

l=ReadNextReg($15)

'print at 10,10;"NR15="; ReadNR15()

for ii = 1 to 190
    UpdateBouncingSprite()

    ox = ii : oy = ii
    ScrollLayer(ox, oy)

    if (ii mod 3) = 0 then
        ScrollULA(0, p)
        p = p + 1
    end if

    ' Match NextBASIC: toggle ULA fallback (NextReg $4A / REG 74) + layer priority (LAYER OVER)
    if (ii band 1) = 0 then
        WriteNextReg($4A, $E3)      ' 227 => make ULA paper/border transparent when global transparency is $E3
        SetLayerOver(0)             ' 000: Sprites over L2 over ULA (sprite in front of ULA) ([wiki.specnext.dev](https://wiki.specnext.dev/Sprites))
    else
        WriteNextReg($4A, int(rnd*256))  ' random border/background colour
        SetLayerOver(4)             ' 100: ULA over sprites over L2 (sprite behind ULA) ([wiki.specnext.dev](https://wiki.specnext.dev/Sprites))
    end if

    if inkey$ <> "" then exit do
    WaitRetrace(1)
next ii

' Phase A reverse  (THIS is what breaks if you use UBYTE i)
SetLayerOver(4)
l=ReadNextReg($15)

'print at 10,10;"NR15="; ReadNR15()

for ii = 190 to 1 step -1
    UpdateBouncingSprite()

    ox = ii : oy = ii
    ScrollLayer(ox, oy)

    if (ii mod 3) = 0 then
        ' if you want layer1 to reverse too, do p = p - 1 with wrap:
        p = p + 1
        ScrollULA(0, p)
    end if

    if p >= 255
        p = 0
    endif
    
    ' Match NextBASIC: toggle ULA fallback (NextReg $4A / REG 74) + layer priority (LAYER OVER)
    if (ii band 1) = 0 then
        WriteNextReg($4A, $E3)      ' 227 => make ULA paper/border transparent when global transparency is $E3
        SetLayerOver(0)             ' 000: Sprites over L2 over ULA (sprite in front of ULA) ([wiki.specnext.dev](https://wiki.specnext.dev/Sprites))
    else
        WriteNextReg($4A, int(rnd*256))  ' random border/background colour
        SetLayerOver(4)             ' 100: ULA over sprites over L2 (sprite behind ULA) ([wiki.specnext.dev](https://wiki.specnext.dev/Sprites))
    end if

    if inkey$ <> "" then exit do
    WaitRetrace(1)
next ii

loop

RemoveSprite(SPR_ID, 0)
stop