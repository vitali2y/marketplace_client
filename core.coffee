#
# Marketplace Client's core module
#

fs = require "fs"
readChunk = require "read-chunk"
fileType = require "file-type"

WSService = require "./util/wsservice"
proto = require "./util/proto"


class Core

  constructor: (@globalEmitter, @cfg, @user, @wallet, @ledger, @blockchain) ->
    # for keeping the state
    @user.state = {}
    @user.state[proto.PROTO_BOOTSTRAP] = false

    # starting up the websockets-based API service
    # TODO: security:
    # http://simplyautomationized.blogspot.com/2015/09/5-ways-to-secure-websocket-rpi.html
    # https://gist.github.com/jfromaniello/8418116
    # https://gist.github.com/subudeepak/9897212#websockets---security-overview
    if @cfg.user.mode in [ 'seller', 'buyer' ] and @cfg.api.port?
      new WSService(@cfg.api.port, @globalEmitter).start()


  getMyInfo: ->
    console.log "getMyInfo ()"
    @user.user.balance = @wallet.value().coins
    @user


  getWhoAreYou: (thisB58Id, thisLocation) ->
    console.log "getWhoAreYou (#{thisB58Id}, #{thisLocation})"
    rslt =
      code: 0
      id:       thisB58Id
      nick:     @user.user.name
      pub:      @wallet.value().pubKey
      mode:     @user.user.mode
      location: thisLocation
    if rslt.mode == 'seller'
      rslt.stores = [ @user.stores ]
    rslt


  # witness saves transaction obtained from buyer into private ledger
  savePrivateTx: (tx, cb) ->
    console.log "savePrivateTx (#{JSON.stringify tx}, <cb>)"

    # stripping down the privacy sensitive data
    # TODO: to delete all except some predefined fields?
    strippedTx = Object.assign({}, tx)
    delete strippedTx.price
    delete strippedTx.size
    delete strippedTx.file_id
    delete strippedTx.store_id

    @ledger.put(tx, (err, txAll) ->
      if err
        console.log 'failed to write to private ledger:', err
        return
      cb err, strippedTx
    )


  # witness saves transaction obtained from buyer into public blockchain
  savePublicTx: (tx, cb) ->
    console.log "savePublicTx (#{JSON.stringify tx}, <cb>)"

    @blockchain.put(tx, (err, txAll) ->
      if err
        console.log 'failed to write to public blockchain:', err
        return
      cb err, tx
    )


  proceedTxByBuyer: (tx, cb) ->
    console.log "proceedTxByBuyer (#{JSON.stringify tx}, <cb>)"

    # decreasing balance on buyer's wallet
    # TODO: to move to wallet app
    if tx.price?
      @wallet.value().coins -= tx.price
    else
      if tx.amount?
        @wallet.value().coins -= tx.amount
    @wallet.write()    

    # stripping down the privacy sensitive data
    # TODO: to delete all except some predefined fields?
    strippedTx = Object.assign({}, tx)
    delete strippedTx.sys
    delete strippedTx.hosted

    @ledger.put(strippedTx, (err, txAll) ->
      if err
        console.log 'failed to write to private ledger:', err
        return
      cb err, strippedTx
    )


  proceedTxBySeller: (tx, cb) ->
    console.log "proceedTxBySeller (#{JSON.stringify tx}, <cb>)"

    # increasing balance on seller's wallet
    # TODO: to move to wallet app
    if tx.price?
      @wallet.value().coins += tx.price
    else
      if tx.amount?
        @wallet.value().coins += tx.amount
    @wallet.write()    

    # stripping down the privacy sensitive data
    # TODO: to delete all except some predefined fields?
    strippedTx = Object.assign({}, tx)
    delete strippedTx.sys
    delete strippedTx.hosted

    @ledger.put(strippedTx, (err, txAll) ->
      if err
        console.log 'failed to write to private ledger:', err
        cb err
        return
      rslt =
        code: 0
        id: strippedTx.id
      cb err, rslt
    )


  getAllPrivateTxsRequest: (cb) ->
    console.log "getAllPrivateTxsRequest (<cb>)"
    @ledger.getAll "genesis", (err, txAll) ->
      cb err, txAll


  getAllPublicTxsRequest: (cb) ->
    console.log "getAllPublicTxsRequest (<cb>)"
    @blockchain.getAll "genesis", (err, txAll) ->
      cb err, txAll


  getPurchasedRequest: (cb) ->
    console.log "getPurchasedRequest (<cb>)"

    getFileIcon = (mime) ->
      type = "question-circle-o"
      switch mime.split("/")[0]
        when "video"
          type = "file-video-o"
        when "audio"
          type = "file-audio-o"
        when "text"
          type = "file-text-o"
        when "image"
          type = "picture-o"
      type

    fs.readdir './purchased', (err, files) =>
      if err
        console.log 'failed to read from dir:', err
        cb err
        return
      filesContent = []
      for f in files
        # when purchased ordinary file
        if /(.[0-Z])\w+.json/g.exec(f) == null
          stats = fs.statSync './purchased/' + f
          console.log f, 'err=', err, 'stats:', stats

          fileContent = 
            file_name: f
            ts: parseInt(stats.ctimeMs) / 1000
            size: stats.size

          t = fileType(readChunk.sync('./purchased/' + f, 0, 4100))
          if t == null
            console.log 'oops, not recognized mime for', f
            # TODO: to recognized mime by extension?
            fileContent.mime = "application/unknown"
          else
            fileContent.mime = t.mime
        # when purchased online file (in JSON format)
        else
          content = fs.readFileSync './purchased/' + f
          fileContent = JSON.parse content.toString()
          fileContent.mime = "application/unknown"

        fileContent.type = getFileIcon fileContent.mime
        filesContent.push fileContent
      cb null, filesContent


  syncNewPublicTx: (tx, cb) ->
    console.log "syncNewPublicTx (#{JSON.stringify tx}, <cb>)"
    @blockchain.put(tx, (err, txAll) ->
      if err
        console.log 'failed to write to public blockchain:', err
        cb err
        return
      rslt =
        code: 0
        id: tx.id
      cb rslt
    )


module.exports = Core
