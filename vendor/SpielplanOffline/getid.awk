/fussball.de\/verein/ {if(match($0,"/id/[0-9A-Z]+")) VereinsID=substr($0,RSTART+4,RLENGTH-4)}
END{if (VereinsID) print VereinsID}
