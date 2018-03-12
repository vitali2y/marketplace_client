#
# Marketplace Client's libp2p-based peer
#

crypto = require "libp2p-crypto"
libp2p = require "libp2p"
PeerId = require "peer-id"
PeerInfo = require "peer-info"
multiaddr = require "multiaddr"
pull = require "pull-stream"
WSStar = require "libp2p-websocket-star"
MulticastDNS = require "libp2p-mdns"

Node = require "./libp2p-bundle"
proto = require "./proto"


class Peer

  constructor: ->
    @witnesses = []
    @browserPeerB58Id = undefined


  start: (@core, cb) ->
    PeerId.createFromJSON require(process.cwd() + "/" + @core.cfg.wallet.wallet), (err, @listenerId) =>
      if err
        cb err
        return
      listenerPeerInfo = new PeerInfo(@listenerId)
      listenerPeerInfo.multiaddrs.add multiaddr @core.cfg.rendezvous[0].uri
      ws = new WSStar(id: @listenerId)
      mdns = new MulticastDNS(listenerPeerInfo, { interval: 2000 })
      modules = 
        transport: [ ws ]
        mdns: mdns
        discovery: [ ws.discovery, mdns.discovery ]
      @listenerNode = new Node(listenerPeerInfo, undefined, modules)


      # browser's node requests for user's info
      @listenerNode.handle proto.PROTO_GET_MY_INFO, (protocol, conn) =>
        console.log 'PROTO_GET_MY_INFO: conn:', conn
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()
          @browserPeerB58Id = v.toString()   # getting browser's peer id inside PROTO_GET_MY_INFO request
          console.log '@browserPeerB58Id=', @browserPeerB58Id, typeof @browserPeerB58Id
          @core.getMyInfo()
        ), conn


      # respond with seller's info, if seller, to browser's node request 
      @listenerNode.handle proto.PROTO_GET_SELLER_INFO, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()
          @core.getSellerInfo()
        ), conn


      # node initiates witness searching
      @listenerNode.handle proto.PROTO_TX_STEP2, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()
          @core.fetchWitness()
        ), conn


      # step 3: witness obtained the transaction for spreading among buyer and seller
      @listenerNode.handle proto.PROTO_TX_STEP3, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, "v=", v.toString()
          t = JSON.parse(v.toString())

          # setting unique fields for all 3 parties
          # TODO: is it enough 16 digits for unique id? Less?
          t.id = crypto.randomBytes(16).toString('hex')
          t.ts = Math.floor((new Date).getTime() / 1000)

          # sending transaction to buyer for getting coins
          buyerB58String = t.buyer
          console.log 'buyerB58String=', buyerB58String

          # dialing to buyer
          buyerId = PeerId.createFromB58String buyerB58String
          buyerPeerInfo = new PeerInfo(buyerId)         
          @listenerNode.dialProtocol buyerPeerInfo, proto.PROTO_TX_STEP4, (err, connOut) =>
            if err is null
              tx = { data: JSON.stringify t }
              pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                console.log "#{proto.PROTO_TX_STEP4}: err:", err, "connIn:", connIn.toString()
                if err
                  cb err, connIn
                  return
                '{ "code": "77" }'
              )
            else
              # ignoring 'Error: "/new/0.0.1" not supported', etc
              m = /Error: (.*) not supported/i.exec err.toString()
              if m == null
                cb err, connOut
              else
                cb true, err.toString()


          # sending transaction to seller for getting URL
          sellerB58String = t.seller
          console.log 'sellerB58String=', sellerB58String

          # dialing to seller
          sellerId = PeerId.createFromB58String sellerB58String
          sellerPeerInfo = new PeerInfo(sellerId)         
          @listenerNode.dialProtocol sellerPeerInfo, proto.PROTO_TX_STEP5, (err, connOut) =>
            if err is null
              tx = { data: JSON.stringify t }
              pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                console.log "#{proto.PROTO_TX_STEP5}: err:", err, "connIn:", connIn.toString()
                if err
                  cb err, connIn
                  return
                '{ "code": "777" }'
              )
            else
              # ignoring 'Error: "/new/0.0.1" not supported', etc
              m = /Error: (.*) not supported/i.exec err.toString()
              if m == null
                cb err, connOut
              else
                cb true, err.toString()

          # TODO: @witness.manageTxByWitness(t) instead of next
          @core.manageTxByWitness t
        ), conn


      # step 4: witness dialed to buyer
      @listenerNode.handle proto.PROTO_TX_STEP4, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()

          cbNotification = (rslt) =>
            console.log "cbNotification (#{rslt})"

            # notification about successfully executed transaction to browser's node
            browserId = PeerId.createFromB58String @browserPeerB58Id
            browserPeerInfo = new PeerInfo(browserId)     
            @listenerNode.dialProtocol browserPeerInfo, proto.PROTO_TX_STEP6, (err, connOut) =>
              if err is null
                tx = { data: rslt }
                pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                  console.log "#{proto.PROTO_TX_STEP6}: err:", err, "connIn:", connIn.toString()
                  if err
                    cb err, connIn
                    return
                  '{ "code": "888" }'
                )
              else
                # ignoring 'Error: "/new/0.0.1" not supported', etc
                m = /Error: (.*) not supported/i.exec err.toString()
                if m == null
                  cb err, connOut
                else
                  cb true, err.toString()

          @core.proceedTxByBuyer v.toString(), cbNotification
        ), conn


      # step 5: witness dialed to seller
      @listenerNode.handle proto.PROTO_TX_STEP5, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()

          cbNotification = (rslt) =>
            console.log "cbNotification (#{rslt})"

          @core.proceedTxBySeller v.toString(), cbNotification
        ), conn


      # step 1: obtained the initial request for purchasing goods from browser's node
      @listenerNode.handle proto.PROTO_TX_STEP1, (protocol, conn) =>
        pull conn, pull.map((v) =>
          witnessB58String = @core.getWitness()

          # dialing to witness
          witnessId = PeerId.createFromB58String witnessB58String
          witnessPeerInfo = new PeerInfo(witnessId)
          @listenerNode.dialProtocol witnessPeerInfo, proto.PROTO_TX_STEP3, (err, connOut) =>
            if err is null
              tx = { data: v.toString() }
              pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                console.log "#{proto.PROTO_TX_STEP3}: err:", err, "connIn:", connIn.toString()
                if err
                  cb err, connIn
                  return
                '{ "code": "7" }'
              )
            else
              # ignoring 'Error: "/new/0.0.1" not supported', etc
              m = /Error: (.*) not supported/i.exec err.toString()
              if m == null
                cb err, connOut
              else
                cb true, err.toString()

          '{ "code": "17" }'
        ), conn


      # reacting on request from browser node for getting all transactions
      # TODO: only for requests from own browser
      @listenerNode.handle proto.PROTO_GET_ALL_TXS, (protocol, conn) =>
        @core.getAllTxsRequest null, (rslt, txId, txAll) =>
          # TODO: 2 chk rslt
          pull conn, pull.map((v) =>
            console.log "protocol:", protocol, 'v=', v.toString()
            return "{ \"code\": \"tututu\", \"data\": #{JSON.stringify(txAll)} }"
          ), conn


      @listenerNode.on 'peer:discovery', (peerDiscovered) =>
        idStr = peerDiscovered.id.toB58String()
        console.log 'discovered a peer:', idStr
        @listenerNode.dial peerDiscovered, (err, data) ->
          if err
            cb err, data
          return
        return


      @listenerNode.on 'peer:connect', (peerConnected) =>
        idStr = peerConnected.id.toB58String()
        console.log 'got connection to:', idStr

        # saving witness for further usage
        # TODO: to find witness in better way as PROTO_TX_STEP2, right before transaction?
        if @witnesses.length == 0
          @listenerNode.dialProtocol peerConnected, proto.PROTO_TX_STEP2, (err, connOut) =>
            if err is null
              tx = { data: 'get-witness' }
              pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                console.log "#{proto.PROTO_TX_STEP2}: err:", err, "connIn:", connIn.toString()
                if err
                  cb err, connIn
                  return
                t = JSON.parse(connIn.toString())
                if t.code == "0"
                  @core.setWitness t.witness
                '{ "code": "27" }'
              )
            else
              # ignoring 'Error: "/new/0.0.1" not supported', etc
              m = /Error: (.*) not supported/i.exec err.toString()
              if m == null
                cb err, connOut
              else
                cb true, err.toString()

        return


      @listenerNode.on 'peer:disconnect', (peerLost) ->
        idStr = peerLost.id.toB58String()
        console.log 'lost connection to:', idStr
        return


      @listenerNode.start (err) =>
        if err
          cb err
          return
        cb null, @listenerId.toB58String()


module.exports = Peer
