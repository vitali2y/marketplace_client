#
# Marketplace Client's websocket service module
#

crypto = require "libp2p-crypto"
WebSocket = require "ws"


class WSService

  constructor: (@port, @globalEmitter) ->

    # respond to wallet about finished transfer transaction
    @globalEmitter.on 'transfer-received', (tx) =>
      console.log 'on transfer-received:', tx
      @respOk { id: JSON.parse(tx).id }

    # request to wallet for balance increasing
    @globalEmitter.on 'increaseBalance', (tx) =>
      console.log 'on increaseBalance:', tx
      t = JSON.parse tx
      @sendRaw { action: 'increaseBalance', id: t.id, amount: t.amount }

    # request to wallet for balance decreasing
    @globalEmitter.on 'decreaseBalance', (tx) =>
      console.log 'on decreaseBalance:', tx
      t = JSON.parse tx
      @sendRaw { action: 'decreaseBalance', id: t.id, amount: t.amount }


  # starting up the websockets service
  start: ->
    wss = new (WebSocket.Server)(port: @port)
    console.log 'websockets service is started up'
    wss.on 'connection', (ws) =>
      if @ws?
        txRes =
          info: 'already connected'
        @respNg 1, txRes
        return
      # TODO: only one wallet connection
      @ws = ws
      @ws.on 'message', (msgStred) =>
        msg = JSON.parse msgStred
        if msg.action?
          console.log 'new ws call:', msg
          if not msg.data.id?
            txRes =
              error: 'no id'
            @respNg 1, txRes
            return
          switch msg.action
            when 'transfer'
              @globalEmitter.emit 'transfer', msg.data
            else
              txRes =
                info: 'wrong command'
              @respNg 1, txRes
          return
        else
          if msg.code?
            console.log 'a confirmation:', msg
          else
            txRes =
              info: 'wrong format'
            @respNg 1, txRes
      @ws.on 'close', =>
        @ws = undefined
        console.log 'ws client disconnected'
        return


  sendRaw: (data) ->
    console.log "sendRaw (#{JSON.stringify data})"
    if @ws?
      @ws.send JSON.stringify(data)


  send: (data) ->

    # TODO: avoid duplication
    getUniqueId = ->
      crypto.randomBytes(16).toString('hex')  

    if data.action?
      data.data.id = getUniqueId()
    data.data.ts = Math.floor((new Date).getTime() / 1000)
    @sendRaw data


  sendReq: (action, data) ->
    @send { action: action, data: data }


  respOk: (data) ->
    @send { code: 0, data: data }


  respNg: (code, data) ->
    @send { code: code, data: data }


module.exports = WSService
