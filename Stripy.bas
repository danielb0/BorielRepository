'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)
#include<NextLib.bas>
#include<sinclair.bas>

 
declare function GetCPUSpeed() as ubyte

dim speed as ubyte
dim baseHL as uinteger
dim stripeHL as uinteger
dim testInt as ubyte
dim testIntAddress as uinteger
'dim spstr as string

testInt = 45

testIntAddress = @testInt

print "TestInt address = ";testIntAddress

spstr$ = input(3)

speed = val(spstr$)

runAT(speed)

speed =  GetCPUSpeed()
print "CPU Speed = ";speed
baseHL=55
stripeHL = baseHL * (1 << speed)  ' scale for 7/14/28
print "stripeHL= ";stripeHL

asm     
        DI
        LD E,0
        EI

LOOP:
        HALT                ; sync to frame

        LD D,32            ; number of stripes this frame

STRIPE:
        LD A,E
        AND 7
        OUT ($FE),A         ; border colour
        INC E

        ; 16-bit delay using HL (does NOT interfere with D)
        LD HL,(_stripeHL)     ; stripe thickness (tweak this)
        
DLY:
        DEC HL
        LD A,H
        OR L
        JR NZ,DLY

        DEC D
        JR NZ,STRIPE

        ; check SPACE once per frame
        CALL SPACEDOWN
        JR NZ,LOOP

        RET

SPACEDOWN:
        LD BC,$7FFE
        IN A,(C)
        AND 1
        RET
 end asm

function GetCPUSpeed() as ubyte
asm
        ld bc,$243B
        ld a,7
        out (c),a          ; select NextReg $07

        ld bc,$253B
        in a,(c)           ; read value

        and 3              ; bits 1..0 = speed
end asm
end function





