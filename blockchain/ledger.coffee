#
# Marketplace Client's private ledger
#

Storage = require "./storage"


class Ledger extends Storage

  constructor: (root) ->
    super root + "/private"


module.exports = Ledger
