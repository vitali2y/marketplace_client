#
# Marketplace Client's configuration
#

fs = require "fs"
toml = require "toml"
request = require "request"

netConf = require "./netconf"


class Config

  get: (cb) ->

    parseConfig = ->
      cfg = toml.parse content
      console.log "well, #{cfg.user.name}'s configuration:\n", cfg
      cb null, cfg

    String::capitalize = ->
      @charAt(0).toUpperCase() + @slice(1)

    try
      content = fs.readFileSync './config.toml'
    catch error
      console.log 'config.toml does not exist, creating a new one'
      content = '# Client\'s config file\n\n[user]\nname = "user_name"\nemail = "user_email"\nmode = "buyer"\n\n\n' +
        '[marketplace]\nuri = "marketplace_uri:marketplace_port"\n\n\n[[rendezvous]]\nuri = "rendezvous_uri"\n\n\n' +
        '[api]\nport = api_port\n\n\n[wallet]\nwallet = "wallet.json"\n\n\n[blockchain]\nroot = "blockchain"\n\n\n' +
        '[purchased]\nroot = "purchased"\n'

        # fetching random first/last name/email for fake "buyer" account
        request 'https://randomuser.me/api?gender=male&inc=name,email&nat=us,gb&noinfo&format=json', (err, res, body) =>
          body = JSON.parse body
          content = netConf(content
            .replace /user_name/, body.results[0].name.first.capitalize() + ' ' + body.results[0].name.last.capitalize()
            .replace /user_email/, body.results[0].email
            .replace /api_port/, "9091")
          fs.writeFileSync './config.toml', content.toString()
          parseConfig()
        return

    parseConfig()


module.exports = Config
