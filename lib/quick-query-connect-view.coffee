{View, $} = require 'atom-space-pen-views'
remote = require 'remote'
ssh2 = require 'ssh2'

element: null

module.exports =
class QuickQueryConnectView extends View
  constructor: (@protocols) ->
    @connectionsStates = []
    super

  initialize: ->
    portEditor = @port[0].getModel()
    portEditor.setText('3306')

    @connect.keydown (e) ->
      $(this).click() if e.keyCode == 13
    @protocol
      .keydown (e) ->
        if e.keyCode == 13
          $(e.target).css height: 'auto'
          e.target.size = 3
        else if  e.keyCode == 37 || e.keyCode == 38
          $(e.target).find('option:selected').prev().prop('selected',true)
        else if  e.keyCode == 39 || e.keyCode == 40
          $(e.target).find('option:selected').next().prop('selected',true)
      .blur (e) ->
        $(e.target).css height: ''
        e.target.size = 0
      .on 'change blur', (e) =>
        if $(e.target).find('option:selected').length > 0
          protocol = $(e.target).find('option:selected').data('protocol')
          @find('.ssh-info').toggle(protocol.handler.sshSupport? && protocol.handler.sshSupport)
          if protocol.handler.fromFilesystem?
            @showLocalInfo()
            if protocol.handler.fileExtencions?
              @browse_file.data('extensions',protocol.handler.fileExtencions)
            else
              @browse_file.data('extensions',false)
          else
            @showRemoteInfo()
            portEditor.setText(protocol.handler.defaultPort.toString())

    @browse_file.click (e) =>
        options =
          properties: ['openFile']
          title: 'Open Database'
        currentWindow = atom.getCurrentWindow()
        if $(e.currentTarget).data("extensions")
          options.filters = [{ name: 'Database', extensions: $(e.target).data("extensions") }]
        remote.dialog.showOpenDialog currentWindow, options, (files) =>
          @file[0].getModel().setText(files[0]) if files?

    for key,protocol of @protocols
      option = $('<option/>')
        .text(protocol.name)
        .val(key)
        .data('protocol',protocol)
      @protocol.append(option)

    @sshkey.click (e) =>
      if @sshkey.hasClass('selected')
        @sshpass_label.text('SSH Password')
        @sshkey.removeClass('selected')
      else
        currentWindow = atom.getCurrentWindow()
        options =
          properties: ['openFile']
          title: 'Load SSH Key'
        remote.dialog.showOpenDialog currentWindow, options, (files) =>
          if files?
            @sshkey.data('file',files[0]).addClass('selected')
            @sshpass_label.text('Passphrase')

    @connect.click (e) =>
      connectionInfo = {
        user: @user[0].getModel().getText(),
        password: @pass[0].getModel().getText()
        protocol: @protocol.val()
      }
      if @protocols[connectionInfo.protocol]?.handler.fromFilesystem?
        connectionInfo.file = @file[0].getModel().getText()
      else
        connectionInfo.host = @host[0].getModel().getText()
        connectionInfo.port = @port[0].getModel().getText()
      if @protocols[connectionInfo.protocol]?.default?
        defaults = @protocols[connectionInfo.protocol].default
        connectionInfo[attr] = value for attr,value of defaults
      if @database[0].getModel().getText() != ''
        connectionInfo.database = @database[0].getModel().getText()
      if @sshuser[0].getModel().getText() != ''
        connectionInfo.ssh =
          username: @sshuser[0].getModel().getText()
          password: @sshpass[0].getModel().getText()
        connectionInfo.ssh.keyfile = @sshkey.data('file') if @sshkey.hasClass('selected')
      $(@element).trigger('quickQuery.connect',[@buildConnection(connectionInfo)])
    @advanced_toggle.click (e) =>
      @find(".qq-advanced-info").slideToggle 400, =>
        @advanced_toggle.children("i").toggleClass("icon-chevron-down icon-chevron-left")

  fixTabindex: ->
    @file.attr('tabindex',2)
    @host.attr('tabindex',2)
    @port.attr('tabindex',3)
    @user.attr('tabindex',4)
    @pass.attr('tabindex',5)
    @database.attr('tabindex',6)

  addProtocol: (key,protocol)->
    @protocols[key] = protocol
    option = $('<option/>')
      .text(protocol.name)
      .val(key)
      .data('protocol',protocol)
    @protocol.append(option)
    for state in @connectionsStates
      state.callback(state.info) if state.info.protocol == key

  buildConnection: (connectionInfo)->
    return @buildConnectionSSH(connectionInfo) if connectionInfo.ssh?
    new Promise (resolve, reject)=>
      protocolClass = @protocols[connectionInfo.protocol]?.handler
      if protocolClass
        connection = new protocolClass(connectionInfo)
        connection.connect (err) =>
          if err then reject(err) else resolve(connection)
          @trigger('quickQuery.connected',connection)  unless err?
      else #whait until the package is loaded
        @connectionsStates.push
          info: connectionInfo
          callback: (connectionInfo) =>
            protocolClass = @protocols[connectionInfo.protocol].handler
            connection = new protocolClass(connectionInfo)
            connection.connect (err) =>
              if err then reject(err) else resolve(connection)
              @trigger('quickQuery.connected',connection)  unless err?

  buildConnectionSSH: (connectionInfo) ->
    ssh = connectionInfo.ssh
    conf =
      host: connectionInfo.host,
      port: '22',
      username: ssh.username,
    if ssh.keyfile?
      conf.privateKey = require('fs').readFileSync(ssh.keyfile)
      conf.passphrase = ssh.password if ssh.password != ''
    else
      conf.password = ssh.password

    new Promise (resolve, reject)=>
      protocolClass = @protocols[connectionInfo.protocol]?.handler
      conn = new ssh2.Client()
      conn.on 'ready', =>
        conn.forwardOut '127.0.0.1', 12345, '127.0.0.1' ,connectionInfo.port, (err, stream) =>
          conn.end?() if err?
          stream.setTimeout = ((time, handler) -> @_client._sock.setTimeout(time, handler))
          connectionInfo.stream = (->stream)
          connection = new protocolClass(connectionInfo)
          connection.connect (err) =>
            console.log err
            if err then reject(err) else resolve(connection)
            @trigger('quickQuery.connected',connection)  unless err?
      conn.connect(conf)

  @content: ->
    @div class: 'dialog quick-query-connect', =>
      @div class: "col-sm-12" , =>
        @label 'protocol'
        @select outlet: "protocol", class: "form-control input-select" , id: "quick-query-protocol", tabindex: "1"
      @div class: "qq-remote-info row", =>
        @div class: "col-sm-9" , =>
          @label 'host'
          @currentBuilder.tag 'atom-text-editor', outlet: "host", id: "quick-query-host", class: 'editor', mini: 'mini', type: 'string'
        @div class:"col-sm-3" , =>
          @label 'port'
          @currentBuilder.tag 'atom-text-editor', outlet: "port", id: "quick-query-port", class: 'editor', mini: 'mini', type: 'string'
      @div class: "qq-local-info row" , =>
        @div class: "col-sm-12", =>
          @label 'file'
        @div class: "col-sm-9", =>
          @currentBuilder.tag 'atom-text-editor',outlet: "file", id: "quick-query-file", class: 'editor', mini: 'mini', type: 'string'
        @div class: "col-sm-3", =>
          @button outlet: "browse_file", id:"quick-query-browse-file", class: "btn btn-default icon icon-file-directory", "Browse"
      @div class: "qq-auth-info row", =>
        @div class: "col-sm-6" , =>
          @label 'user'
          @currentBuilder.tag 'atom-text-editor', outlet: "user", id: "quick-query-user", class: 'editor', mini: 'mini', type: 'string'
        @div class: "col-sm-6" , =>
          @label 'password'
          @currentBuilder.tag 'atom-text-editor', outlet: "pass", id: "quick-query-pass", class: 'editor', mini: 'mini'
      @div class: "qq-advanced-info-toggler row", =>
        @div class: "col-sm-12", =>
          @button outlet:"advanced_toggle", class: "advance-toggle", tabindex: "-1", title:"toggle advanced options",=>
            @i  class: "icon icon-chevron-left"
      @div class: "qq-advanced-info row", =>
        @div class: "col-sm-12" , =>
          @label 'default database (optional)'
          @currentBuilder.tag 'atom-text-editor',outlet: "database", id: "quick-query-database", class: 'editor', mini: 'mini', type: 'string'
        @div class: "ssh-info col-sm-6" , =>
          @label 'SSH Username'
          @currentBuilder.tag 'atom-text-editor',outlet: "sshuser", id: "quick-query-ssh-user", class: 'editor', mini: 'mini', type: 'string'
        @div class: "ssh-info col-sm-6" , =>
          @label outlet: 'sshpass_label', 'SSH Password'
          @div class:'flex-row', =>
            @div =>
              @currentBuilder.tag 'atom-text-editor',outlet: "sshpass", id: "quick-query-ssh-user", class: 'editor', mini: 'mini', type: 'string'
            @button outlet:"sshkey", id:"quick-query-key", class: "btn btn-default icon icon-key",  ""

      @div class: "col-sm-12" , =>
        @button outlet:"connect", id:"quick-query-connect", class: "btn btn-default icon icon-plug" , tabindex: "7" , "Connect"

  destroy: ->
    @element.remove()
  focusFirst: ->
    @fixTabindex()
    @protocol.focus()

  showLocalInfo: ->
    @find(".qq-local-info").show()
    @find(".qq-remote-info").hide()

  showRemoteInfo: ->
    @find(".qq-remote-info").show()
    @find(".qq-local-info").hide()

  onWillConnect: (callback)->
    @bind 'quickQuery.connect', (e,connectionPromise) ->
      callback(connectionPromise)

  onConnectionStablished: (callback)->
    @bind 'quickQuery.connected', (e,connection) ->
      callback(connection)
