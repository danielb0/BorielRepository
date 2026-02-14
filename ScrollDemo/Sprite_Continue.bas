'------------------------------------------------------------
' Sprite_Continue.bas
'
' NextBASIC-style automatic sprite movement/animation:
'   - SPRITE CONTINUE  (configure ranges/steps/rate/delay/flags)
'   - SPRITE MOVE      (advance one tick)
'
' This module reproduces the CONTINUE + MOVE behaviour in Boriel ZX Basic.
' It updates x/y/pattern state and then calls NextLib UpdateSprite.
'
' Usage (main program):
'   #include "Sprite_Continue.bas"   ' includes <NextLib.bas> internally
'
'   SpriteContinue_Init()
'   SpriteContinue_SetPos(id, x, y, pattern)
'   SpriteContinue_Config(id, x1,x2,xs,runX, y1,y2,ys,runY, p1,p2, rate, delay, flags)
'
'   ' per tick (equivalent of SPRITE MOVE):
'   SpriteContinue_Tick(id)
'   SpriteContinue_Apply(id, spriteId, -1, anchor, attr2)
'
' Notes:
' - This module maintains per-sprite state (x, y, pattern, visibility).
' - It does not attempt to mirror every NextBASIC sprite attribute; you can still
'   change sprite flags/palette/anchor via normal NextLib calls.
'------------------------------------------------------------

#ifndef SPRITE_CONTINUE_BAS
#define SPRITE_CONTINUE_BAS

#include <NextLib.bas>

' Adjust if you need more than 32 sprites.
const SC_MAX as ubyte = 32

' Position (signed, because bouncing can go negative briefly if misconfigured)
dim sc_x(SC_MAX-1) as integer
dim sc_y(SC_MAX-1) as integer

' Movement ranges (x uses 0..319, y uses 0..255 but you typically use 0..191)
dim sc_x1(SC_MAX-1) as uinteger
dim sc_x2(SC_MAX-1) as uinteger
dim sc_y1(SC_MAX-1) as ubyte
dim sc_y2(SC_MAX-1) as ubyte

' Steps (signed, -127..+127 typical)
dim sc_xs(SC_MAX-1) as integer
dim sc_ys(SC_MAX-1) as integer

' RUN/STOP flags per axis (0=STOP, 1=RUN)
dim sc_runX(SC_MAX-1) as ubyte
dim sc_runY(SC_MAX-1) as ubyte

' Pattern animation range and state
dim sc_p1(SC_MAX-1) as ubyte
dim sc_p2(SC_MAX-1) as ubyte
dim sc_pat(SC_MAX-1) as integer     ' current pattern (signed for bounce)
dim sc_patDir(SC_MAX-1) as integer  ' +1 or -1

' Movement rate / initial delay
dim sc_rate(SC_MAX-1)  as ubyte
dim sc_delay(SC_MAX-1) as ubyte
dim sc_skip(SC_MAX-1)  as ubyte

' Flags (matches manual semantics for bits implemented here)
' bits 1:0  limit behaviour:
'   00 reflect
'   01 stop this direction, start other direction
'   10 stop this direction
'   11 stop completely and make sprite invisible
' bit 4  pattern change:
'   0 cycle upwards with wrap
'   1 bounce between limits
' bit 6  if set, update pattern even when sprite is stationary
dim sc_flags(SC_MAX-1) as ubyte

dim sc_visible(SC_MAX-1) as ubyte

'------------------------------------------------------------
' Public API
'------------------------------------------------------------
sub SpriteContinue_Init()
    dim i as ubyte
    for i = 0 to SC_MAX-1
        sc_x(i) = 0 : sc_y(i) = 0
        sc_x1(i) = 0 : sc_x2(i) = 0
        sc_y1(i) = 0 : sc_y2(i) = 0
        sc_xs(i) = 0 : sc_ys(i) = 0
        sc_runX(i) = 0 : sc_runY(i) = 0
        sc_p1(i) = 0 : sc_p2(i) = 0
        sc_pat(i) = 0 : sc_patDir(i) = 1
        sc_rate(i) = 0 : sc_delay(i) = 0 : sc_skip(i) = 0
        sc_flags(i) = 0
        sc_visible(i) = 1
    next i
end sub

' Set the initial state (equivalent to "last SPRITE command" supplying initial x,y,pattern)
sub SpriteContinue_SetPos(byval s as ubyte, byval x as integer, byval y as integer, byval pattern as ubyte)
    if s >= SC_MAX then return
    sc_x(s) = x
    sc_y(s) = y
    sc_pat(s) = pattern
end sub

sub SpriteContinue_Config( _
    byval s as ubyte, _
    byval x1 as uinteger, byval x2 as uinteger, byval xs as integer, byval runX as ubyte, _
    byval y1 as ubyte,    byval y2 as ubyte,    byval ys as integer, byval runY as ubyte, _
    byval p1 as ubyte,    byval p2 as ubyte, _
    byval rate as ubyte,  byval delay as ubyte, _
    byval flags as ubyte _
)
    if s >= SC_MAX then return

    sc_x1(s) = x1 : sc_x2(s) = x2 : sc_xs(s) = xs : sc_runX(s) = runX
    sc_y1(s) = y1 : sc_y2(s) = y2 : sc_ys(s) = ys : sc_runY(s) = runY

    sc_p1(s) = p1 : sc_p2(s) = p2

    ' Clamp current pattern into range and set initial direction.
    if sc_pat(s) < p1 then sc_pat(s) = p1
    if sc_pat(s) > p2 then sc_pat(s) = p2
    sc_patDir(s) = 1

    sc_rate(s)  = rate
    sc_delay(s) = delay
    sc_skip(s)  = 0

    sc_flags(s) = flags
    sc_visible(s) = 1
end sub

' Equivalent of one SPRITE MOVE tick for sprite s
sub SpriteContinue_Tick(byval s as ubyte)
    if s >= SC_MAX then return
    if sc_visible(s) = 0 then return

    ' initial delay
    if sc_delay(s) <> 0 then
        sc_delay(s) = sc_delay(s) - 1
        return
    end if

    ' rate skipping: 0 = every tick, 1 = move every 2 ticks, etc.
    if sc_skip(s) <> 0 then
        sc_skip(s) = sc_skip(s) - 1
        return
    end if
    sc_skip(s) = sc_rate(s)

    dim moved as ubyte
    moved = 0

    ' X movement
    if sc_runX(s) <> 0 and sc_xs(s) <> 0 then
        sc_x(s) = sc_x(s) + sc_xs(s)
        moved = 1

        if sc_xs(s) > 0 then
            if sc_x(s) > sc_x2(s) then SpriteContinue_HitLimit(s, 1)
        else
            if sc_x(s) < sc_x1(s) then SpriteContinue_HitLimit(s, 1)
        end if
    end if

    ' Y movement
    if sc_runY(s) <> 0 and sc_ys(s) <> 0 then
        sc_y(s) = sc_y(s) + sc_ys(s)
        moved = 1

        if sc_ys(s) > 0 then
            if sc_y(s) > sc_y2(s) then SpriteContinue_HitLimit(s, 0)
        else
            if sc_y(s) < sc_y1(s) then SpriteContinue_HitLimit(s, 0)
        end if
    end if

    ' Pattern animation:
    ' - If bit6 set, animate even if not moved; otherwise animate only when moved.
    if (sc_p1(s) <> sc_p2(s)) then
        if ((sc_flags(s) BAND %01000000) <> 0) or (moved <> 0) then
            SpriteContinue_UpdatePattern(s)
        end if
    end if
end sub

' Push current state to hardware using NextLib UpdateSprite.
' patternOverride:
'   >= 0  use that pattern
'   <  0  use current sc_pat(s)
sub SpriteContinue_Apply( _
    byval s as ubyte, _
    byval spriteId as ubyte, _
    byval patternOverride as integer, _
    byval anchor as ubyte, _
    byval attr2 as ubyte _
)
    if s >= SC_MAX then return
    if sc_visible(s) = 0 then return

    dim ux as uinteger
    dim uy as ubyte
    dim pat as ubyte

    ux = sc_x(s)
    uy = sc_y(s)

    if patternOverride >= 0 then
        pat = patternOverride
    else
        pat = sc_pat(s)
    end if

    UpdateSprite(ux, uy, spriteId, pat, anchor, attr2)
end sub

' Convenience getters (optional)
function SpriteContinue_X(byval s as ubyte) as integer
    return sc_x(s)
end function

function SpriteContinue_Y(byval s as ubyte) as integer
    return sc_y(s)
end function

function SpriteContinue_Pattern(byval s as ubyte) as ubyte
    return sc_pat(s)
end function

'------------------------------------------------------------
' Internal helpers
'------------------------------------------------------------
sub SpriteContinue_UpdatePattern(byval s as ubyte)
    ' bit4: 0=cycle, 1=bounce
    if (sc_flags(s) BAND %00010000) = 0 then
        sc_pat(s) = sc_pat(s) + 1
        if sc_pat(s) > sc_p2(s) then sc_pat(s) = sc_p1(s)
    else
        sc_pat(s) = sc_pat(s) + sc_patDir(s)
        if sc_pat(s) > sc_p2(s) then
            sc_pat(s) = sc_p2(s)
            sc_patDir(s) = -sc_patDir(s)
        end if
        if sc_pat(s) < sc_p1(s) then
            sc_pat(s) = sc_p1(s)
            sc_patDir(s) = -sc_patDir(s)
        end if
    end if
end sub

' axis: 1 = X, 0 = Y
sub SpriteContinue_HitLimit(byval s as ubyte, byval axis as ubyte)
    dim mode as ubyte
    mode = sc_flags(s) BAND %00000011

    if mode = 0 then
        ' reflect
        if axis <> 0 then sc_xs(s) = -sc_xs(s) else sc_ys(s) = -sc_ys(s)

    elseif mode = 1 then
        ' stop this direction, start other direction
        if axis <> 0 then sc_runX(s) = 0 else sc_runY(s) = 0
        if axis <> 0 then sc_runY(s) = 1 else sc_runX(s) = 1

    elseif mode = 2 then
        ' stop this direction
        if axis <> 0 then sc_runX(s) = 0 else sc_runY(s) = 0

    else
        ' stop completely and make sprite invisible
        sc_runX(s) = 0 : sc_runY(s) = 0 : sc_visible(s) = 0
        RemoveSprite(s, 0)
    end if
end sub

#endif
