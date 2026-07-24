#corrects some common mistakes of the OCR software
{
    gsub("[?]"," ")
    gsub("MO","Mo")
    gsub("DO","Do")
    gsub("SO","So")
    gsub("Mo,","Mo.")
    gsub("Di,","Di.")
    gsub("Mi,","Mi.")
    gsub("Do,","Do.")
    gsub("Fr,","Fr.")
    gsub("Sa,","Sa.")
    gsub("So,","Do.")
    s=gensub("\\<([0-9][0-9])2([0-9][0-9])\\>","\\1:\\2","g") 
    print s
}
