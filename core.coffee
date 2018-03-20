#
# Marketplace Client's core module
#

class Core

  constructor: (@cfg, @user, @wallet, @ledger, @blockchain) ->


  getMyInfo: ->
    console.log "getMyInfo ())"
    @user.user.balance = @wallet.value().coins
    JSON.stringify @user


  getSellerInfo: ->
    console.log "getSellerInfo ()"
    if @user.user.mode == 'seller'
      JSON.stringify({ stores: [ @user.stores ] })
    else
      '{ "stores": [] }'


  fetchWitness: ->
    console.log "fetchWitness ()"
    if @user.user.mode == 'witness'
      console.log "fetchWitness: { \"code\": \"0\", \"witness\": \"#{@user.user.id}\" }"
      return "{ \"code\": \"0\", \"witness\": \"#{@user.user.id}\" }"
    else
      return '{ "code": "1" }'


  setWitness: (@witnessAddress) ->
    console.log "setWitness (#{@witnessAddress})"


  getWitness: ->
    @witnessAddress


  # witness saves transaction obtained from buyer into private ledger
  savePrivateTx: (tx, cb) ->
    console.log "savePrivateTx (#{JSON.stringify tx}, <cb>)"
    @ledger.put(tx, (err, txAll) ->
      console.log "savePrivateTx: err=", err, "txId=", tx.id, "txAll=", txAll
      if err
        console.log 'failed to write to private ledger:', err
        return
      console.log "success: txId:", tx.id, "txAll:", txAll
      cb err
    )


  # witness saves transaction obtained from buyer into public blockchain
  savePublicTx: (tx, cb) ->
    console.log "savePublicTx (#{JSON.stringify tx}, <cb>)"
    @blockchain.put(tx, (err, txAll) ->
      console.log "savePublicTx: err=", err, "txId=", tx.id, "txAll=", txAll
      if err
        console.log 'failed to write to public blockchain:', err
        return
      console.log "success: txId:", tx.id, "txAll:", txAll
      cb err
    )


  proceedTxByBuyer: (tx, cb) ->
    console.log "proceedTxByBuyer (#{tx}, <cb>)"
    tx = JSON.parse tx
    
    # updating buyer's wallet
    @wallet.update('coins', (n) ->
      n -= tx.price
    ).write()

    @ledger.put(tx, (err, txAll) ->
      if err
        console.log 'failed to write to private ledger:', err
        return
      console.log "success: txId:", tx.id, "txAll:", txAll
      cb("{ \"code\": \"0\", \"id\": \"#{tx.id}\" }")
    )


  proceedTxBySeller: (tx, cb) ->
    console.log "proceedTxBySeller (#{tx}, <cb>)"
    tx = JSON.parse tx
    
    # updating seller's wallet
    @wallet.update('coins', (n) ->
      n += tx.price
    ).write()

    @ledger.put(tx, (err, txAll) ->
      if err
        console.log 'failed to write to private ledger:', err
        return
      console.log "success: txId:", tx.id, "txAll:", txAll
      cb("{ \"code\": \"0\", \"id\": \"#{tx.id}\" }")
    )


  getAllPrivateTxsRequest: (cb) ->
    console.log "getAllPrivateTxsRequest (<cb>)"
    @ledger.getAll (err, txAll) ->
      console.log "getAllPrivateTxsRequest: err=", err, "txAll=", txAll
      cb err, txAll


  getAllPublicTxsRequest: (cb) ->
    console.log "getAllPublicTxsRequest (<cb>)"
    @blockchain.getAll (err, txAll) ->
      console.log "getAllPublicTxsRequest: err=", err, "txAll=", txAll
      cb err, txAll


  syncNewPublicTx: (tx, cb) ->
    console.log "syncNewPublicTx (#{JSON.stringify tx}, <cb>)"
    tx = JSON.parse tx

    @blockchain.put(tx, (err, txAll) ->
      if err
        console.log 'failed to write to public blockchain:', err
        return
      console.log "success: txId:", tx.id, "txAll:", txAll
      cb("{ \"code\": \"0\", \"id\": \"#{tx.id}\" }")
    )


module.exports = Core
