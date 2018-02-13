#
# Marketplace Client's Private Ledger
#

CryptoJS = require "crypto-js"
levelup = require "levelup"
leveldown = require "leveldown"


# TODO: class Ledger extends levelup
class Ledger

  constructor: (root, @latest) ->
    @ledger = levelup(leveldown(root))
    @get("genesis", (err, val) =>
      if err == null and val == null
        @put("genesis", null, (err) =>    # genesis block init
          console.log "genesis: err=", err
        )
    )



  get: (key, cb) ->
    @ledger.get(key, (err, val) ->
      if err
        if err.notFound
          cb null, null
        else
          console.log('failed to read from private ledger:', err)
          cb err
        return
      console.log "get: val=", val.toString()
      cb null, JSON.parse(val)
    )



  put: (key, val, cb) ->
    console.log "put (#{key}, #{JSON.stringify(val)}, <cb>)"

    _calculateHash = (record) ->
      CryptoJS.SHA256(JSON.stringify(record)).toString()

    if key == "genesis"
      val = {}
      val.id = key
      val.buyer = null
      val.store_id = null
      val.price = 0

    val.prev_id = @latest.get("latest").value()["id"]
    val.ts = Math.floor((new Date).getTime() / 1000)
    val.hash = _calculateHash val
    console.log "saving:", JSON.stringify(val)
    @ledger.put(key, JSON.stringify(val), (err) =>
      if err
        console.log('failed to write to private ledger:', err)
        cb err
        return
      @latest.get("latest").assign({ id: key, ts: Math.floor((new Date).getTime() / 1000) }).write()
      console.log "new latest:", @latest.get("latest").value()

      # gathering all txs under "My Transactions"
      txAll = []
      @ledger.createReadStream().on('data', (data) ->
        _tx = {}
        _d = JSON.parse(data.value.toString())
        for v of _d
          _tx[v] = _d[v]
        txAll.push(_tx) 
        return
      ).on 'end', ->
        console.log "current ledger:", txAll
        cb null, key, txAll
        return
    )


module.exports = Ledger
