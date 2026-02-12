'!org 24576

#define NEX                                 ' Include data in NEX
#include <Nextlib.bas>
BORDER 0:PAPER 0:ink 1
cls
'CLS256(7)
InitLayer2(MODE256X192)
ClearLayer2(0)
LoadSDBank("[]font3.spr",0,0,0,35)
L2Text(0,0,"HELLO FROM NEXTBUILD!",35,0)
do:loop
