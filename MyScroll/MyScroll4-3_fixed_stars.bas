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
const SPR_FILE_SKIP as uinteger = 128      ' +3DOS header
const SPR_DATA_BYTES as uinteger = 512      ' 2 x 256-byte 8-bit patterns
const SPR_SLOTS as ubyte = 2                ' upload 2 pattern slots (pattern 0..1)

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
dim xMain as uinteger




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
SUB LoadLayer2_SL2()
    WriteNextReg($12, L2_START_16K)      ' Layer2 start 16K bank
    LoadSDBank("nutter.sl2", 0, 0, 0, 18) ' address=$4000 (via 0), length=0 = autodetect, offset=0, start bank=18
END SUB

sub LoadLayer2Palette_PAL()
    LoadSD("nutter.pal", @palL2(0), PAL_SIZE, 0)

    ' Select Layer2 first palette in NextReg $43 (bits 6..4 = %001)
    ' Keep ULANext enable bit (bit0) set as well -> OR 1
    ' Select Layer2 first palette for upload: bits 6..4 = 001 => $10
    WriteNextReg($43, ($10 BOR 1))

    ' Upload 256 colours (0 in NextLib means 256, because the loop uses DJNZ)
    PalUpload(@palL2(0), 0, 0, 0)
    ' NOTE: NextBASIC demo does not set a sprite palette; leave sprite palette at power-on default (RGB332 passthrough)
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
        if (i band 1) = 0 then
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

SUB FillStarfield()
    CLS

    ' Clip ULA (equivalent "LAYER DIM" for the ULA plane)
    ClipULA(10, 250, 15, 150)

    DIM l AS UBYTE
    DIM r AS UBYTE
    DIM c AS UBYTE
    DIM t AS UBYTE
    DIM inkCol AS UBYTE

    DIM lu AS UINTEGER
    DIM ru AS UINTEGER
    DIM attrAddr AS UINTEGER

    c = 0

    FOR l = 1 TO 20
        lu = l
        FOR r = 1 TO 30
            ru = r

            ' Same logic as NextBASIC: temporarily force 227 on every 3rd column
            t = c
            inkCol = c
            IF (r MOD 3) = 0 THEN
                inkCol = $E3
            END IF

            PRINT AT l, r; "*";

            ' IMPORTANT: do address math in 16-bit
            attrAddr = 22528 + (lu * 32) + ru
            POKE attrAddr, inkCol

            ' restore + increment (matches NextBASIC)
            c = t
            c = c + 1
            IF c >= 255 THEN c = 0
        NEXT r
    NEXT l
END SUB


'------------------------------------------------------------
' Sprites
'------------------------------------------------------------
sub InitMySprite()
    ' spaceship.spr is a +3DOS CODE file; skip its 128-byte header and load only the 512 bytes of sprite pattern data
    LoadSD("spaceship.spr", @sprBuf(0), SPR_DATA_BYTES, SPR_FILE_SKIP)

    ' Upload 2 x 256-byte 8-bit patterns into sprite pattern memory (patterns 0 and 1)
    InitSprites(SPR_SLOTS, @sprBuf(0))

    ' 8-bit sprite transparency index (NextReg $4B). This file uses $E3 extensively.
    WriteNextReg($4B, $E3)



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
    UpdateSprite(ux, uy, SPR_ID, SPR_PATTERN, 0, 0)   ' 8-bit anchor (byte5=0), no palette offset (attr2=0)
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
' NextBASIC effect: every X iterations toggle ULA fallback (REG 74 / $4A) + layer priority (LAYER OVER)
' Even state: $4A=$E3 (transparent) and LAYER OVER 0 (sprite in front of ULA)
' Odd state:  $4A=random (non-$E3) and LAYER OVER 4 (ULA in front of sprite)
'------------------------------------------------------------

'------------------------------------------------------------
' Main loop (adds actual scrolling to Layer2 + ULA, and cycles priorities)
'------------------------------------------------------------
do
    xMain = xMain + 1

    ' Phase A forward (matches NextBASIC: LAYER OVER 2 / FOR 1..190)
    dim ii as integer
    dim ox as ubyte
    dim oy as ubyte
    dim rr as ubyte

    SetLayerOver(2)
    for ii = 1 to 190
        UpdateBouncingSprite()
        ox = ii : oy = ii
        ScrollLayer(ox, oy)

        ' every 3rd step: scroll ULA only upward (independent from Layer2 direction)
        if (ii mod 3) = 0 then
            ScrollULA(p, p)
            p = p + 1
            if p >= 255 then p = 0
        end if

        if inkey$ <> "" then exit do
        WaitRetrace(1)
    next ii

    ' Phase B reverse (matches NextBASIC: LAYER OVER 4 / FOR 190..1)
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

    ' Once per MAIN iteration: NextBASIC IF %x MOD 2 = 0 ...
    ' REG 74 is NextReg $4A (fallback / border-paper in full-ink mode).
    if (xMain band 1) = 0 then
        WriteNextReg($4A, $E3)    ' 227: make ULA paper/border transparent (matches PALETTE OVER $E3)
        SetLayerOver(0)          ' sprites in front of ULA
    else
        rr = int(rnd * 256)
        if rr = $E3 then rr = rr + 1
        WriteNextReg($4A, rr)    ' random visible background/border colour
        SetLayerOver(4)          ' ULA in front of sprites
    end if

    ' NextBASIC naturally pauses here (PRINT etc). Give the end-state time to be visible.
    WaitRetrace(10)

loop

RemoveSprite(SPR_ID, 0)
stop