#
# Marketplace Client's levelup-based storage
#

# TODO: how about to avoid CryptoJS?
CryptoJS = require "crypto-js"
levelup = require "levelup"
leveldown = require "leveldown"


class Storage

  constructor: (root) ->
    @storage = levelup(leveldown(root))
    @get("genesis", (err, tx) =>
      if err == null and tx == null
        @put({ id: "genesis" }, (err) =>    # genesis block init
          console.log "genesis (#{root}): err=", err
        )
    )


  calculateHash: (record) ->
    CryptoJS.SHA256(JSON.stringify(record)).toString()


  getGenesis: ->
    tx = {}
    tx.id = "genesis"
    tx.prev_id = "genesis"
    tx.ts = Math.floor((new Date).getTime() / 1000)
    tx.hash = @calculateHash tx
    tx


  # get transaction from the store by 'key' id
  get: (key, cb) ->
    console.log "get (#{key}, <cb>)"
    @storage.get(key, (err, tx) ->
      if err
        if err.notFound
          cb null, null
        else
          console.log('failed to read from storage:', err)
          cb err
        return
      cb null, JSON.parse(tx)
    )


  # gathering all txs for displaying under "My Transactions"
  getAll: (cb) ->
    txAll = []
    @storage.createReadStream().on('data', (data) ->
      tx = {}
      d = JSON.parse(data.value.toString())
      for v of d
        tx[v] = d[v]
      txAll.push(tx) 
      return
    ).on 'end', ->
      cb null, txAll
      return


  # save transaction into the store
  put: (tx, cb) ->
    console.log "put (#{JSON.stringify(tx)}, <cb>)"
    key = tx.id

    _saveTx = =>
      @storage.put(key, JSON.stringify(tx), (err) =>
        if err
          console.log('failed to write to storage:', err)
          cb err
          return
        @getAll cb
      )

    if key == "genesis"
      tx = @getGenesis()
      _saveTx()
      return

    # getting id of the latest transaction
    @storage.createReadStream({ limit: 1 })
      .on('error', (err) =>
        console.log 'storage error:', err
        cb err
        return
      )
      .on('data', (data) =>
        # console.log "latest:", data.key.toString(), '=', data.value.toString()
        tx.prev_id = data.key.toString()
        tx.hash = @calculateHash tx
        # console.log "saving tx:", JSON.stringify(tx)
        _saveTx()
        return
      )


module.exports = Storage
