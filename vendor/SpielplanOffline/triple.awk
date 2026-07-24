#{print $0}
BEGIN{if (endline<=startline) {nosplit=1}}
( (NR>=startline && NR<=endline) || nosplit ) {
    if (length > 0) {print; print; print}  # " " $0 " " $0 " " $0
}
#{print $0 $0 $0 $0 }
