#!/bin/sh

#
# Script for setting the production environment
#

# configuring network environment
rm -f ./util/netconf.coffee
cp ./scripts/netconf_prod.coffee.tmpl ./util/netconf.coffee

# avoiding usage of local rendezvous server, but external one
(cd ./dist && for c in ./*/*/config.toml; do sed -i -e 's/.*\/dns4\/localhost\/tcp\/61617.*/uri = "\/dns4\/ws-star-signal-4.servep2p.com\/tcp\/443\/wss\/p2p-websocket-star"/' $c; done && cd -)
