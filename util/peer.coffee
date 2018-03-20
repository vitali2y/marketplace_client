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


  # ignoring 'Error: "/new/0.0.1" not supported', 'Error: Circuit not enabled!', etc
  ignoreNotSupported: (err, cb) ->
    console.log "ignoreNotSupported (#{err}, <cb>)"
    cb null, err.toString()


  start: (@core, cb) ->
    PeerId.createFromJSON require(process.cwd() + "/" + @core.cfg.wallet.wallet), (err, @clientId) =>
      if err
        cb err
        return
      clientPeerInfo = new PeerInfo(@clientId)
      clientPeerInfo.multiaddrs.add multiaddr @core.cfg.rendezvous[0].uri
      ws = new WSStar(id: @clientId)
      mdns = new MulticastDNS(clientPeerInfo, { interval: 2000 })
      modules = 
        transport: [ ws ]
        mdns: mdns
        discovery: [ ws.discovery, mdns.discovery ]
      @clientNode = new Node(clientPeerInfo, undefined, modules)


      # browser's node requests for user's info
      @clientNode.handle proto.PROTO_GET_MY_INFO, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()
          @browserPeerB58Id = v.toString()   # getting browser's peer id inside PROTO_GET_MY_INFO request
          console.log 'browserPeerB58Id=', @browserPeerB58Id
          @core.getMyInfo()
        ), conn


      # respond with seller's info, if seller, to browser's node request 
      @clientNode.handle proto.PROTO_GET_SELLER_INFO, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()
          @core.getSellerInfo()
        ), conn


      # step 1: obtained the initial request for purchasing goods from browser's node
      @clientNode.handle proto.PROTO_TX_STEP1, (protocol, conn) =>
        pull conn, pull.map((v) =>
          witnessB58String = @core.getWitness()

          # dialing to witness
          witnessId = PeerId.createFromB58String witnessB58String
          witnessPeerInfo = new PeerInfo(witnessId)
          @clientNode.dialProtocol witnessPeerInfo, proto.PROTO_TX_STEP3, (err, connOut) =>
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
              @ignoreNotSupported err, cb
              return
          '{ "code": "17" }'
        ), conn


      # step 2: node initiates witness searching
      @clientNode.handle proto.PROTO_TX_STEP2, (protocol, conn) =>
        console.log 'myPeerB58Id=', @clientNode.peerInfo.id.toB58String()
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()
          @core.fetchWitness()
        ), conn


      # step 3: witness obtained the transaction for spreading among buyer and seller
      @clientNode.handle proto.PROTO_TX_STEP3, (protocol, conn) =>
        console.log 'myPeerB58Id=', @clientNode.peerInfo.id.toB58String()
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, "v=", v.toString()
          t = JSON.parse(v.toString())

          # setting unique fields for all 3 parties
          # TODO: is it enough 16 digits for unique id? Less?
          t.id = crypto.randomBytes(16).toString('hex')
          t.ts = Math.floor((new Date).getTime() / 1000)

          # sending transaction to buyer for getting coins
          buyerB58Id = t.buyer
          console.log 'buyerB58Id=', buyerB58Id

          # dialing to buyer with new transaction
          buyerId = PeerId.createFromB58String buyerB58Id
          buyerPeerInfo = new PeerInfo(buyerId)         
          @clientNode.dialProtocol buyerPeerInfo, proto.PROTO_TX_STEP4, (err, connOut) =>
            if err is null
              tx = { data: JSON.stringify(t) }
              pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                console.log "#{proto.PROTO_TX_STEP4}: err:", err, "connIn:", connIn.toString()
                if err
                  cb err, connIn
                  return
                '{ "code": "77" }'
              )
            else
              @ignoreNotSupported err, cb
              return

          # sending transaction to seller for getting URL
          sellerB58Id = t.seller
          console.log 'sellerB58Id=', sellerB58Id

          # dialing to seller with new transaction
          sellerId = PeerId.createFromB58String sellerB58Id
          sellerPeerInfo = new PeerInfo(sellerId)         
          @clientNode.dialProtocol sellerPeerInfo, proto.PROTO_TX_STEP5, (err, connOut) =>
            if err is null
              tx = { data: JSON.stringify(t) }
              pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                console.log "#{proto.PROTO_TX_STEP5}: err:", err, "connIn:", connIn.toString()
                if err
                  cb err, connIn
                  return
                '{ "code": "777" }'
              )
            else
              @ignoreNotSupported err, cb
              return

          # TODO: @witness.savePrivateTx(t) instead of @core.savePrivateTx(t)?
          @core.savePrivateTx t, (err) =>
            # stripping down the privacy sensitive data
            # TODO: to delete all except some predefined fields?
            strippedT = Object.assign({}, t)
            strippedT.witness = [ @clientNode.peerInfo.id.toB58String() ]
            delete strippedT.price
            delete strippedT.file_id
            delete strippedT.store_id
            @core.savePublicTx strippedT, (err) =>
              # syncing private ledger's transaction among other public blockchain nodes
              for p of @clientNode.peerBook._peers
                console.log "peer to share with:", p
                publicId = PeerId.createFromB58String p
                publicPeerInfo = new PeerInfo(publicId)
                console.log 'publicPeerInfo:', JSON.stringify publicPeerInfo
                @clientNode.dialProtocol publicPeerInfo, proto.PROTO_SYNC_TX, (err, connOut) =>
                  if err is null
                    tx = { data: JSON.stringify(strippedT) }
                    pull pull.values(tx), connOut, pull.collect((err, connIn) =>
                      console.log "#{proto.PROTO_SYNC_TX}: err:", err, "connIn:", connIn.toString()
                      if err
                        cb err, connIn
                        return
                      '{ "code": "999" }'
                    )
                  else
                    @ignoreNotSupported err, cb
                    return
          '{ "code": "0" }'
        ), conn


      # step 4: buyer was dialed by witness with a new transaction
      @clientNode.handle proto.PROTO_TX_STEP4, (protocol, conn) =>
        console.log 'myPeerB58Id=', @clientNode.peerInfo.id.toB58String()
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()

          cbProceedTxByBuyer = (rslt) =>
            console.log "cbProceedTxByBuyer (#{rslt})"

            # notification about successfully executed transaction to browser's node
            browserId = PeerId.createFromB58String @browserPeerB58Id
            browserPeerInfo = new PeerInfo(browserId)     
            @clientNode.dialProtocol browserPeerInfo, proto.PROTO_TX_STEP6, (err, connOut) =>
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
                @ignoreNotSupported err, cb
            return

          @core.proceedTxByBuyer v.toString(), cbProceedTxByBuyer
        ), conn


      # step 5: seller was dialed by witness with a new transaction
      @clientNode.handle proto.PROTO_TX_STEP5, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()

          cbProceedTxBySeller = (rslt) =>
            console.log "cbProceedTxBySeller (#{rslt})"
            return rslt

          @core.proceedTxBySeller v.toString(), cbProceedTxBySeller
        ), conn


      # getting new public blockchain transaction for keeping on my node
      @clientNode.handle proto.PROTO_SYNC_TX, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "protocol:", protocol, 'v=', v.toString()

          cbSyncNewPublicTx = (rslt) =>
            console.log "cbSyncNewPublicTx (#{rslt})"
            return rslt

          @core.syncNewPublicTx v.toString(), cbSyncNewPublicTx
        ), conn


      # reacting on request from browser node for getting all private transactions
      # TODO: only for requests from own browser
      @clientNode.handle proto.PROTO_GET_ALL_PRIVATE_TXS, (protocol, conn) =>
        @core.getAllPrivateTxsRequest (err, txAll) =>
          # TODO: 2 chk err
          pull conn, pull.map((v) =>
            console.log "protocol:", protocol, 'v=', v.toString()
            return "{ \"code\": \"tututu\", \"data\": #{JSON.stringify(txAll)} }"
          ), conn


      # reacting on request from browser node for getting all public transactions
      # TODO: only for requests from own browser
      @clientNode.handle proto.PROTO_GET_ALL_PUBLIC_TXS, (protocol, conn) =>
        @core.getAllPublicTxsRequest (err, txAll) =>
          # TODO: 2 chk err
          pull conn, pull.map((v) =>
            console.log "protocol:", protocol, 'v=', v.toString()
            return "{ \"code\": \"tututu\", \"data\": #{JSON.stringify(txAll)} }"
          ), conn


      @clientNode.on 'peer:discovery', (peerDiscovered) =>
        idStr = peerDiscovered.id.toB58String()
        console.log 'discovered a peer:', idStr
        # # TODO: peers are not removed upon 'Login As' or UI refresh - why?
        # for p of @clientNode.peerBook._peers
        #   console.log "peer:", p
        @clientNode.dial peerDiscovered, (err, data) ->
          if err
            cb err, data
          return
        return


      @clientNode.on 'peer:connect', (peerConnected) =>
        idStr = peerConnected.id.toB58String()
        console.log 'got connection to:', idStr

        # saving witness for further usage
        # TODO: to find witness in better way as PROTO_TX_STEP2, right before transaction?
        if @witnesses.length == 0
          @clientNode.dialProtocol peerConnected, proto.PROTO_TX_STEP2, (err, connOut) =>
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
              @ignoreNotSupported err, cb
        return


      @clientNode.on 'peer:disconnect', (peerLost) ->
        idStr = peerLost.id.toB58String()
        console.log 'lost connection to:', idStr
        return


      @clientNode.start (err) =>
        if err
          console.log 'hmmm, err on start:', err
        cb null, @clientId.toB58String()


module.exports = Peer
