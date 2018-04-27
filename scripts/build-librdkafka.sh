#!/bin/bash

RDKAFKA_VER="7478b5ef16aadd6543fe38bc6a2deb895c70da98"

PRJ=$PWD
DST="$PRJ/.librdkafka"
VERSION_FILE="$DST/version.txt"

if [ -f $VERSION_FILE ]; then
    echo "Found librdkafka: $(cat $VERSION_FILE), expected: $RDKAFKA_VER"
else
    echo "librdkafka not found in $DST"
fi

if [ -f $VERSION_FILE ] && [ "$(cat $VERSION_FILE)" == $RDKAFKA_VER ]; then
    echo "Required version found, using it"
    sudo cp -r $DST/* /usr/
    exit 0
fi

echo "Making librdkafka ($RDKAFKA_VER)"
SRC=`mktemp -d 2>/dev/null || mktemp -d -t 'rdkafka'`
git clone https://github.com/edenhill/librdkafka "$SRC"
cd $SRC
git reset $RDKAFKA_VER --hard

./configure --prefix $DST
cd src
make && make install
find $DST/lib -type f -executable | xargs strip

sudo cp -r $DST/* /usr/

echo "Writing version file to $VERSION_FILE"
echo $RDKAFKA_VER > $VERSION_FILE
