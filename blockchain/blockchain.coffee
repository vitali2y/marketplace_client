#
# Marketplace Client's public blockchain
#

Storage = require "./storage"


class Blockchain extends Storage

  constructor: (root) ->
    super root + "/public"


module.exports = Blockchain
