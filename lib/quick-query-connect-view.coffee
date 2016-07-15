{View, $} = require 'atom-space-pen-views'
remote = require 'remote'

element: null

module.exports =
class QuickQueryConnectView extends View
  constructor: (@protocols) ->
    @connectionsStates = []
    super

  initialize: ->
    portEditor = @find("#quick-query-port")[0].getModel()
    portEditor.setText('3306')

    @find("#quick-query-file").attr('tabindex',2)
    @find("#quick-query-host").attr('tabindex',2)
    @find("#quick-query-port").attr('tabindex',3)
    @find("#quick-query-user").attr('tabindex',4)
    @find("#quick-query-pass").attr('tabindex',5)

    @find('#quick-query-connect').keydown (e) ->
      $(this).click() if e.keyCode == 13
    @find('#quick-query-protocol')
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
          if protocol.handler.fromFilesystem?
            @showLocalInfo()
            if protocol.handler.fileExtencions?
              @find('#quick-query-browse-file')
               .data('extensions',protocol.handler.fileExtencions)
            else
              @find('#quick-query-browse-file').data('extensions',false)
          else
            @showRemoteInfo()
            portEditor.setText(protocol.handler.defaultPort.toString())

    @find('#quick-query-browse-file').click (e) =>
        options =
          properties: ['openFile']
          title: 'Open Database'
        currentWindow = atom.getCurrentWindow()
        if $(e.currentTarget).data("extensions")
          options.filters = [{ name: 'Database', extensions: $(e.target).data("extensions") }]
        remote.require('dialog').showOpenDialog currentWindow, options, (files) =>
          @find('#quick-query-file')[0].getModel().setText(files[0]) if files?

    for key,protocol of @protocols
      option = $('<option/>')
        .text(protocol.name)
        .val(key)
        .data('protocol',protocol)
      @find('#quick-query-protocol').append(option)

    @find('#quick-query-connect').click (e) =>
      connectionInfo = {
        user: @find("#quick-query-user")[0].getModel().getText(),
        password: @find("#quick-query-pass")[0].getModel().getText()
        protocol: @find("#quick-query-protocol").val()
      }
      if @protocols[connectionInfo.protocol]?.handler.fromFilesystem?
        connectionInfo.file = @find("#quick-query-file")[0].getModel().getText()
      else
        connectionInfo.host = @find("#quick-query-host")[0].getModel().getText()
        connectionInfo.port = @find("#quick-query-port")[0].getModel().getText()
      if @protocols[connectionInfo.protocol]?.default?
        defaults = @protocols[connectionInfo.protocol].default
        connectionInfo[attr] = value for attr,value of defaults
      $(@element).trigger('quickQuery.connect',[@buildConnection(connectionInfo)])

  addProtocol: (key,protocol)->
    @protocols[key] = protocol
    option = $('<option/>')
      .text(protocol.name)
      .val(key)
      .data('protocol',protocol)
    @find('#quick-query-protocol').append(option)
    for state in @connectionsStates
      state.callback(state.info) if state.info.protocol == key

  buildConnection: (connectionInfo)->
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

  @content: ->
    @div class: 'dialog quick-query-connect', =>
      @div class: "col-sm-12" , =>
        @label 'protocol'
        @select class: "form-control" , id: "quick-query-protocol", tabindex: "1"
      @div class: "col-sm-9 qq-remote-info" , =>
        @label 'host'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-host", class: 'editor', mini: 'mini', type: 'string'
      @div class:"col-sm-3 qq-remote-info" , =>
        @label 'port'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-port", class: 'editor', mini: 'mini', type: 'string'
      @div class: "qq-local-info" , =>
        @div class: "col-sm-12", =>
          @label 'file'
        @div class: "col-sm-9", =>
          @currentBuilder.tag 'atom-text-editor', id: "quick-query-file", class: 'editor', mini: 'mini', type: 'string'
        @div class: "col-sm-3", =>
          @button id:"quick-query-browse-file", class: "btn btn-default icon icon-file-directory", "Browse"
      @div class: "col-sm-6 qq-auth-info" , =>
        @label 'user'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-user", class: 'editor', mini: 'mini', type: 'string'
      @div class: "col-sm-6 qq-auth-info" , =>
        @label 'password'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-pass", class: 'editor', mini: 'mini'
      @div class: "col-sm-12" , =>
        @button id:"quick-query-connect", class: "btn btn-default icon icon-plug" , tabindex: "6" , "Connect"

  destroy: ->
    @element.remove()
  focusFirst: ->
    @find('#quick-query-protocol').focus()

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
