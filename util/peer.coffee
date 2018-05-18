#
# Marketplace Client's libp2p-based peer
#

fs = require "fs"
os = require "os"
request = require "request"
crypto = require "libp2p-crypto"
libp2p = require "libp2p"
PeerId = require "peer-id"
PeerInfo = require "peer-info"
multiaddr = require "multiaddr"
WSStar = require "libp2p-websocket-star"
MulticastDNS = require "libp2p-mdns"
pull = require "pull-stream"
Transform = require('stream').Transform

Node = require "./libp2p-bundle"
proto = require "./proto"
FileTransfer = require "./filetransfer"


# setting unique fields for all 3 parties
# TODO: is it enough 16 digits for unique id? Less?
getUniqueIds = ->
  [ crypto.randomBytes(16).toString('hex'), Math.floor((new Date).getTime() / 1000) ]


class Peer

  constructor: ->
    @witnesses = []
    @browserPeerB58Id = undefined


  # ignoring 'Error: "/new/0.0.1" not supported', 'Error: Circuit not enabled!', etc
  ignoreNotSupported: (err, cb) ->
    console.log "ignoreNotSupported (#{err}, <cb>)"
    # cb null, err.toString()
    return


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
      clientNode = new Node(clientPeerInfo, undefined, modules)

      ft = new FileTransfer()

      doTransfer = (tx) ->
        console.log 'transfer request here:', tx, typeof tx
        recipientPeerB58Id = tx.recipientAddr
        recipientId = PeerId.createFromB58String recipientPeerB58Id
        recipientPeerInfo = new PeerInfo(recipientId)
        console.log 'recipientPeerB58Id=', recipientPeerB58Id
        # TODO: to sign transaction by private key before sending it
        clientNode.dialProtocol recipientPeerInfo, proto.PROTO_TRANSFER1, (err, connOut) =>
          if err is null
            pull pull.values([ JSON.stringify(tx) ]), connOut, pull.collect((err, connIn) =>
              console.log "<== #{proto.PROTO_TRANSFER1}: err:", err, "connIn:", JSON.parse(connIn.toString())
              if err
                cb err, connIn
                return
              @core.proceedTxByBuyer JSON.parse(v.toString()), (err, rslt) ->
                return JSON.stringify(rslt)
            )
          else
            ignoreNotSupported err, cb
        # TODO: avoid displaying this 721 exit code on toaster
        return '{ "code": "721" }'


      # watch on external 'transfer' request in order to do a coins transfer to another address
      @core.globalEmitter.on 'transfer', (tx) =>
        doTransfer tx


      # transfer step 1: sender's transferred coins arrived to recipient
      clientNode.handle proto.PROTO_TRANSFER1, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          @core.proceedTxBySeller JSON.parse(v.toString()), (err, rslt) =>
            # TODO: find better way to get sender's address instead of this dirty hacking
            q = JSON.stringify conn
            senderPeerB58Id = q[(q.search /"peerInfo":{"id":{"id":"Qm/)+24..(q.search /"peerInfo":{"id":{"id":"Qm/)+23+46]
            senderId = PeerId.createFromB58String senderPeerB58Id
            senderPeerInfo = new PeerInfo(senderId)
            clientNode.dialProtocol senderPeerInfo, proto.PROTO_TRANSFER2, (err, connOut) =>
              if err is null
                pull pull.values([ v.toString() ]), connOut, pull.collect((err, connIn) =>
                  console.log "<== #{proto.PROTO_TRANSFER2}: err:", err, "connIn:", JSON.parse(connIn.toString())
                  if err
                    cb err, connIn
                    return
                  return connIn.toString()
                )
              else
                ignoreNotSupported err, cb
        ), conn


      # transfer step 2: sender gets confirmation about transferred coins from recipient
      clientNode.handle proto.PROTO_TRANSFER2, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          @core.proceedTxByBuyer JSON.parse(v.toString()), (err, rslt) =>

            # sending notification about successfully executed transfer to browser's node
            browserId = PeerId.createFromB58String @browserPeerB58Id
            browserPeerInfo = new PeerInfo(browserId)     
            clientNode.dialProtocol browserPeerInfo, proto.PROTO_TRANSFER_WEB3, (err, connOut) =>
              if err is null
                pull pull.values([ "Coins transfer has been executed successfully " +
                  "(transaction ##{rslt.id} in {duration} ms)" ]), connOut, pull.collect((err, connIn) =>
                    console.log "<== #{proto.PROTO_TRANSFER_WEB3}: err:", err, "connIn:", connIn.toString()
                    if err or JSON.parse(connIn.toString()).code != 0
                      console.log 'ouch, error'
                )
              else
                @ignoreNotSupported err, cb

            @core.globalEmitter.emit 'transfer-received', v.toString()
            return JSON.stringify(v.toString())
        ), conn
        return '{ "code": "731" }'


      # watch on a coins transfer request from a browser in order to transfer to another address
      clientNode.handle proto.PROTO_TRANSFER_WEB1, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          doTransfer JSON.parse(v.toString())
        ), conn


      # executing request from browser's node for user's info
      clientNode.handle proto.PROTO_GET_MY_INFO, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          @browserPeerB58Id = v.toString()   # getting browser's peer id inside PROTO_GET_MY_INFO request
          return JSON.stringify(@core.getMyInfo())
        ), conn
        return '{ "code": "771" }'


      # "who-are-you" request
      clientNode.handle proto.PROTO_WHORU, (protocol, conn) =>

        callWRU = (ipInfo) =>
          console.log 'ipInfo:', ipInfo
          pull conn, pull.map((v) =>
            console.log "==>", protocol, 'v=', v.toString()
            # console.log "ping:", new Date() - new Date(v.toString())
            return JSON.stringify(@core.getWhoAreYou(clientNode.peerInfo.id.toB58String(), ipInfo.city + ', ' + ipInfo.country))
          ), conn

        try
          # TODO: 'Rate limit exceeded. Subscribe to a paid plan to increase your usage limits at http://ipinfo.io/pricing' ,
          # https://github.com/fiorix/freegeoip as an alternative?
          request 'https://ipinfo.io/json', (err, res, body) ->
            ipInfo = JSON.parse body
            callWRU ipInfo
        catch err
          console.log 'geo service error:', err
          ipInfo =
            city: '?'
            country: '?'
          callWRU ipInfo
        return '{ "code": "772" }'


      # purchase step 1: buyer's host gets the initial request for purchasing goods from buyer's browser
      clientNode.handle proto.PROTO_PURCHASE1, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          txOrg = Object.assign({}, JSON.parse(v.toString()))
          [ txOrg.id, txOrg.ts ] = getUniqueIds()
          tx = Object.assign({}, txOrg)

          # preparing transactions per witnesses
          txs = []
          cnt = -1
          chunk = -1
          position = 0
          for w in txOrg.witness
            t = Object.assign({}, txOrg)
            t.sys = {}

            [ t.sys.price, t.sys.position, t.sys.chunk, t.sys.size ] =
              [ parseInt(txOrg.price / txOrg.witness.length), position, chunk += 1, parseInt(txOrg.size / txOrg.witness.length) ]

            # special processing for online file - pass info about it as JSON file
            if t.hosted == 'online'
              t.file_name += '.' + t.id[0..7] + '.json'
              # online file only thru a single witness for now
              for vv in t.witness
                if t.witness.length > 1
                  t.witness.splice(0, 1)
              t.sys.price = t.sys.price
              t.sys.price += txOrg.price % txOrg.witness.length
              t.sys.size = JSON.stringify(t).length
              txs[0] = Object.assign({}, t)
              console.log "txs[0]:", txs[0]
              break
            position += t.sys.size
            if (cnt += 1) == txOrg.witness.length - 1    # some extra adjustment for the last witness in list
              t.sys.price += txOrg.price % txOrg.witness.length
              t.sys.size += txOrg.size % txOrg.witness.length

            txs[cnt] = Object.assign({}, t)
            console.log "txs[#{cnt}] (for #{w} witness):", txs[cnt]

          # dialing to witnesses one-by-one with unique chunk's transaction to initiate the purchase
          txs[0].witness.forEach (w, index) =>
            witnessId = PeerId.createFromB58String(w)
            witnessPeerInfo = new PeerInfo(witnessId)
            clientNode.dialProtocol witnessPeerInfo, proto.PROTO_PURCHASE2, (err, connOut) =>
              if err is null
                console.log "dialing to ##{index} witness", w, "with:", JSON.stringify(txs[index])
                pull pull.values([ JSON.stringify(txs[index]) ]), connOut, pull.collect((err, connIn) =>
                  console.log "<== #{proto.PROTO_PURCHASE2}: err:", err, "connIn:", connIn.toString()
                  if err
                    console.log 'ouch, error'
                )
              else
                @ignoreNotSupported err, cb
          return '{ "code": "073" }'
        ), conn
        return '{ "code": "773" }'


      # purchase step 2: witness gets the transaction from buyer to copy file from seller to buyer
      clientNode.handle proto.PROTO_PURCHASE2, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, "v=", v.toString()
          tx = JSON.parse(v.toString())
          console.log protocol, 'tx:', tx

          # witness dials to seller for pulling the chunk
          sellerB58Id = tx.seller
          sellerId = PeerId.createFromB58String sellerB58Id
          sellerPeerInfo = new PeerInfo(sellerId)
          clientNode.dialProtocol sellerPeerInfo, proto.PROTO_PURCHASE3, (err, connOut) =>
            if err is null
              # TODO: how about to avoid keeping temp chunk, but to pass it further directly to buyer?
              ft.initPullFile connOut, tx, (err, v) =>
                if err
                  console.log 'err=', err
                  cb err

                ft.writeChunksToFile 'transferred/' + tx.id + '.' + tx.sys.chunk, v, (err, fileName) =>
                  # witness dials to buyer for pushing the chunk pulled from seller
                  # TODO: how to avoid this dialing by returning stream to the initial dial?
                  buyerId = PeerId.createFromB58String tx.buyer
                  buyerPeerInfo = new PeerInfo(buyerId) 
                  clientNode.dialProtocol buyerPeerInfo, proto.PROTO_PURCHASE4, (err, connOut) =>
                    ft.initPushFile connOut, tx, (err, chunk) =>
                      console.log 'initPushFile: err=', err, 'chunk:', chunk
            else
              @ignoreNotSupported err, cb
          return '{ "code": "074" }'
        ), conn
        return '{ "code": "774" }'


      # purchase step 3: seller was dialed by witness to handle a new transaction
      clientNode.handle proto.PROTO_PURCHASE3, (protocol, conn) =>
        ft.execPullFile conn, @core.user.stores.root, (err, data) =>
          console.log 'write: err=', err, 'data=', data
        return '{ "code": "775" }'


      # purchase step 4: buyer was dialed by witness for pushing the chunk preliminary obtained from seller
      clientNode.handle proto.PROTO_PURCHASE4, (protocol, conn) =>

        confirmAndNotify = (chunk) =>
          console.log "confirmAndNotify (#{JSON.stringify chunk})"
          # TODO: find better way to get witness-confirmer's address instead of this dirty hacking
          q = JSON.stringify conn
          confirmerPeerB58Id = q[(q.search /"peerInfo":{"id":{"id":"Qm/)+24..(q.search /"peerInfo":{"id":{"id":"Qm/)+23+46]
          console.log 'confirmerPeerB58Id=', confirmerPeerB58Id

          # buyer sends confirmation about successfully executed transaction to witness-confirmer
          confirmerId = PeerId.createFromB58String confirmerPeerB58Id
          confirmerPeerInfo = new PeerInfo(confirmerId)
          @core.proceedTxByBuyer chunk, (err, strippedChunk) =>
            clientNode.dialProtocol confirmerPeerInfo, proto.PROTO_PURCHASE5, (err, connOut) =>
              @core.savePrivateTx strippedChunk, (err) =>
                if err is null
                  pull pull.values([ JSON.stringify(strippedChunk) ]), connOut, pull.collect((err, connIn) =>
                    console.log "<== #{proto.PROTO_PURCHASE5}: err:", err, "connIn:", connIn.toString()
                    if err
                      console.log 'ouch, error'
                  )
                else
                  @ignoreNotSupported err, cb
                  return '{ "code": "076" }'

                # sending notification about successfully executed transaction to browser's node
                browserId = PeerId.createFromB58String @browserPeerB58Id
                browserPeerInfo = new PeerInfo(browserId)     
                clientNode.dialProtocol browserPeerInfo, proto.PROTO_PURCHASE7, (err, connOut) =>
                  if err is null
                    console.log 'strippedChunk:', strippedChunk
                    console.log "File '#{strippedChunk.file_name}' has been successfully purchased " +
                      "(transaction ##{strippedChunk.id} in {duration} ms)"
                    # TODO: to pass both strippedChunk.id & strippedChunk.file_name only
                    pull pull.values([ "File '#{strippedChunk.file_name}' has been successfully purchased " +
                      "(transaction ##{strippedChunk.id} in {duration} ms)" ]), connOut, pull.collect((err, connIn) =>
                        console.log "<== #{proto.PROTO_PURCHASE7}: err:", err, "connIn:", connIn.toString()
                        if err or JSON.parse(connIn.toString()).code != 0
                          console.log 'ouch, error'
                    )
                  else
                    @ignoreNotSupported err, cb
          return '{ "code": "077" }'

        ft.execPushFile conn, (err, chunk) =>

          class FixerTransform extends Transform

            constructor: (opt) ->
              super opt

            _transform: (chunk, encoding, callback) ->
              @push Buffer.from(chunk.toString().replace(/[^\x01-\x7F]/g, ""), 'utf8')

          fixer = new FixerTransform()
          console.log 'execPushFile: err=', err, 'chunk:', JSON.stringify chunk

          fileName = chunk.file_name
          if chunk.hosted == "online"
            fs.createReadStream(os.tmpdir() + '/' + chunk.id + '.0')
              # TODO: to avoid this fixer workaround
              .pipe(fixer)
              .pipe(fs.createWriteStream('./purchased/' + fileName))
            confirmAndNotify chunk
          else
            if fs.existsSync './purchased/' + fileName
              c = 0

              nextCopyName = ->
                # TODO: what if no 'dot'?
                n = chunk.file_name.split "."
                n[n.length - 2] += "(#{c += 1})"
                fileName = n.join(".")
                return

              # finding an unique name in case if such file name is already exist
              nextCopyName()  while fs.existsSync './purchased/' + fileName
            console.log "expecting amount of chunks:", chunk.witness.length
            # TODO: what if lst file is blocked (by whom?)?
            # TODO: to chk size additionally?
            fs.appendFileSync os.tmpdir() + '/' + chunk.id + '.lst', chunk.sys.chunk + ',' + chunk.sys.size + '\n'
            chunkAmount = fs.readFileSync(os.tmpdir() + '/' + chunk.id + '.lst').toString().split("\n").length - 1
            if chunkAmount == chunk.witness.length
              for c in [0..chunkAmount - 1]
                content = fs.readFileSync os.tmpdir() + '/' + chunk.id + '.' + c
                # TODO: to avoid hardcoded folders
                fs.appendFileSync './purchased/' + fileName, content
                fs.unlinkSync os.tmpdir() + '/' + chunk.id + '.' + c
              fs.unlinkSync os.tmpdir() + '/' + chunk.id + '.lst'
              confirmAndNotify chunk
            else
              console.log 'not a time for chunks merging, have just', chunkAmount
        return '{ "code": "776" }'


      # purchase step 5: last witness-confirmer gets confirmation from buyer about successfully executed transaction
      clientNode.handle proto.PROTO_PURCHASE5, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          tx = JSON.parse v.toString()

          # calling seller to update the private ledger
          sellerId = PeerId.createFromB58String tx.seller
          sellerPeerInfo = new PeerInfo(sellerId)
          clientNode.dialProtocol sellerPeerInfo, proto.PROTO_PURCHASE6, (err, connOut) =>
            if err is null
              pull pull.values([ JSON.stringify(tx) ]), connOut, pull.collect((err, connIn) =>
                console.log "<== #{proto.PROTO_PURCHASE6}: err:", err, "connIn:", connIn.toString()
                if err
                  console.log 'ouch, error'
              )
            else
              @ignoreNotSupported err, cb

          # witness saves transaction in own private ledger
          # TODO: to use @witness.savePrivateTx(tx) instead of @core.savePrivateTx(tx)?
          @core.savePrivateTx tx, (err, strippedTx) =>
            @core.savePublicTx strippedTx, (err) =>

              # syncing private ledger's transaction among other public blockchain nodes
              for p of clientNode.peerBook._peers
                console.log "peer to share with:", p
                publicId = PeerId.createFromB58String p
                publicPeerInfo = new PeerInfo(publicId)
                clientNode.dialProtocol publicPeerInfo, proto.PROTO_PURCHASE8, (err, connOut) =>
                  if err is null
                    pull pull.values([ JSON.stringify(strippedTx) ]), connOut, pull.collect((err, connIn) =>
                      console.log "<== #{proto.PROTO_PURCHASE8}: err:", err, "connIn:", connIn.toString()
                      if err
                        console.log 'ouch, error'
                    )
                  else
                    @ignoreNotSupported err, cb
          return '{ "code": "078" }'
        ), conn
        return '{ "code": "778" }'


      # purchase step 6: seller updates private ledger
      clientNode.handle proto.PROTO_PURCHASE6, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          @core.proceedTxBySeller JSON.parse(v.toString()), (err, rslt) -> {}
        ), conn
        return '{ "code": "789" }'


      # purchase step 8: saving a synced public blockchain's transaction
      clientNode.handle proto.PROTO_PURCHASE8, (protocol, conn) =>
        pull conn, pull.map((v) =>
          console.log "==>", protocol, 'v=', v.toString()
          @core.syncNewPublicTx JSON.parse(v.toString()), (rslt) =>
            return rslt
        ), conn
        return '{ "code": "779" }'


      # respond on request from browser node for getting all private transactions
      # TODO: only for requests from own browser
      clientNode.handle proto.PROTO_GET_ALL_PRIVATE_TXS, (protocol, conn) =>
        @core.getAllPrivateTxsRequest (err, txAll) =>
          # TODO: 2 chk err
          pull conn, pull.map((v) =>
            console.log "==>", protocol, 'v=', v.toString()
            return JSON.stringify(txAll)
          ), conn
        return '{ "code": "780" }'


      # respond on request from browser node for getting all public transactions
      # TODO: only for requests from own browser
      clientNode.handle proto.PROTO_GET_ALL_PUBLIC_TXS, (protocol, conn) =>
        @core.getAllPublicTxsRequest (err, txAll) =>
          # TODO: 2 chk err
          pull conn, pull.map((v) =>
            console.log "==>", protocol, 'v=', v.toString()
            return JSON.stringify(txAll)
          ), conn
        return '{ "code": "781" }'


      # respond on request from browser node for getting purchased files
      # TODO: only for requests from own browser
      clientNode.handle proto.PROTO_GET_PURCHASED, (protocol, conn) =>
        @core.getPurchasedRequest (err, files) =>
          # TODO: 2 chk err
          pull conn, pull.map((v) =>
            console.log "==>", protocol, 'v=', v.toString()
            return JSON.stringify(files)
          ), conn
        return '{ "code": "782" }'


      # returning locally located file
      clientNode.handle proto.PROTO_LOAD_FILE, (protocol, conn) =>
        ft.execPullFile conn, './purchased', (err, data) =>
          console.log 'local: err=', err, 'data=', data
        return '{ "code": "712" }'


      clientNode.on 'peer:discovery', (peerDiscovered) =>
        discovPeerB58Id = peerDiscovered.id.toB58String()
        clientNode.dial peerDiscovered, (err, data) ->
          if err
            cb err, data
          return
        return


      clientNode.on 'peer:connect', (peerConnected) =>
        connPeerB58Id = peerConnected.id.toB58String()
        console.log 'got connection to:', connPeerB58Id

        # saving status/ping/country of connected node for further usage
        startCnt = new Date()
        clientNode.dialProtocol peerConnected, proto.PROTO_WHORU, (err, connOut) =>
          if err is null
            tx = { data: 'whoru' }
            pull pull.values(tx), connOut, pull.collect((err, connIn) =>
              console.log "ping #{@core.wallet.value().id}-#{connPeerB58Id}:", new Date() - startCnt
              console.log "<== #{proto.PROTO_WHORU}: err:", err, "connIn: '#{connIn.toString()}'"
              if err
                console.log 'ouch, error'
            )
          else
            @ignoreNotSupported err, cb
            return '{ "code": "127" }'
        return '{ "code": "27" }'


      clientNode.on 'peer:disconnect', (peerLost) =>
        lostPeerB58Id = peerLost.id.toB58String()
        console.log 'lost connection to:', lostPeerB58Id
        return


      clientNode.start (err) =>
        if err
          console.log 'hmmm, err on start:', err
        cb null, @clientId.toB58String()


module.exports = Peer
