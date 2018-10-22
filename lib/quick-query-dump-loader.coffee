{View, $} = require 'atom-space-pen-views'
{TextBuffer} = require 'atom'
fs = require 'fs'
remote = require 'remote'
path = require 'path'
module.exports =
class QuickQueryDumpLoader extends View
  initialize: (@browser, options = {} )->

    if @browser.selectedConnection?
      @refreshDatabases(options.database)

    if options.filename?
      @filename = options.filename
      @selectDesktop()
      @run.prop('disabled', @isNotReady())

    @browser.onConnectionDeleted =>
      if @browser.connections.length == 0
        @database.empty()
        @run.prop('disabled', true)

    @browser.onConnectionSelected =>
      @refreshDatabases(options.database)

    @desktop.click => @loadDesktopFile()
    @cloud.click => @selectCloud()

    @url.on 'change keydown', =>
      @run.prop('disabled', @isNotReady())

    @run.click =>
      @aborted = false
      @stateRunning()
      @stop.unbind('click').click =>
        @aborted = true
        @step.addClass('text-error').text("Aborted")
        @resetState()
      @step.text('Loading buffer')
      connection = @browser.selectedConnection
      if @cloud.hasClass('selected') && @url.val() != ''
        @step.text('Downloading')
        promise = @newTextBufferFromCloud(@url.val())
      else if path.extname(@filename) == '.gz'
        promise = @newTextBufferFromGz(@filename)
      else
        promise = TextBuffer.load(@filename)
      promise
      .then (buffer) =>
        @step.text('Parsing')
        @splitStatements connection, buffer
      .then (statements)=>
        @step.text('Executing')
        @executeStatements(connection, statements)
      .then =>
        @step.text('Done') if !@aborted
        @resetState()
      .catch (err)=>
        @step.addClass('text-error').text("Error: #{err}")
        @resetState()

  newTextBufferFromCloud: (url)->
    new Promise (resolve, reject) =>
      parsedUrl = require('url').parse(url)
      if parsedUrl.protocol == 'https:'
        protocol = require('https')
      else
        protocol = require('http')
      pathname = parsedUrl.pathname.split('/')
      inFilename = pathname[pathname.length - 1]
      request = protocol.get url, (response) =>
        if content_lenght = response.headers['content-length']
          @progress.attr('max',content_lenght).attr('value',0)
        if response.headers['content-disposition']?
          regexp = /filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/
          inFilename = regexp.exec( res.headers['content-disposition'] )[1]
          inFilename = inFilename.replace(/['"]/g, '')
        response.on 'data', (data) =>
          if content_lenght
            @progress.attr('value', parseInt(@progress.attr('value'))+data.length)
        if path.extname(inFilename) == '.gz'
          resolve(@newTextBufferFromGzStream(response,inFilename))
        else
          resolve(@newTextBufferFromStream(response,inFilename))
      @stop.click -> request.abort()

  newTextBufferFromGz: (inFilename)->
    inStream = fs.createReadStream(inFilename)
    @newTextBufferFromGzStream(inStream,inFilename)

  newTextBufferFromGzStream: (inStream,inFilename)->
    zlib = require 'zlib'
    filename = path.basename(inFilename,'.gz')
    gunzip = inStream.pipe(zlib.createGunzip())
    @stop.click -> gunzip.close()
    @newTextBufferFromStream(gunzip,filename)

  newTextBufferFromStream: (inStream,inFilename)->
    new Promise (resolve, reject) ->
      tempdir = require('os').tmpdir()
      outFilename = path.join(tempdir,inFilename)
      outStream = fs.createWriteStream(outFilename)
      inStream.pipe outStream
      inStream.on 'error', (err) -> reject(err)
      inStream.on 'end' , ->
        promise = TextBuffer.load(outFilename)
        promise.then (buffer)->
          buffer.onDidDestroy ->
            fs.unlink outFilename, (err) ->
              console.log(err) if err?
        resolve(promise)

  @content: ->
    @div class: 'quick-query-dump-loader', =>
      @div class: 'block flex-row', =>
        @div class: 'source flex-row btn-group', =>
          @button outlet: 'desktop', class: 'btn icon icon-desktop-download'
          @button outlet: 'cloud', class: 'btn icon icon-cloud-download'
          @input outlet: 'url', type: 'url', class: 'input-text hidden native-key-bindings' ,placeholder: 'Type an URL', value: ""
          @div outlet: 'fileview', class: 'fileview', ""
        @div class: 'destination', =>
          @select outlet: 'database', class:'input-select'
      @div class: 'block row-2 flex-row', =>
        @div outlet: 'left', class: 'left', =>
          @button outlet: 'run', disabled: 'disabled', class: 'btn start icon icon-playback-play'
          @button outlet: 'stop', class: 'btn stop icon icon-x'
        @div outlet: 'right', class: 'right', =>
          @progress outlet: 'progress', class: 'inline-block', value: 0, max: 1
          @span outlet: 'step',  class: 'inline-block', ''

  getTitle: -> 'Dump Loader'

  getDefaultLocation: -> "bottom"

  isNotReady: ->
    return true if @database.val() == '' || @database.val() == null
    if @cloud.hasClass('selected')
      @url.val() == '' || !@url.is(':valid')
    else
      !@filename?

  refreshDatabases: (defaultDB)->
    return if @database.prop('disabled')
    defaultDB ?= @browser.selectedConnection?.getDefaultDatabase()
    @database.append($('<option>').text(defaultDB))
    @browser.selectedConnection?.children (children) =>
      @database.empty()
      for child in children
        @database.append($('<option>').text(child.name).prop('selected',defaultDB == child.name))
      @run.prop('disabled', @isNotReady())

  stateRunning: ->
    @database.prop('disabled',true)
    @cloud.prop('disabled',true)
    @desktop.prop('disabled',true)
    @url.prop('readonly',true)
    @stop.show() ; @run.hide()
    @step.removeClass('text-error')
    @progress.removeAttr('value').removeAttr('max')
    @run.prop('disabled', true)

  resetState: ->
    @database.prop('disabled',false)
    @cloud.prop('disabled',false).removeClass 'selected'
    @desktop.prop('disabled',false).removeClass 'selected'
    @url.prop('readonly',false)
    @stop.hide() ; @run.show()
    @url.val('').addClass 'hidden'
    @fileview.empty().removeClass 'hidden'

  selectCloud: ->
    @cloud.addClass 'selected'
    @desktop.removeClass 'selected'
    @url.removeClass 'hidden'
    @fileview.addClass 'hidden'

  selectDesktop: ->
    @fileview.text(path.basename(@filename)).attr('title',@filename)
    if path.extname(@filename) == '.gz'
      $icon = $('<i>').addClass('icon icon-file-zip')
    else
      $icon = $('<i>').addClass('icon icon-file')
    @fileview.prepend($icon)
    @desktop.addClass 'selected'
    @cloud.removeClass 'selected'
    @fileview.removeClass 'hidden'
    @url.addClass 'hidden'

  loadDesktopFile: =>
    currentWindow = atom.getCurrentWindow()
    options =
      properties: ['openFile']
      title: 'Load Database Dump'
      filters: [{ name: 'Connections', extensions: ['mysql','sql','mysql.gz','sql.gz'] }]
    remote.dialog.showOpenDialog currentWindow, options, (files) =>
      if files?
        @filename = files[0]
        @selectDesktop()
        @run.prop('disabled', @isNotReady())

  splitStatements: (connection, buffer)->
    # Inspired in phpmyadmin's sql parser
    # https://github.com/phpmyadmin/sql-parser/blob/master/src/Utils/BufferedQuery.php

    # A string is being parsed.
    STATUS_STRING = 16; # 0001 0000
    STATUS_STRING_SINGLE_QUOTES = 17 # 0001 0001
    STATUS_STRING_DOUBLE_QUOTES = 18 # 0001 0010
    STATUS_STRING_BACKTICK = 20      # 0001 0100
    STATUS_STRING_DOLAR = 24         # 0001 1000
    # A comment is being parsed.
    STATUS_COMMENT = 32      # 0010 0000
    STATUS_COMMENT_BASH = 33 # 0010 0001
    STATUS_COMMENT_C = 34    # 0010 0010
    STATUS_COMMENT_SQL = 36  # 0010 0100
    # a Tag is being parsed
    STATUS_TAG = 64
    STATUS_TAG_DOLAR_OPEN = 65
    STATUS_TAG_DOLAR_CLOSE = 66

    is_mysql = connection.protocol = 'mysql'
    is_postgres = connection.protocol = 'postgres'

    dolar_open_tag = ''
    dolar_close_tag = ''
    markers = []
    status = 0
    delimiter = ';'
    # for line,i in lines
    i1 = 0 ; j1 = 0
    rows = buffer.getLastRow()
    statements = []
    for_loop = @timesInChunks rows, (i) =>
      line = buffer.lineForRow(i)
      if status == STATUS_COMMENT_SQL || status == STATUS_COMMENT_BASH
        status = 0
      for j in [0..(line.length-1)]
        ch0 = line[j-1]
        ch1 = line[j]
        ch2 = line[j+1]
        switch status
          when 0
            if ch1 == "'" && ch0 != '\\' then status = STATUS_STRING_SINGLE_QUOTES
            if ch1 == '"' && ch0 != '\\' then status = STATUS_STRING_DOUBLE_QUOTES
            if ch1 == '`' && ch0 != '\\' then status = STATUS_STRING_BACKTICK
            if ch1 == '-' && ch2 == '-' then status = STATUS_COMMENT_SQL
            if ch0 == '\\' && ch1 == '*' && ch2 != '!' then status = STATUS_COMMENT_C
            if ch1 == '$' && is_postgres then status = STATUS_TAG_DOLAR_OPEN
          when STATUS_STRING_SINGLE_QUOTES
            if ch1 == "'" && ch0 != '\\' then status = 0
          when STATUS_STRING_DOUBLE_QUOTES
            if ch1 == '"' && ch0 != '\\' then status = 0
          when STATUS_STRING_BACKTICK
            if ch1 == '`' && ch0 != '\\' then status = 0
          when STATUS_STRING_DOLAR
            if ch1 == '$' then status = STATUS_TAG_DOLAR_CLOSE
          when STATUS_TAG_DOLAR_OPEN
            if ch1 == '$'
              status = STATUS_STRING_DOLAR
            else
              dolar_open_tag += ch1
          when STATUS_TAG_DOLAR_CLOSE
            if ch1 == '$'
              if dolar_open_tag == dolar_close_tag
                status = 0
                dolar_open_tag = ''
              dolar_close_tag = ''
            else
              dolar_close_tag += ch1
          when STATUS_COMMENT_C
            if ch0 == '*' && ch1 == '\\' then status = 0
        if status == 0
          if is_mysql && new_delimiter = @findNewDelimiter(line)
            buffer.setTextInRange([[i,0],[i,line.length]],'')
            delimiter = new_delimiter
          if @matchDelimiter(line,j,delimiter)
            j2 = j + 1 - delimiter.length
            sentence = buffer.getTextInRange([[i1,j1],[i,j2]])
            statements.push(sentence) unless /^\s*$/.test(sentence)
            i1 = i ; j1 = j + delimiter.length
      if i == rows - 1 && (i1 < i || j1 < line.length)
        sentence = buffer.getTextInRange([[i1,j1],[i,line.length]])
        statements.push(sentence) unless /^\s*$/.test(sentence)
      buffer.destroy() if i == rows - 1
    for_loop.then (aborted)->
      new Promise (resolve, reject) ->
        resolve(statements)

  executeStatements: (oldConnection, statements)->
    new Promise (resolve, reject) =>
      return resolve(true) if @aborted
      connectionInfo = oldConnection.serialize()
      connectionInfo['database'] = @database.val()
      @progress.attr('max',statements.length)
      connection = new oldConnection.constructor(connectionInfo)
      connection.connect (err)=>
        if (!err)
          @executeStatementsIteration connection,statements, (err)->
            connection.close()
            if err then reject(err) else resolve(true)
        else
          reject(err)

  executeStatementsIteration: (connection,statements,fn,i = 0) ->
    if !@aborted && i < statements.length
      @progress.attr('value',i+1)
      connection.query statements[i], (message)=>
        if message.type == 'error'
          fn(message.content)
        else
          @executeStatementsIteration(connection,statements,fn,i+1)
    else
      fn(false)

  timesInChunks: (n,fn)->
    new Promise (resolve, reject) =>
      chuncksize = 10
      @progress.attr('max',n).attr('value',0)
      index = 0
      @stop.click =>
        if @loop?
          clearTimeout(@loop)
          @loop = null
      doChunk = ()=>
        cnt = chuncksize
        while cnt > 0 && index < n && !@aborted
          fn.call(@,index)
          ++index
          cnt--
        if @aborted
          resolve(true)
        else if index < n
          @progress.attr('value',index)
          @loop = setTimeout(doChunk, 1)
        else
          @loop = null
          @progress.attr('value',n)
          resolve(false)
      doChunk()

  matchDelimiter: (line,j, delimiter)->
    if delimiter.length == 1
      delimiter == line[j]
    else
      delimiter == line.substring(j,delimiter.length)

  findNewDelimiter: (line)->
    if ((line[0] == 'D') || (line[0] == 'd')) &&
     ((line[1] == 'E') || (line[1] == 'e')) &&
     ((line[2] == 'L') || (line[2] == 'l')) &&
     ((line[3] == 'I') || (line[3] == 'i')) &&
     ((line[4] == 'M') || (line[4] == 'm')) &&
     ((line[5] == 'I') || (line[5] == 'i')) &&
     ((line[6] == 'T') || (line[6] == 't')) &&
     ((line[7] == 'E') || (line[7] == 'e')) &&
     ((line[8] == 'R') || (line[8] == 'r')) &&
     (@isWhitespace(line[9]))
      return line.substring(9).trim()
    else
      return null

  isWhitespace: (chr)-> chr == ' '
