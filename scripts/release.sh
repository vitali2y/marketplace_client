#!/bin/sh

#
# Script for preparing client's binary builds
#

mkdir -p ./build

cp ./package.json ./build

MAJOR_VERSION=$(node -v | awk '{ split($0,v,"."); print substr(v[1], 2) }')

(cd ./build &&
mkdir -p util blockchain service && ../node_modules/.bin/coffee -o . -c ../*.coffee && ../node_modules/.bin/coffee -o ./util -c ../util/*.coffee &&
../node_modules/.bin/coffee -o ./service ../service/*.coffee &&
../node_modules/.bin/coffee -o ./blockchain -c ../blockchain/*.coffee &&
# adding name, version number, and timestamp for output during booting
cat ../package.json | ../node_modules/.bin/json -A -a description version | awk -F, 'BEGIN { "date +%y%m%d-%H%M" | getline d } { print "console.log(\""$0" ("d") is starting...\");" }' > ./client.js.tmp && cat ./client.js >> ./client.js.tmp && mv ./client.js.tmp ./client.js &&
APP_NAME="client-linux-x64.bin" && TARGET="node"$MAJOR_VERSION"-linux-x64" && echo $APP_NAME && ../node_modules/.bin/pkg --targets $TARGET --output ./$APP_NAME ./package.json &&
mv ./$APP_NAME ../dist/linux &&
APP_NAME="client-macos-x64.bin" && TARGET="node"$MAJOR_VERSION"-macos-x64" && echo $APP_NAME && ../node_modules/.bin/pkg --targets $TARGET --output ./$APP_NAME ./package.json &&
mv ./$APP_NAME ../dist/darwin &&
APP_NAME="client-win-x86.exe" && TARGET="node"$MAJOR_VERSION"-win-x86" && echo $APP_NAME && ../node_modules/.bin/pkg --targets $TARGET --output ./$APP_NAME ./package.json &&
mv ./$APP_NAME ../dist/windows &&
cd -)
if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 1; fi

if [ "$(uname)" = "Linux" ]; then 
    cp ./node_modules/leveldown/build/Release/leveldown.node ./dist/linux
fi
if [ "$(uname)" = "Darwin" ]; then 
    cp ./node_modules/leveldown/build/Release/leveldown.node ./dist/darwin
fi
# TODO: 'npm install leveldown' @ Windows

GREEN='\033[0;32m'; NOCOLOR='\033[0m'
echo "@ Linux & Mac OS X:"
echo "Before running just copy both ${GREEN}client-*-x64.bin${NOCOLOR} and ${GREEN}leveldown.node${NOCOLOR} into every user's folder under ${GREEN}./dist/*${NOCOLOR} folder"
echo "run sellers first:"
echo "${GREEN}client_bob.sh client_james.sh client_tom.sh${NOCOLOR}"
echo "and:"
echo "${GREEN}client_cl-1.sh${NOCOLOR}"
echo "... and finally a buyer:"
echo "${GREEN}client_alice.sh${NOCOLOR}"

echo "@ Winduz:"
echo "Before running just copy both ${GREEN}client-win-x86.exe${NOCOLOR} and ${GREEN}leveldown.node${NOCOLOR} into every user's folder under ${GREEN}./dist/windows${NOCOLOR} folder"
echo "run sellers first:"
echo "${GREEN}client_bob.bat client_james.bat client_tom.bat${NOCOLOR}"
echo "and:"
echo "${GREEN}client_cl-1.bat${NOCOLOR}"
echo "... and finally a buyer:"
echo "${GREEN}client_alice.bat${NOCOLOR}"

echo "open https://127.0.0.1:43443/?QmdFdWtiC9HdNWvRH3Cih9hJhLvRZmsDutz549s25CtQ61"
