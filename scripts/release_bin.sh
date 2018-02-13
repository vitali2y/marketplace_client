#!/bin/sh

#
# Script for preparing the binary builds
#

rm -rf ./build
mkdir ./build
cp ./package.json ./build

if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 1; fi

TARGETS="node6-linux-x64"
(cd ./build; ../node_modules/.bin/coffee -o . -c ../client.coffee  ../ledger.coffee; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 1; fi; \
	../node_modules/.bin/pkg --targets $TARGETS --output ./client-linux-x64.bin ./package.json; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 2; fi; \
	mv ./client-linux-x64.bin ../dist/linux; echo "./dist/linux/client-linux-x64.bin: done"; cd -)

TARGETS="node6-win-x86"
(cd ./build; ../node_modules/.bin/coffee -o . -c ../client.coffee  ../ledger.coffee; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 1; fi; \
	../node_modules/.bin/pkg --targets $TARGETS --output ./client-win-x86.exe  ./package.json; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 2; fi; \
	mv ./client-win-x86.exe ../dist/windows; echo "./dist/windows/client-win-x86.exe: done"; cd -)

cp ./cfg/* ./dist/linux
cp ./cfg/* ./dist/windows

GREEN='\033[0;32m'; NOCOLOR='\033[0m'
echo -e "@ Linux:"
echo "run sellers first:"
echo -e "${GREEN}client_bob.sh client_james.sh client_tom.sh${NOCOLOR}"
echo "... and finally a buyer:"
echo -e "${GREEN}client_alice.sh${NOCOLOR}"

echo -e "@ Winduz:"
echo "run sellers first:"
echo -e "${GREEN}client_bob.bat client_james.bat client_tom.bat${NOCOLOR}"
echo "... and finally a buyer:"
echo -e "${GREEN}client_alice.bat${NOCOLOR}"

echo "open http://127.0.0.1:3000/?64489c85dc2fe0787b85cd87214b3810"
