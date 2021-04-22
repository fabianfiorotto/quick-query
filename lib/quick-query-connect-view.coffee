{View, $} = require 'atom-space-pen-views'
{remote} = require 'electron'

ssh2 = require 'ssh2'

element: null

module.exports =
class QuickQueryConnectView extends View
  constructor: (@protocols) ->
    @connectionsStates = []
    super

  initialize: ->
    @port.val('3306')

    @sshport.val('22')

    @onWillConnect (promise) =>
      @connect.prop('disabled',true)
      fn = (=> @connect.prop('disabled',false))
      promise.then(fn).catch(fn)

    @pass.focus =>
      @showpass.stop().show()
    @pass.blur =>
      @showpass.fadeOut()

    @showpass.click =>
      @showpass.toggleClass("on")
      if @showpass.hasClass("on")
        @pass.attr("type","text")
        @sshpass.attr("type","text")
      else
        @pass.attr("type","password")
        @sshpass.attr("type","password")
      @pass.focus()

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
            @port.val(protocol.handler.defaultPort.toString())

    @browse_file.click (e) =>
        options =
          properties: ['openFile']
          title: 'Open Database'
        currentWindow = atom.getCurrentWindow()
        if $(e.currentTarget).data("extensions")
          options.filters = [{ name: 'Database', extensions: $(e.target).data("extensions") }]
        remote.dialog.showOpenDialog(currentWindow, options).then (dialog) =>
          @file.val(dialog.filePaths[0]) if dialog && !dialog.canceled

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
        remote.dialog.showOpenDialog(currentWindow, options).then (dialog) =>
          if dialog && !dialog.canceled
            @sshkey.data('file', dialog.filePaths[0]).addClass('selected')
            @sshpass_label.text('Passphrase')

    @connect.click (e) =>
      connectionInfo = {
        user: @user.val(),
        password: @pass.val()
        protocol: @protocol.val()
      }
      if @protocols[connectionInfo.protocol]?.handler.fromFilesystem?
        connectionInfo.file = @file.val()
      else
        connectionInfo.host = @host.val()
        connectionInfo.port = @port.val()
      if @protocols[connectionInfo.protocol]?.default?
        defaults = @protocols[connectionInfo.protocol].default
        connectionInfo[attr] = value for attr,value of defaults
      if @database.val() != ''
        connectionInfo.database = @database.val()
      if @sshuser.val() != ''
        connectionInfo.ssh =
          username: @sshuser.val()
          password: @sshpass.val()
          port: @sshport.val()
        connectionInfo.ssh.keyfile = @sshkey.data('file') if @sshkey.hasClass('selected')
      $(@element).trigger('quickQuery.connect',[@buildConnection(connectionInfo)])
    @advanced_toggle.click (e) =>
      @advanced_info.slideToggle 400, =>
        hidden = @advanced_info.is(":hidden")
        @advanced_info.find('input').attr 'tabindex', (i,attr) -> if hidden then null else i + 6
        @advanced_toggle.children("i").toggleClass("icon-chevron-down icon-chevron-left")

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
      port: ssh.port,
      username: ssh.username,
    if ssh.keyfile?
      conf.privateKey = require('fs').readFileSync(ssh.keyfile)
      conf.passphrase = ssh.password if ssh.password != ''
    else
      conf.password = ssh.password

    new Promise (resolve, reject)=>
      protocolClass = @protocols[connectionInfo.protocol]?.handler
      conn = new ssh2.Client()
      conn.on 'error', (err) -> reject(err)
      conn.on 'ready', =>
        conn.forwardOut '127.0.0.1', 12345, '127.0.0.1' ,connectionInfo.port, (err, stream) =>
          conn.end?() if err?
          stream.setTimeout = ((time, handler) -> @_client._sock.setTimeout(0, handler))
          connectionInfo.stream = (->stream)
          connection = new protocolClass(connectionInfo)
          connection.connect (err) =>
            console.log err if err?
            if err then reject(err) else resolve(connection)
            @trigger('quickQuery.connected',connection)  unless err?
      conn.connect(conf)

  @content: ->
    @div class: 'dialog quick-query-connect', =>
      @div class: "col-sm-12" , =>
        @label 'protocol'
        @select outlet: "protocol", class: "form-control input-select" , id: "quick-query-protocol", tabindex: 1
      @div class: "qq-remote-info row", =>
        @div class: "col-sm-9" , =>
          @label 'host'
          @input outlet: "host", class: "input-text native-key-bindings", id: "quick-query-host", type: "text", tabindex: 2
        @div class:"col-sm-3" , =>
          @label 'port'
          @input outlet: "port", class: "input-number native-key-bindings", id: "quick-query-port", type: "number", min:0, max: 65536, tabindex: 3
      @div class: "qq-local-info row" , =>
        @div class: "col-sm-12", =>
          @label 'file'
        @div class: "col-sm-9", =>
          @input outlet: 'file', class: "input-text native-key-bindings", id: "quick-query-file", type: "text", tabindex: 2
        @div class: "col-sm-3", =>
          @button outlet: "browse_file", id:"quick-query-browse-file", class: "btn btn-default icon icon-file-directory", "Browse"
      @div class: "qq-auth-info row", =>
        @div class: "col-sm-6" , =>
          @label 'user'
          @input outlet: 'user', class: "input-text native-key-bindings", id: "quick-query-user", type: "text", tabindex: 4
        @div class: "col-sm-6" , =>
          @label 'password'
          @div class: "pass-wrapper", =>
            @input outlet: 'pass' ,class: "input-text native-key-bindings", id: "quick-query-pass", type: "password", tabindex: 5
            @button outlet:"showpass", class:"show-password", title:"Show password", tabindex: "-1", =>
              @i class: "icon icon-eye"
      @div class: "qq-advanced-info-toggler row", =>
        @div class: "col-sm-12", =>
          @button outlet:"advanced_toggle", class: "advance-toggle", tabindex: "-1", title:"toggle advanced options",=>
            @i  class: "icon icon-chevron-left"
      @div outlet: "advanced_info", class: "qq-advanced-info row", =>
        @div class: "col-sm-12" , =>
          @label 'default database (optional)'
          @input outlet: 'database' ,class: "input-text native-key-bindings", id: "quick-query-database", type: "text"
        @div class: "ssh-info col-sm-6" , =>
          @label 'SSH username'
          @input outlet: 'sshuser' ,class: "input-text native-key-bindings", id: "quick-query-ssh-user", type: "text"
        @div class: "ssh-info col-sm-4" , =>
          @label outlet: 'sshpass_label', 'SSH password'
          @div class:'flex-row', =>
            @div =>
              @input outlet: 'sshpass', class: "input-text native-key-bindings", id: "quick-query-ssh-pass", type: "password"
            @button outlet:"sshkey", title: "Load SSH Key", id:"quick-query-key", class: "btn btn-default icon icon-key",  ""
        @div class: "ssh-info col-sm-2" , =>
          @label for: "quick-query-ssh-port",'SSH port'
          @input outlet: 'sshport', class: "input-text native-key-bindings", id: "quick-query-ssh-port", type: "number", min:0, max: 65536

      @div class: "col-sm-12" , =>
        @button outlet:"connect", id:"quick-query-connect", class: "btn btn-default icon icon-plug" , tabindex: "99" , "Connect"

  destroy: ->
    @element.remove()
  focusFirst: ->
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
