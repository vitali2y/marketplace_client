#!/bin/sh

mkdir ./dist/linux/store_bob ./dist/linux/store_james ./dist/linux/store_ragnar
mkdir ./dist/windows/store_bob ./dist/windows/store_james ./dist/windows/store_ragnar
cp ./cfg/* ./dist/linux
cp ./cfg/* ./dist/windows
RED='\033[0;31m'; GREEN='\033[0;32m'; NOCOLOR='\033[0m'; echo -e "${RED}Attention:${GREEN} do not forget to put preliminary some files into 'stores' ('store_bob', 'store_james', and 'store_ragnar') dirs!${NOCOLOR}"
