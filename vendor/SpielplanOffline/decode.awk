BEGIN{
#    hexcodefile="hexcodes-1460.txt"
#    codetablefile="codetable-1460.txt"
    if (codetablefile) {
        while ((getline < codetablefile)>0) {
            codetable[$1]=substr($0,6,10)
        }
    }
}

/^ *$/{next}

{
#    gsub(" ","")
    gsub("[? ]","")
    cleartext=$0
    do {
        getline < hexcodefile
        gsub("0020 *","")
    }
    while ($0 ~ "^ *$")
#    print cleartext
#    print $0
    for (i=1;i<=length(cleartext);i++) {
        c=substr(cleartext,i,1)
#Poor man's multibyte / UTF character treatement
	if (c > "~") {
	    c=substr(cleartext,i,2)
	    cleartext=substr(cleartext,1,i) substr(cleartext,i+2) 
	}
        code=$i
        codetable[code]=c codetable[code]
    }
}

END{
    for (code in codetable) {
        delete count
        maxcount=0
        characters=codetable[code]
        len=length(characters)
        for (i=1;i<=len;i++) {
            char=substr(characters,i,1)
            count[char]=count[char]+1
        }
        for (char in count) {
            if (count[char]>maxcount) {
                mostpopularcharacter=char
                maxcount=count[char]
            }
        }
        print code,mostpopularcharacter characters
    }
}
