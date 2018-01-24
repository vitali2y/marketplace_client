#!/bin/sh

#
# Script for preparing the binary builds
#

rm -rf ./build
mkdir ./build
cp ./package.json ./build

TARGETS="node6-linux-x64"
(cd ./build; ../node_modules/.bin/coffee -o . -c ../client.coffee; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 1; fi; \
	../node_modules/.bin/pkg --targets $TARGETS --output ./client-linux-x64.bin ./package.json; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 2; fi; \
	cp ./client-linux-x64.bin ..; echo "./build/client-linux-x64.bin: done"; cd -)

TARGETS="node6-win-x86"
(cd ./build; ../node_modules/.bin/coffee -o . -c ../client.coffee; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 1; fi; \
	../node_modules/.bin/pkg --targets $TARGETS --output ./client-win-x86.exe  ./package.json; if [ $? -ne 0 ]; then echo 'failed!!!'; cd -; exit 2; fi; \
	cp ./client-win-x86.exe ..; echo "./build/client-win-x86.exe: done"; cd -)

GREEN='\033[0;32m'; NOCOLOR='\033[0m'
echo "so, at the beginning start server (Linux ${GREEN}server-linux-x64.bin${NOCOLOR} or, Winduz ${GREEN}server-win-x86.exe${NOCOLOR})"

echo -e "@ Linux:"
echo "run sellers first:"
echo -e "${GREEN}client_bob.sh client_james.sh client_ragnar.sh${NOCOLOR}"
echo "... then buyer:"
echo -e "${GREEN}client_alice.sh${NOCOLOR}"

echo -e "@ Winduz:"
echo "run sellers first:"
echo -e "${GREEN}client_bob.bat client_james.bat client_ragnar.bat${NOCOLOR}"
echo "... then buyer:"
echo -e "${GREEN}client_alice.bat${NOCOLOR}"
