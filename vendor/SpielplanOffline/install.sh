#!/bin/bash
#Man braucht diese Programme zusätzlich und muss sie von Hand installieren, bzw. dieses Skript ausführen

if [ -f ~/.profile ]; then source ~/.profile; fi
if [ -f ~/.bash_profile ]; then source ~/.bash_profile; fi

echo $PATH

echo "Installiere die fehlenden Pakete für SpielplanOffline, falls nötig."
BREW=`which brew`
WGET=`which wget`
AWK=`which gawk`
OCR=`which tesseract`
#CONVERT=`which convert`


if [ "X$BREW" = X  ]; then
    echo "Installiere Homebrew Package-Manager"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [ "X$WGET" = X ]; then
    echo brew install wget
fi
exit

if  [ "X$AWK" = X ]; then
    brew install gawk
fi

if  [ "X$OCR" = X ]; then
    brew install tesseract
fi

exit

#Rest ist für MacOS Developer:
#brew install platypus #Create Max Apps
brew install platypus
sudo mkdir /usr/local/share
sudo cp -r /opt/homebrew/share/platypus /usr/local/share
brew install create-dmg
brew install dos2unix
brew install --cask pashua

# Windows
#https://eternallybored.org/misc/wget/
