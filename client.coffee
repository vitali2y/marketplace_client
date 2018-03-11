#
# Marketplace Client
#

fs = require "fs"
readChunk = require "read-chunk"
fileType = require "file-type"
md5 = require "crypto-js/md5"
opn = require "opn"
path = require "path"

Core = require "./core"
Ledger = require "./blockchain/ledger"
Config = require "./util/config"
Latest = require "./util/latest"
Peer = require "./util/peer"
Wallet = require "./util/wallet"


# reading config file from stdin
cfgStdinText = ''
process.stdin.resume()
process.stdin.setEncoding 'utf8'
process.stdin.on 'data', (chunk) ->
  cfgStdinText += chunk
  return
process.stdin.on 'end', ->
  new Config(cfgStdinText).get (err, cfg) ->
    if err
      console.log "app stopped"
      process.exit err

    user = { user: cfg.user }
    latest = new Latest(cfg).get()
    wallet = new Wallet(cfg).get()
    ledger = new Ledger(cfg.ledger.ledger, latest)

    # scanning store's directory for files for representing them on marketplace
    if cfg.user.mode == 'seller'
      user.stores = cfg.seller[0]   # one store per seller for now
      user.stores.id = md5(user.stores.name).toString()
      user.stores.user_id = cfg.user.id
      items = []
      fs.readdir user.stores.root, (err, list) ->
        if err
          console.log "oops, something wrong with seller's directory", user.stores.root
          process.exit(-1)
        list.forEach (file) ->
          fs.stat user.stores.root + path.sep + file, (err, stat) ->
            item = {}
            [ item.id, item.name, item.type, item.ts, item.size, item.price ] =
              [ md5(file).toString(), file, undefined, stat.ctime, stat.size, parseInt(Math.random() * 100) ]
            t = fileType(readChunk.sync(user.stores.root + path.sep + file, 0, 4100))
            if t == null
              console.log 'oops, not recognized mime for', item.name
              # TODO: to recognized mime by extension?
              item.mime = "application/unknown"
            else
              item.mime = t.mime
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
        user.stores.items = items

    new Peer().start new Core(cfg, user, wallet, ledger), (err, resp) ->
      if err is null
        console.log "user", cfg.user.name, "(#{cfg.user.email}, #{resp}) as a", cfg.user.mode, "having",
          cfg.user.balance, "coins is connecting to", cfg.rendezvous[0].uri

        # opening the web UI of marketplace under "logged in" buyer only
        if cfg.user.mode == 'buyer'
          console.log "trying to open http://#{cfg.marketplace.uri}/?#{cfg.user.id} marketplace's web UI for buyer #{cfg.user.name} under Chrome/Chromium"
          if /^win/.test process.platform
            opn "http://#{cfg.marketplace.uri}/?#{cfg.user.id}", app: "chrome"
          if /^darwin/.test process.platform
            opn "http://#{cfg.marketplace.uri}/?#{cfg.user.id}", app: "google chrome"
          if /^linux/.test process.platform
            opn "http://#{cfg.marketplace.uri}/?#{cfg.user.id}", app: "chromium-browser"
        else
          console.log "by default do not open marketplace's web UI for #{cfg.user.mode}, but for buyer only"
      else
        console.log "error:", JSON.stringify(err), 'resp:', resp
        console.log "app stopped"
        process.exit -7
