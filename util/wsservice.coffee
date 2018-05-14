#
# Marketplace Client's websocket service module
#

crypto = require "libp2p-crypto"
WebSocket = require 'ws'


class WSService

  constructor: (@port, @globalEmitter) ->
    @ws = undefined
    @globalEmitter.on 'transfer-received', (tx) =>
      console.log 'on transfer-received:', tx
      @respOk { id: JSON.parse(tx).id }


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

    # TODO: avoid duplication
    getUniqueId = ->
      crypto.randomBytes(16).toString('hex')  

    if data.action?
      data.data.id = getUniqueId()
    data.data.ts = Math.floor((new Date).getTime() / 1000)
    if @ws?
      @ws.send JSON.stringify(data)


  sendReq: (action, data) ->
    @sendRaw { action: action, data: data }


  respOk: (data) ->
    @sendRaw { code: 0, data: data }


  respNg: (code, data) ->
    @sendRaw { code: code, data: data }


module.exports = WSService
