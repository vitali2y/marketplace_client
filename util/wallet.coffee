#
# Marketplace Client's wallet
#

low = require "lowdb"
# TODO: to use FileAsync
FileSync = require "lowdb/adapters/FileSync"


class Wallet

  constructor: (cfg) ->
    @wallet = low(new FileSync(cfg.wallet.wallet))
    _w = @get().value()
    if not (_w.coins? and _w.id? and _w.privKey? and _w.pubKey?)
      console.log "looks, like broken #{cfg.wallet.wallet}"
      return
    [ cfg.user.balance, cfg.user.id ] = [ _w["coins"], _w["id"] ]


  get: ->
    @wallet # .value()


module.exports = Wallet
