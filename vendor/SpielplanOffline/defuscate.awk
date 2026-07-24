BEGIN{
    if (codetablefile) {
        while ((getline < codetablefile)>0) {
            codetable[$1]=substr($0,6,1)
        }
    }

    codetable["007C"]="|"
    codetable["0020"]=" "

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

    FS=">"
    RS="<"
    OFS=">"
    ORS="<"
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

    if ( fn == fontnumber) {
        ncodes=split($2,codes," *; *")
#    print "ncodes",ncodes
        for (i=1;i<=ncodes;i++) {
            if (codes[i] ~ "..x[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]") {
                hexcode=substr(codes[i],4)
                HEXCODE=toupper(hexcode)
                if (HEXCODE in codetable) {
                    sub("[&]#x" hexcode ";",codetable[HEXCODE])
                }
            }
        }
    }
}

{print}

