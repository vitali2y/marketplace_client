#
# Marketplace Client's core module
#

class Core

  constructor: (@cfg, @user, @wallet, @ledger) ->


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


  # witness manages transaction obtained from buyer
  manageTxByWitness: (tx) ->
    console.log "manageTxByWitness (#{tx})"

    @ledger.put(tx.id, tx, (rslt, txId, txAll) ->
      console.log "manageTxByWitness: rslt=", rslt, "txId=", txId, "txAll=", txAll
      if rslt
        console.log 'failed to write to private ledger:', rslt
        return
      console.log "success: txId:", txId, "txAll:", txAll
    )

    '{ "code": "0" }'


  proceedTxByBuyer: (tx, cb) ->
    console.log "proceedTxByBuyer (#{tx}, <cb>)"
    tx = JSON.parse tx

    @wallet.update('coins', (n) ->
      console.log 'n=', n
      n -= tx.price
    ).write()

    @ledger.put(tx.id, tx, (rslt, txId, txAll) ->
      console.log "proceedTxByBuyer: rslt=", rslt, "txId=", txId, "txAll=", txAll
      if rslt
        console.log 'failed to write to private ledger:', rslt
        return
      console.log "success: txId:", txId, "txAll:", txAll
      cb("{ \"code\": \"0\", \"id\": \"#{txId}\" }")
    )
    '{ "code": "0" }'


  proceedTxBySeller: (tx, cb) ->
    console.log "proceedTxBySeller (#{tx}, <cb>)"
    tx = JSON.parse tx

    @wallet.update('coins', (n) ->
      console.log 'n=', n
      n += tx.price
    ).write()

    @ledger.put(tx.id, tx, (rslt, txId, txAll) ->
      console.log "proceedTxBySeller: rslt=", rslt, "txId=", txId, "txAll=", txAll
      if rslt
        console.log 'failed to write to private ledger:', rslt
        return
      console.log "success: txId:", txId, "txAll:", txAll
      cb("{ \"code\": \"0\", \"id\": \"#{txId}\" }")
    )
    '{ "code": "0" }'


  getAllTxsRequest: (something, cb) ->
    console.log "getAllTxsRequest (<cb>)"
    @ledger.getAll null, (rslt, txId, txAll) ->
      console.log "getAllTxsRequest: rslt=", rslt, "txId=", txId, "txAll=", txAll
      cb rslt, txId, txAll


module.exports = Core
