#!/bin/sh

#
# Script for preparing the binary builds
#

rm -rf ./build
mkdir ./build
cp ./package.json ./build

if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 1; fi

(cd ./build &&
mkdir util blockchain && ../node_modules/.bin/coffee -o . -c ../*.coffee && ../node_modules/.bin/coffee -o ./util -c ../util/*.coffee && ../node_modules/.bin/coffee -o ./blockchain -c ../blockchain/*.coffee &&
APP_NAME="client-linux-x64.bin" && TARGETS="node8-linux-x64" && ../node_modules/.bin/pkg --targets $TARGETS --output ./$APP_NAME ./package.json &&
mv ./$APP_NAME ../dist/linux &&
APP_NAME="client-macos-x64.bin" && TARGETS="node8-macos-x64" && ../node_modules/.bin/pkg --targets $TARGETS --output ./$APP_NAME ./package.json &&
mv ./$APP_NAME ../dist/darwin &&
APP_NAME="client-win-x86.exe" && TARGETS="node8-win-x86" && ../node_modules/.bin/pkg --targets $TARGETS --output ./$APP_NAME ./package.json &&
mv ./$APP_NAME ../dist/windows &&
cd -)

cp ./node_modules/leveldown/build/Release/leveldown.node ./dist/linux
# TODO: 'npm install leveldown' @ Mac OS X
# TODO: 'npm install leveldown' @ Windows

GREEN='\033[0;32m'; NOCOLOR='\033[0m'
echo -e "@ Linux & Mac OS X:"
echo "Before running just copy both client-*-x64.bin and leveldown.node into every user's folder under ./dist/* folder"
echo "run sellers first:"
echo -e "${GREEN}client_bob.sh client_james.sh client_tom.sh${NOCOLOR}"
echo "and:"
echo -e "${GREEN}client_cl-1.sh${NOCOLOR}"
echo "... and finally a buyer:"
echo -e "${GREEN}client_alice.sh${NOCOLOR}"

echo -e "@ Winduz:"
echo "Before running just copy both client-win-x86.exe and leveldown.node into every user's folder under ./dist/windows folder"
echo "run sellers first:"
echo -e "${GREEN}client_bob.bat client_james.bat client_tom.bat${NOCOLOR}"
echo "and:"
echo -e "${GREEN}client_cl-1.bat${NOCOLOR}"
echo "... and finally a buyer:"
echo -e "${GREEN}client_alice.bat${NOCOLOR}"

echo "open http://127.0.0.1:3000/?QmdFdWtiC9HdNWvRH3Cih9hJhLvRZmsDutz549s25CtQ61"
