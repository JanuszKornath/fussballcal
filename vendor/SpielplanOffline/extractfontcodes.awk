BEGIN{

#FS="<[^>]+>"
    FS=">"
    RS="<"
    exclude["007C"]=""
    exclude["002D"]=""

    hexary["0"]=0
    hexary["1"]=1
    hexary["2"]=2
    hexary["3"]=3
    hexary["4"]=4
    hexary["5"]=5
    hexary["6"]=6
    hexary["7"]=7
    hexary["8"]=8
    hexary["9"]=9
    hexary["A"]=10
    hexary["B"]=11
    hexary["C"]=12
    hexary["D"]=13
    hexary["E"]=14
    hexary["F"]=15

    for (i=0;i<=9;i++) {hexbase[i]=16^(i)}
}

function HEX2NUM(hexcode)
{
    result=0
    split(hexcode,digits,"")
    len=length(hexcode); 
    for (hxi=1;hxi<=len;hxi++) {result+=hexary[toupper(digits[hxi])]*hexbase[len-hxi]}
    return result
}

#/data-obfuscation/{print $0; print $1 "," $2 "," $3 "," $4 "," $5}

/data-obfuscation="[0-9a-zA-Z]+"/{
    match($1,"data-obfuscation=\"[0-9a-zA-Z]+\"")
    fn=substr($0,RSTART+18,RLENGTH-18-1)
    hexfile=tmpdir "hexcodes-" fn ".txt"
    utffile=tmpdir "utfcodes-" fn ".awk.txt"
    perlfile=tmpdir "utfcodes-" fn ".perl"

    if ( ! ( fn in fontnumbers) ) {
        fontnumbers[fn]=fn
        printf (sep "%s",fn); sep="," # no separator for first font
        printf ("%s","") > hexfile
        printf ("%s","") > utffile
        printf ("%s","binmode(STDOUT, \":utf8\"); \n") > perlfile
#        close(utffile)
#        system ("rm -f " utffile)
    }

    ncodes=split($2,codes," *; *")
#    print "ncodes",ncodes
    printf("%s","print \"") >> perlfile 
    for (i=1;i<=ncodes;i++) {
        if (codes[i] ~ "..x[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]") {
            hexcode=toupper(substr(codes[i],4))
            if (!(hexcode in exclude)) {
                if (hexcode == "0020"){
                    printf ("\n") >> hexfile
                    printf ("\n") >> utffile
                    printf ("%s","\\n") >> perlfile 

                } else {
#                    print i,hexcode,HEX2NUM(hexcode)
                    printf ("%s ",hexcode) >> hexfile
                    printf ("%c",HEX2NUM(hexcode)) >> utffile
                    printf ("%s","\\x{" hexcode "}") >> perlfile 
#		             printf ("%s","\\x{" hexcode "} ") >> perlfile 
#                    system("perl -e 'binmode(STDOUT, \":utf8\"); print \"\\x{" hexcode "}\"' >>  " utffile)
                }
            }
        }
    }
    print "" >> hexfile
    print "" >> utffile
    print "\\n\";" >> perlfile
#    system("perl -e 'binmode(STDOUT, \":utf8\"); print \"\\n\"' >>  " utffile) 
}

END{
    print ""
    close (hexfile)
    close (utffile)
    close (perlfile)
}


