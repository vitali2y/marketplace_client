#
# Marketplace Client's file transfer protocol
#

fs = require "fs"
os = require "os"
pull = require "pull-stream"
Handshake = require "pull-handshake"


MSG_ACK = '0kay'
CHUNK_SIZE = 100 * 1024


class FileTransfer

  # sending tx file
  sendTxFile: (shake, tx) ->
    txLength = Buffer.alloc 4
    txLength.writeInt32BE JSON.stringify(tx).length, 0
    shake.write Buffer.concat([ txLength, Buffer.from(JSON.stringify(tx)) ])
    return


  # receiving tx file
  receiveTxFile: (shake, cb) ->

    # receiving size of tx file
    shake.read 4, (err, v) ->
      if err
        console.log 'receiveTxFile4: err=', err
        shake.abort err
        return
      txLength = v.readInt32BE(0)
      console.log 'txLength=', txLength

      # receiving tx file itself
      shake.read txLength, (err, fileTx) ->
        if err
          console.log 'receiveTxFile: err=', err
          shake.abort err
          return
        fileTx = JSON.parse(fileTx.toString())
        cb null, fileTx
    return


  writeChunksToFile: (fileName, arrChunks, cb) ->

    writeChunkToFile = (fd, arrChunks, pos, cntChunk) ->
      if cntChunk <= arrChunks.length - 1
        c = arrChunks[cntChunk]
        fs.write fd, c, 0, c.length, pos, (err, bytesWritten, buffWritten) ->
          # TODO: to chk err
          pos += c.length
          writeChunkToFile fd, arrChunks, pos, cntChunk + 1
      else
        cb null, fileName

    fs.open fileName, 'a', (err, fd) ->
      console.log 'chunks amount:', arrChunks.length
      writeChunkToFile fd, arrChunks, 0, 0
    return


  # sending file by chunks
  sendByChunks: (shake, fileDir, fileTx) ->

    sendChunk = (arrChunks, cntChunk) ->
      if cntChunk <= arrChunks.length - 1
        contentChunk = arrChunks[cntChunk]
        txChunk = Buffer.alloc 4
        txChunk.writeInt32BE contentChunk.length, 0
        shake.write Buffer.concat([ txChunk, contentChunk ])
        shake.read MSG_ACK.length, (err, v) ->    # expecting MSG_ACK
          if err or not (v.toString() == MSG_ACK)
            console.log 'ouch, err=', err
            shake.abort err
            return
          sendChunk arrChunks, cntChunk + 1
      return

    fileName = fileTx.file_name
    fs.open fileDir + '/' + fileName, 'r', (err, fd) ->
      contentBuff = new Buffer(fileTx.sys.size)
      fs.read fd, contentBuff, 0, fileTx.sys.size, fileTx.sys.position, (err, bytesRead, buffRead) ->
        chunkPos = 0
        preparedChunks = []
        while true
          chunk = buffRead.slice(0 + chunkPos, CHUNK_SIZE + chunkPos)
          preparedChunks.push chunk
          if chunk.length < CHUNK_SIZE  then break
          chunkPos += CHUNK_SIZE
        sendChunk preparedChunks, 0
    return


  receiveByChunks: (shake, fileFullName, cb) ->
    console.log "receiveByChunks (<shake>, #{fileFullName}, <cb>)"

    receiveChunk = (receivedChunks, cbReceived) ->

      # receiving the size of chunk
      shake.read 4, (err, v) ->
        if err
          console.log 'receiveChunk4: err=', err
          shake.abort err
          return
        chunkLength = v.readInt32BE(0)

        # receiving the chunk
        shake.read chunkLength, (err, encodedContent) ->
          if err
            console.log 'receiveChunk: err=', err
            shake.abort err
            return
          shake.write new Buffer(MSG_ACK)
          receivedChunks.push encodedContent
          if chunkLength < CHUNK_SIZE
            cbReceived null, receivedChunks
            return

          # recursive call for next chunk
          receiveChunk receivedChunks, cbReceived
      return

    receiveChunk [], cb
    return


  initPullFile: (conn, fileTx, cb) ->
    console.log "initPullFile (<conn>, #{JSON.stringify fileTx}, <cb>)"
    # TODO: to close stream?
    stream = Handshake()
    shake = stream.handshake
    stream.handshake = null
    pull stream, conn, stream

    # sending tx file first
    @sendTxFile shake, fileTx
    @receiveByChunks shake, 'transferred/' + fileTx.id + '.' + fileTx.sys.chunk, cb
    return


  execPullFile: (conn, fileDir, cb) ->
    console.log "execPullFile (<conn>, #{fileDir}, <cb>)"
    stream = Handshake()
    shake = stream.handshake
    pull conn, stream, conn

    @receiveTxFile shake, (err, fileTx) =>
      fileName = fileTx.file_name
      if fileTx.hosted? and fileTx.hosted == "online"
        fileDir = os.tmpdir()
        fs.writeFileSync fileDir + '/' + fileName, JSON.stringify(fileTx)
        console.log 'creating', fileDir + '/' + fileName

      # sending file itself now
      @sendByChunks shake, fileDir, fileTx
    return


  initPushFile: (conn, fileTx, cb) ->
    console.log "initPushFile (<conn>, #{JSON.stringify fileTx}, <cb>)"
    # TODO: to close stream?
    stream = Handshake()
    shake = stream.handshake
    stream.handshake = null
    pull stream, conn, stream

    fs.stat './transferred/' + fileTx.id + '.' + fileTx.sys.chunk, (err, stats) =>
      if err
        cb err
      fileTx.sys.size = stats.size

      # sending tx file first
      @sendTxFile shake, fileTx

      # sending file itself now
      fileTx.file_name = fileTx.id + '.' + fileTx.sys.chunk
      fileTx.sys.position = 0
      @sendByChunks shake, './transferred/', fileTx
    return


  execPushFile: (conn, cb) ->
    console.log 'execPushFile (<conn>, <cb>)'
    stream = Handshake()
    shake = stream.handshake
    pull conn, stream, conn

    @receiveTxFile shake, (err, fileTx) =>
      @receiveByChunks shake, os.tmpdir() + '/' + fileTx.id + '.' + fileTx.sys.chunk, (err, chunkContent) =>
        @writeChunksToFile os.tmpdir() + '/' + fileTx.id + '.' + fileTx.sys.chunk, chunkContent, (err, chunkContent) ->
          cb err, fileTx
    return


module.exports = FileTransfer
