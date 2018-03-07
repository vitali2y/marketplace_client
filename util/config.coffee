#
# Marketplace Client's configuration
#

toml = require "toml"
low = require "lowdb"
# TODO: to use FileAsync
FileSync = require "lowdb/adapters/FileSync"


class Config

  constructor: (@cfgPlainText) ->


  get: (cb) ->
    @cfg = toml.parse(@cfgPlainText)
    if Object.keys(@cfg).length == 0
      console.log 'empty config from stdin'
      cb 1
      return
    console.log "well, #{@cfg.user.name}'s configuration:\n", @cfg
    cb null, @cfg


module.exports = Config
