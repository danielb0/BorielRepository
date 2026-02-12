#include<Nextlib.bas>
#include <input.bas>


'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)

#define NEX
#define IM2

' From the Terminal Menu pick Run Build Task or CTRL+SHFT+B

' build address 
'!org=24576
' From the Terminal menu pick Run Build Task or press control+shift+b



dim n as String
dim number as ubyte
paper 7:ink 0
cls
print "Hello There World!"

do 
    ink 0
    paper 7
    border 6
    n = input(12)
    print  n
    number=val (n) 
    print  "This is the value of the string: " + str(number)
    if number = 10 then 
        print  "Number is 10"
    else 
        print  "Number is not 10"
    endif
loop 
 