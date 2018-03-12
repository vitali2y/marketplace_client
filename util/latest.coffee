#
# Marketplace Client's the latest transaction number
#

low = require "lowdb"
# TODO: to use FileAsync
FileSync = require "lowdb/adapters/FileSync"


class Latest

  constructor: (cfg) ->
    console.log 'cfg.latest.latest:', cfg.latest.latest
    @latest = low(new FileSync(cfg.latest.latest))
    @latest.defaults(latest: { id: "genesis", ts: Math.floor((new Date).getTime() / 1000) }).write()


  get: ->
    @latest


module.exports = Latest
