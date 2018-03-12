#!/bin/sh

#
# Postinstall script
#

mkdir -p ./dist/linux/bob/store_bob ./dist/linux/james/store_james ./dist/linux/tom/store_tom
mkdir -p ./dist/darwin/bob/store_bob ./dist/darwin/james/store_james ./dist/darwin/tom/store_tom
mkdir -p ./dist/windows/bob/store_bob ./dist/windows/james/store_james ./dist/windows/tom/store_tom

(cd ./cfg; for f in ./*; do cp $f/* ../dist/linux/$f; done; cd -)
(cd ./cfg; for f in ./*; do cp $f/* ../dist/darwin/$f; done; cd -)
(cd ./cfg; for f in ./*; do cp $f/* ../dist/windows/$f; done; cd -)

(cd ./dist/$(uname -s | awk '{ print tolower($0) }'); mkdir -p ./alice/blockchain ./bob/blockchain ./james/blockchain ./tom/blockchain ./cl-1/blockchain; cd -)

RED='\033[0;31m'; GREEN='\033[0;32m'; NOCOLOR='\033[0m'; echo -e "${RED}Attention:${GREEN} do not forget to put preliminary some files into 'stores' ('store_bob', 'store_james', and 'store_tom') dirs!${NOCOLOR}"
