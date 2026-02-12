dim VarBasic as ubyte=0
VarBasic=VarBasic+0
do
    'print at 0,0;"VarBasic = ";VarBasic;" "
    asm
        ld hl,_VarBasic
        inc (hl)
    end asm
loop