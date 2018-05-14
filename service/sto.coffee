#
# Marketplace Client's 100Amigo integration service module
#

request = require "request"


class Sto

  constructor: (@getFileIcon) ->


  getBaseUrl: ->
    "https://online.100amigo.com/opus"


  getDownloadUrl: ->
    "file?_a=getresource&id={fileId}&type=file"


  getItems: (body, cb) ->
    items = []
    ptrnBeg = body.search /media_player":"/
    ptrnEnd = body.search /","object_type":"/
    request body[ptrnBeg+15..ptrnEnd-1].replace(/\\/g, ""), (error, response, body) =>
      fileList = JSON.parse body
      if fileList.code == '0'
        for f in fileList.data
          item = {}
          [ item.id, item.name, item.type, item.ts, item.size, item.price ] =
            [ f.id, f.name, @getFileIcon(f.mime), new Date(f.creation_date * 1000), f.origfilesize,
            parseInt(Math.random() * 100) ]
          item.hosted = 'online'
          items.push item
      cb null, @getBaseUrl(), @getDownloadUrl(), items


module.exports = Sto
