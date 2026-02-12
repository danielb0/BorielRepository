'===========================================================
' myscroll4 - NextBASIC -> Boriel ZX Basic (ZXBASIC) version
' Target: ZX Spectrum Next
'===========================================================

'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)

'-------------------------
' Ports & NextReg helpers
'-------------------------
CONST PORT_NEXTREG_SEL = $243B
CONST PORT_NEXTREG_DAT = $253B

SUB NextRegWrite(byval r AS UBYTE, byval v AS UBYTE)
    OUT PORT_NEXTREG_SEL, r
    OUT PORT_NEXTREG_DAT, v
END SUB

FUNCTION NextRegRead(byval r AS UBYTE) AS UBYTE
    OUT PORT_NEXTREG_SEL, r
    RETURN IN(PORT_NEXTREG_DAT)
END FUNCTION

'-------------------------
' Layer priority / sprites
'-------------------------
DIM sys15 AS UBYTE

SUB LayerOver(byval n AS UBYTE)
    sys15 = (sys15 AND %11100011) OR ((n AND 7) SHL 2)
    NextRegWrite($15, sys15)
END SUB

'-------------------------
' Clip windows
'-------------------------
SUB SetULAClip(byval x1 AS UBYTE, byval x2 AS UBYTE, byval y1 AS UBYTE, byval y2 AS UBYTE)
    NextRegWrite($1C, %00000100)  ' reset ULA clip index
    NextRegWrite($1A, x1)
    NextRegWrite($1A, x2)
    NextRegWrite($1A, y1)
    NextRegWrite($1A, y2)
END SUB

SUB SetLayer2ClipFull256x192()
    NextRegWrite($1C, %00000001)  ' reset Layer2 clip index
    NextRegWrite($18, 0)
    NextRegWrite($18, 255)
    NextRegWrite($18, 0)
    NextRegWrite($18, 191)
END SUB

'-------------------------
' Layer 2 scroll offsets
'-------------------------
SUB Layer2At(byval ox AS UBYTE, byval oy AS UBYTE)
    NextRegWrite($16, ox)
    NextRegWrite($17, oy)
END SUB

'-------------------------
' Palette upload (9-bit via $44)
'-------------------------
SUB Upload9BitPalette(byval palSelectBits AS UBYTE, byval startIndex AS UBYTE, byval srcAddr AS UINTEGER, byval colours AS UBYTE)
    NextRegWrite($43, palSelectBits)
    NextRegWrite($40, startIndex)

    DIM i AS UINTEGER
    DIM p AS UINTEGER
    p = srcAddr

    FOR i = 0 TO colours-1
        NextRegWrite($44, PEEK(p)) : p = p + 1
        NextRegWrite($44, PEEK(p)) : p = p + 1
    NEXT i
END SUB

'-----------------------------------------------------------
' SAFE MMU window: use slot 2 ($4000-$5FFF) via NextReg $52
'-----------------------------------------------------------
CONST MMU_WIN_REG  = $52
CONST MMU_WIN_BASE = $4000

SUB CopyToPagedWindow(byval bank8k AS UBYTE, byval src AS UINTEGER, byval count AS UINTEGER)
    DIM old AS UBYTE
    old = NextRegRead(MMU_WIN_REG)

    NextRegWrite(MMU_WIN_REG, bank8k)

    DIM i AS UINTEGER
    FOR i = 0 TO count-1
        POKE MMU_WIN_BASE + i, PEEK(src + i)
    NEXT i

    NextRegWrite(MMU_WIN_REG, old)
END SUB

SUB CopyLayer2Image256x192(byval start16k AS UBYTE, byval srcAddr AS UINTEGER)
    ' 256x192 8bpp = 48K = 6 x 8K banks
    DIM start8k AS UBYTE
    start8k = start16k * 2

    DIM ofs AS UINTEGER
    ofs = 0

    DIM b AS UBYTE
    FOR b = 0 TO 5
        CopyToPagedWindow(start8k + b, srcAddr + ofs, 8192)
        ofs = ofs + 8192
    NEXT b
END SUB

'-------------------------
' Sprite upload & setup
'-------------------------
CONST PORT_SPR_SLOTSEL = $303B
CONST PORT_SPR_PATUPL  = $005B

SUB UploadSpritePatterns(byval patternSlot AS UBYTE, byval srcAddr AS UINTEGER, byval byteCount AS UINTEGER)
    OUT PORT_SPR_SLOTSEL, patternSlot

    DIM i AS UINTEGER
    FOR i = 0 TO byteCount-1
        OUT PORT_SPR_PATUPL, PEEK(srcAddr + i)
    NEXT i
END SUB

SUB SetSprite0(byval x AS UINTEGER, byval y AS UBYTE, byval pat AS UBYTE)
    NextRegWrite($34, 0)
    NextRegWrite($35, x AND 255)
    NextRegWrite($36, y)
    NextRegWrite($37, 0)
    NextRegWrite($38, %11000000 OR (pat AND 63))
    NextRegWrite($39, (x SHR 8) AND 1)
END SUB

'-------------------------
' Layer2 plot/circle (uses SAFE window too)
'-------------------------
CONST L2_START_16K = 9

SUB L2Plot(byval x AS UBYTE, byval y AS UBYTE, byval col AS UBYTE)
    IF y > 191 THEN return

    DIM bank16k AS UBYTE
    bank16k = L2_START_16K + (y SHR 6)

    DIM offset AS UINTEGER
    offset = (y AND 63) * 256 + x

    DIM bank8k AS UBYTE
    bank8k = (bank16k SHL 1) + (offset SHR 13)

    DIM old AS UBYTE
    old = NextRegRead(MMU_WIN_REG)

    NextRegWrite(MMU_WIN_REG, bank8k)
    POKE MMU_WIN_BASE + (offset AND 8191), col
    NextRegWrite(MMU_WIN_REG, old)
END SUB

SUB CircleL2(byval cx AS UBYTE, byval cy AS UBYTE, byval r AS UBYTE, byval col AS UBYTE)
    DIM x AS INTEGER
    DIM y AS INTEGER
    DIM d AS INTEGER
    x = 0 : y = r : d = 1 - r

    WHILE x <= y
        L2Plot(cx + x, cy + y, col)
        L2Plot(cx - x, cy + y, col)
        L2Plot(cx + x, cy - y, col)
        L2Plot(cx - x, cy - y, col)
        L2Plot(cx + y, cy + x, col)
        L2Plot(cx - y, cy + x, col)
        L2Plot(cx + y, cy - x, col)
        L2Plot(cx - y, cy - x, col)

        IF d < 0 THEN
            d = d + (2 * x) + 3
        ELSE
            d = d + (2 * (x - y)) + 5
            y = y - 1
        END IF
        x = x + 1
    WEND
END SUB

'===========================================================
' Main program
'===========================================================
BORDER 3
CLS
RANDOMIZE

' Make Layer2 visible using $123B bit 1 (and enable read paging bit 2 if you like)
' Bit1 = visible, Bit0 write paging, Bit2 read-only paging. :contentReference[oaicite:1]{index=1}
OUT $123B, %00000110   ' bit1 + bit2 (visible + read paging)

' Set Layer2 start bank (16K)
NextRegWrite($12, L2_START_16K)

' Layer2 clip full screen for 256x192
SetLayer2ClipFull256x192()

' Copy SL2 image data into Layer2 banks
CopyLayer2Image256x192(L2_START_16K, @NutterSL2)

' Upload Layer2 palette
Upload9BitPalette(%00010000, 0, @NutterPAL, 256)

' Draw circles on top
DIM i AS UBYTE
FOR i = 0 TO 19
    CircleL2(100, 40, 20, i)
NEXT i

'-------------------------
' ULA palette setup
'-------------------------
NextRegWrite($42, 255)
NextRegWrite($4A, 0)

NextRegWrite($43, %00000001)
NextRegWrite($40, 0)

DIM pal43(511) AS UBYTE
DIM n AS UINTEGER
FOR n = 0 TO 511
    IF (n AND 1) = 0 THEN pal43(n) = $60 ELSE pal43(n) = $03
NEXT n

pal43(0)   = $00 : pal43(1)   = $00
pal43(2)   = $03 : pal43(3)   = $00
pal43(4)   = $04 : pal43(5)   = $00
pal43(6)   = $1C : pal43(7)   = $00
pal43(8)   = $05 : pal43(9)   = $00
pal43(10)  = $07 : pal43(11)  = $00
pal43(12)  = $0B : pal43(13)  = $00
pal43(14)  = $0B : pal43(15)  = $00

Upload9BitPalette(%00000001, 0, @pal43(0), 256)

NextRegWrite($14, $E3)

' Star field printing (ULA text)
DIM tx AS UBYTE
DIM ty AS UBYTE
FOR ty = 0 TO 23
    FOR tx = 0 TO 31
        INK 7 - (tx AND 7)
        PRINT AT ty, tx; "*";
    NEXT tx
NEXT ty


SetULAClip(10, 250, 15, 150)

'-------------------------
' Sprites
'-------------------------
sys15 = %00000001
NextRegWrite($15, sys15)

UploadSpritePatterns(0, @SpaceshipSpr, (@SpaceshipSprEnd - @SpaceshipSpr))
SetSprite0(100, 100, 1)

'-------------------------
' Animation
'-------------------------
DIM sx AS INTEGER
DIM sy AS INTEGER
DIM dx AS INTEGER
DIM dy AS INTEGER
sx = 0 : sy = 48
dx = 2 : dy = 5

DIM p AS UBYTE
p = 0

DO
    LayerOver(2)

    FOR i = 1 TO 190
        sx = sx + dx
        sy = sy + dy
        IF sx >= 304 THEN sx = 304 : dx = -dx
        IF sx <= 0   THEN sx = 0   : dx = -dx
        IF sy >= 192 THEN sy = 192 : dy = -dy
        IF sy <= 48  THEN sy = 48  : dy = -dy

        SetSprite0(sx, sy, 1)
        Layer2At(i AND 255, i AND 255)

        IF (i MOD 3) <> 0 THEN
            NextRegWrite($26, p)
            NextRegWrite($27, p)
            p = p + 1
        END IF

        IF INKEY$ <> "" THEN STOP
    NEXT i

    LayerOver(0)
    NextRegWrite($4A, 0)

    FOR i = 1 TO 190
        sx = sx + dx
        sy = sy + dy
        IF sx >= 304 THEN sx = 304 : dx = -dx
        IF sx <= 0   THEN sx = 0   : dx = -dx
        IF sy >= 192 THEN sy = 192 : dy = -dy
        IF sy <= 48  THEN sy = 48  : dy = -dy
        SetSprite0(sx, sy, 1)

        NextRegWrite($4A, $E3)
        IF INKEY$ <> "" THEN STOP
    NEXT i

    LayerOver(4)
    NextRegWrite($4A, $E3)

    FOR i = 1 TO 190
        sx = sx + dx
        sy = sy + dy
        IF sx >= 304 THEN sx = 304 : dx = -dx
        IF sx <= 0   THEN sx = 0   : dx = -dx
        IF sy >= 192 THEN sy = 192 : dy = -dy
        IF sy <= 48  THEN sy = 48  : dy = -dy
        SetSprite0(sx, sy, 1)

        NextRegWrite($4A, INT(RND * 255))
        IF INKEY$ <> "" THEN STOP
    NEXT i

LOOP

END

'===========================================================
' Embedded assets MUST be after END (so they are not executed)
'===========================================================

SpaceshipSpr:
asm
    INCBIN "data/spaceship.spr"
end asm
SpaceshipSprEnd: REM

NutterSL2:
asm
    INCBIN "data/nutter.sl2"
end asm
NutterSL2End: REM

NutterPAL:
asm
    INCBIN "data/nutter.pal"
end asm
NutterPALEnd: REM
