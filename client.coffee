#
# Marketplace Client
#

console.log 'marketplace client is starting...'

fs = require "fs"
readChunk = require "read-chunk"
fileType = require "file-type"
md5 = require "crypto-js/md5"
open = require "open"
path = require "path"
toml = require "toml"
ioClient = require "socket.io-client"
low = require "lowdb"
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
  cfg.user.id = md5(cfg.user.name).toString()
  # private ledger
  ledger = low(new FileSync(cfg.ledger.ledger))
  ledger.defaults(ledger: []).write()
  # private wallet
  wallet = low(new FileSync(cfg.wallet.wallet))
  _w = wallet.value()
  console.log 'wallet=', _w
  if not (_w.coins? and _w.address?)
    console.log "broken #{cfg.wallet.wallet}? client stopped"
    process.exit -1
  [ cfg.user.balance, cfg.user.address ] = [ _w["coins"], _w["address"] ]
  console.log "well, #{cfg.user.name}'s configuration:", cfg
  data = { user: cfg.user }

  # reading seller's directory
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
          [ item.id, item.name, item.mime, item.ts, item.size, item.price ] =
            [ md5(file).toString(), file, fileType(readChunk.sync(data.stores.root + path.sep + file, 0, 4100)).mime,
            stat.ctime, stat.size, parseInt(Math.random() * 100) ]
          items.push item
      data.stores.items = items

  console.log cfg.user.name, "(#{cfg.user.email}) as a", cfg.user.mode, "having",
    cfg.user.balance, "coins is connecting to marketplace @", cfg.servers.demo.uri, "..."

  # connecting to marketplace
  skt = ioClient.connect("http://#{cfg.servers.demo.uri}")

  # notification about a new client
  skt.emit 'new_client', data: data

  # getting confirmation from marketplace about connected client
  skt.on 'new_client_connected', (data) ->
    console.log 'new_client_connected:', data.data.user.email
    return

  # getting broadcast message about a new transaction from marketplace
  skt.on 'transaction_broadcasted', (data) ->
    console.log 'transaction_broadcasted:', data
    if cfg.user.address in data.parties
      skt.emit 'get_transaction', data.id
    return

  # finally getting the transaction
  skt.on 'get_transaction_returned', (data) ->
    console.log 'get_transaction_returned:', data
    if cfg.user.mode == 'seller'
      wallet.update('coins', (n) ->
        n += data.price
      ).write()
    if cfg.user.mode == 'buyer'
      wallet.update('coins', (n) ->
        n -= data.price
      ).write()
    ledger.get("ledger").push(data).write()
    console.log "wallet/ledger magic is done"
    # TODO: to send confirmation about finishing the transaction
    return

  # opening the marketplace on web UI under "logged in" buyer only
  if cfg.user.mode == 'buyer'
    console.log "opening marketplace's web UI for #{cfg.user.name} buyer"
    if /^win/.test process.platform
      open "http://#{cfg.servers.demo.uri}/?#{cfg.user.id}", "chrome"
    else
      open "http://#{cfg.servers.demo.uri}/?#{cfg.user.id}", "chromium-browser"
  else
    console.log "not opening marketplace's web UI for this seller (for buyers only)"
