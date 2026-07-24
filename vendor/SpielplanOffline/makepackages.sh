#!/bin/bash

#Not yet well tested ...

#brew tap timsutton/formulae
#brew install brew-pkg
#brew pkg --with-deps ffmpeg


packages='gawk tesseract-deu ImageMagick'

oldpath=$PATH
MP_PREFIX=/opt/macports-hfalcke
export PATH=$MP_PREFIX/bin:$MP_PREFIX/sbin:$PATH

sudo port mpkg $packages

for f in $packages
do
    work=`port work $f`
    echo Copying ${f%} from $work
    mpkg=$work/$f*.mpkg
    cp $mpkg $dir/MacOS/Packages
done
ls $dir/MacOS/Packages/*.mpkg

cd $dir/MacOS
hdiutil create ./Packages.dmg -srcfolder ./Packages/ -ov
mv Packages.dmg  $dir

export PATH=$oldpath

