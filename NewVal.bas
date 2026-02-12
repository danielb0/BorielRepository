'!org=24576
#include <nextlib.bas>
#include <input.bas>

'!nb=autostart(dir=/games,copy=/nextzxos/autoexec.bas,sync=all)

dim Z as float
paper 7:ink 0
cls
print "Hello World!"
a$=input(4)
print "A$= ";a$
Z = VAL (a$)
PRINT "Z= ";Z

do 

loop 
