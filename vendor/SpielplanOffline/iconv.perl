#
#bin\perlbin\perl iconv.perl spielplan-1-fc-koeln-1-fc-koeln-mittelrhein-EXCEL2.csv test.csv
open my $INFILE,  '<:utf8',  $ARGV[0]; 
open my $OUTFILE, '>',  $ARGV[1];

while (my $line = <$INFILE>) {
    #$line =~ s/[^\x010000-\xffffff]//g; #removes all 3 byte unicode characters (not 0-128 ASCII) 
    #$line =~ s/\xe2\x80\x93//g; #Trying to remove a three-byte unicode - doesn't work 
    print $OUTFILE $line;
}
