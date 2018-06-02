#
# Marketplace Client
#

express = require "express"
fs = require "fs"
readChunk = require "read-chunk"
fileType = require "file-type"
md5 = require "crypto-js/md5"
opn = require "opn"
path = require "path"
request = require "request"
mitt = require "mitt"

Config = require "./util/config"
Core = require "./core"
Ledger = require "./blockchain/ledger"
Blockchain = require "./blockchain/blockchain"
Peer = require "./util/peer"
Wallet = require "./util/wallet"


globalEmitter = mitt()


new Config().get (err, cfg) ->
  if err
    console.log "app stopped"
    process.exit err

  # default system dirs management
  if not fs.existsSync './blockchain'
    fs.mkdirSync './blockchain'
  if cfg.user.mode in [ 'buyer', 'seller' ] and not fs.existsSync './purchased'
    fs.mkdirSync './purchased'
  if cfg.user.mode == 'witness' and not fs.existsSync './transferred'
    fs.mkdirSync './transferred'

  user = { user: cfg.user }
  user.cwd = process.cwd()
  new Wallet cfg, (err, wallet) ->
    ledger = new Ledger(cfg.blockchain.root)
    blockchain = new Blockchain(cfg.blockchain.root)

    getFileIcon = (mime) ->
      type = "question-circle-o"
      switch mime.split("/")[0]
        when "video"
          type = "file-video-o"
        when "audio"
          type = "file-audio-o"
        when "text"
          type = "file-text-o"
        when "image"
          type = "picture-o"
      type

    startNode = ->
      new Peer().start new Core(globalEmitter, cfg, user, wallet, ledger, blockchain), (err, resp) ->
        if err is null
          console.log "user", cfg.user.name, "(#{cfg.user.email}, #{resp}) as a", cfg.user.mode, "having",
            cfg.user.balance, "coins is connecting to", cfg.rendezvous[0].uri

          # opening the marketplace's web UI under "logged in" buyer only (if enabled)
          if /^win/.test process.platform
            bro = "chrome"
          if /^darwin/.test process.platform
            bro = "google chrome"
          if /^linux/.test process.platform
            bro = "chromium-browser"
          if process.env.MARKETPLACE_BROWSER?
            bro = process.env.MARKETPLACE_BROWSER
          if bro == 'no'
            console.log 'skip opening browser'
          else
            if cfg.user.mode == 'buyer'
              console.log "trying to open https://#{cfg.marketplace.uri}/?#{cfg.user.id} marketplace's web UI for buyer #{cfg.user.name} under '${bro}' browser"
              opn "https://#{cfg.marketplace.uri}/?#{cfg.user.id}", app: bro
            else
              console.log "by default do not open marketplace's web UI for #{cfg.user.mode}, but for buyer only"

          # running local web server for purchased files
          # TODO: https://github.com/baalexander/node-portscanner for finding not busy port
          if cfg.user.mode == 'buyer'
            app = express()
            app.set 'port', 3000
            app.use('/', express.static(process.cwd() + '/purchased'))
            server = app.listen(app.get('port'))
            console.log 'listening on port', app.get('port')

        else
          # TODO: 'error: {} resp: undefined'
          console.log "error:", JSON.stringify(err), 'resp:', resp
          console.log "app stopped"
          process.exit -7

    # scanning store's directory for files for representing them on marketplace
    if cfg.user.mode == 'seller'
      # TODO: one store per seller for now
      user.stores = cfg.seller[0]
      user.stores.id = md5(user.stores.name).toString()
      user.stores.user_id = cfg.user.id
      items = []

      if user.stores.service?
        user.stores.icon = "cloud"
        request user.stores.root, (error, response, body) ->

          # loading the service modules
          # TODO: support for multiply modules
          Service = require "./service"
          service = new Service(getFileIcon)
          service.getItems body, (err, baseUrl, downloadUrl, items) ->
            [ user.stores.base, user.stores.download, user.stores.items ] = [ baseUrl, downloadUrl, items ]
            startNode()
      else
        user.stores.icon = "hdd-o"
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
              item.type = getFileIcon item.mime
              item.hosted = 'local'
              items.push item
          user.stores.items = items
          startNode()
    else
      startNode()
