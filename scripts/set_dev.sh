#!/bin/sh

#
# Script for setting the development environment
#

# configuring network environment
rm -f ./util/netconf.coffee
cp ./scripts/netconf_dev.coffee.tmpl ./util/netconf.coffee

# configuring clients (with local rendezvous server)
(cd ./cfg; for f in ./*; do mkdir -p ../dist/linux/$f; cp $f/* ../dist/linux/$f; done; cd -)
(cd ./cfg; for f in ./*; do mkdir -p ../dist/darwin/$f; cp $f/* ../dist/darwin/$f; done; cd -)
(cd ./cfg; for f in ./*; do mkdir -p ../dist/windows/$f; cp $f/* ../dist/windows/$f; done; cd -)
