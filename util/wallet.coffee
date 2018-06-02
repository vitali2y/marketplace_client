#
# Marketplace Client's wallet
#

fs = require "fs"
low = require "lowdb"
# TODO: to use FileAsync
FileSync = require "lowdb/adapters/FileSync"
PeerId = require "peer-id"


class Wallet

  constructor: (@cfg, cb) ->
    fs.exists @cfg.wallet.wallet, (exists) =>
      if exists
        @wallet = low(new FileSync(@cfg.wallet.wallet))
        _w = @wallet.value()
        if not (_w.coins? and _w.id? and _w.privKey? and _w.pubKey?)
          console.log "looks, like broken #{@cfg.wallet.wallet}"
          return
        [ @cfg.user.balance, @cfg.user.id ] = [ _w["coins"], _w["id"] ]
        cb null, @wallet
      else
        PeerId.create { bits: 1024 }, (err, walletGenerated) =>
          if err
            throw err
          j = walletGenerated.toJSON()
          # default amount of coins for every new account
          j.coins = 5000
          # default 'qaz' password
          j.password = "8d6c5597d25eca212ea6c6cacc0a02e247b8c631343a70147cb81374ff72f414"
          fs.writeFileSync './wallet.json', JSON.stringify(j, null, 2)
          @wallet = low(new FileSync(@cfg.wallet.wallet))
          _w = @wallet.value()
          if not (_w.coins? and _w.id? and _w.privKey? and _w.pubKey?)
            console.log "looks, like broken #{@cfg.wallet.wallet} wallet"
            return
          [ @cfg.user.balance, @cfg.user.id ] = [ _w["coins"], _w["id"] ]
          cb null, @wallet


module.exports = Wallet
