#
# Marketplace Client
#

console.log 'marketplace client is starting...'

fs = require "fs"
readChunk = require "read-chunk"
fileType = require "file-type"
md5 = require "crypto-js/md5"
opn = require "opn"
path = require "path"
toml = require "toml"
ioClient = require "socket.io-client"
low = require "lowdb"
levelup = require "levelup"
leveldown = require "leveldown"
Ledger = require "./ledger"

# TODO: to use FileAsync
FileSync = require "lowdb/adapters/FileSync"


# reading config file from stdin
cfgPlainText = ''
process.stdin.resume()
process.stdin.setEncoding 'utf8'
process.stdin.on 'data', (chunk) ->
  cfgPlainText += chunk
  return
process.stdin.on 'end', ->
  cfg = toml.parse(cfgPlainText)
  if Object.keys(cfg).length == 0
    console.log 'empty config from stdin, client stopped'
    process.exit -2
  cfg.user.id = md5(cfg.user.name).toString()
  # latest tx
  latest = low(new FileSync(cfg.latest.latest))
  latest.defaults(latest: { id: "genesis", ts: Math.floor((new Date).getTime() / 1000) }).write()
  # private ledger
  ledger = new Ledger(cfg.ledger.ledger, latest)
  # private wallet
  wallet = low(new FileSync(cfg.wallet.wallet))
  _w = wallet.value()
  if not (_w.coins? and _w.address?)
    console.log "broken #{cfg.wallet.wallet}? client stopped"
    process.exit -1
  [ cfg.user.balance, cfg.user.address ] = [ _w["coins"], _w["address"] ]
  console.log "well, #{cfg.user.name}'s configuration:", cfg
  data = { user: cfg.user }

  # scanning store's directory for files for marketplace
  if cfg.user.mode == 'seller'
    data.stores = cfg.seller[0]   # one store per seller for now
    data.stores.id = md5(data.stores.name).toString()
    data.stores.user_id = cfg.user.id
    items = []
    fs.readdir data.stores.root, (err, list) ->
      if err
        console.log "oops, something wrong with seller's directory", data.stores.root
        process.exit(-1)
      list.forEach (file) ->
        fs.stat data.stores.root + path.sep + file, (err, stat) ->
          item = {}
          [ item.id, item.name, item.mime, item.type, item.ts, item.size, item.price ] =
            [ md5(file).toString(), file, fileType(readChunk.sync(data.stores.root + path.sep + file, 0, 4100)).mime, undefined,
            stat.ctime, stat.size, parseInt(Math.random() * 100) ]
          item.type = "question-circle-o"
          switch item.mime.split("/")[0]
            when "video"
              item.type = "file-video-o"
            when "audio"
              item.type = "file-audio-o"
            when "text"
              item.type = "file-text-o"
            when "image"
              item.type = "picture-o"
          items.push item
      data.stores.items = items

  console.log cfg.user.name, "(#{cfg.user.email}) as a", cfg.user.mode, "having",
    cfg.user.balance, "coins is connecting to marketplace @", cfg.servers.demo.uri, "..."

  # connecting to marketplace
  skt = ioClient.connect("http://#{cfg.servers.demo.uri}")

  # notification about a new client
  skt.emit 'new-client', data: data

  # getting confirmation from marketplace about connected client
  skt.on 'new-client-connected', (data) ->
    console.log 'on new-client-connected:', data.data.user.email
    return

  # getting broadcast message about a new transaction from marketplace
  skt.on 'transaction-broadcasted', (data) ->
    console.log 'on transaction-broadcasted:', data
    if cfg.user.address in data.parties   # confirmation of own involvement
      skt.emit 'get-transaction', data.id
    return

  # finally getting the transaction
  skt.on 'get-transaction-returned', (data) ->
    console.log 'on get-transaction-returned:', data
    if cfg.user.mode == 'seller'
      wallet.update('coins', (n) ->
        n += data.price
      ).write()
    if cfg.user.mode == 'buyer'
      wallet.update('coins', (n) ->
        n -= data.price
      ).write()
    ledger.put(data.id, data, (rslt, txId, txAll) ->
      if rslt
        console.log 'failed to write to private ledger:', rslt
        return
      console.log "success: txId:", txId, "txAll:", txAll
      if cfg.user.mode == 'buyer'
        skt.emit 'success-transaction', txId, txAll   # buyer sends final confirmation about successful transaction
    )

  # opening the marketplace on web UI under "logged in" buyer only
  if cfg.user.mode == 'buyer'
    console.log "trying to open http://#{cfg.servers.demo.uri}/?#{cfg.user.id} marketplace's web UI for #{cfg.user.name} buyer"
    if /^win/.test process.platform
      opn "http://#{cfg.servers.demo.uri}/?#{cfg.user.id}", app: "chrome"
    else
      opn "http://#{cfg.servers.demo.uri}/?#{cfg.user.id}", app: "chromium-browser"
  else
    console.log "not opening marketplace's web UI for this seller (for buyers only)"
