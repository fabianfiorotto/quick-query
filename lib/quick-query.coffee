QuickQueryConnectView = require './quick-query-connect-view'
QuickQueryResultView = require './quick-query-result-view'
QuickQueryBrowserView = require './quick-query-browser-view'
QuickQueryEditorView = require './quick-query-editor-view'
QuickQueryMysqlConnection = require './quick-query-mysql-connection'
{CompositeDisposable} = require 'atom'

mysql = require 'mysql'

module.exports = QuickQuery =
  config:
    resultsInTab:
      type: 'boolean'
      default: false
      title: 'Show results in a tab'

  editorView: null
  queryResult: null
  browser: null
  modalPanel: null
  bottomPanel: null
  rightPanel: null
  subscriptions: null
  connection: null
  connections: null

  activate: (state) ->
    @connections = []

    @queryResult = new QuickQueryResultView()
    @browser = new QuickQueryBrowserView(@connections)

    if state.connections
      for connectionInfo in state.connections
        connectionPromise = @buildConnection(connectionInfo)
        @browser.addConnection(connectionPromise)

    @connectView = new QuickQueryConnectView()

    @browser.bind 'quickQuery.connectionSelected', (e,connection) =>
      @connection = connection

    @browser.bind 'quickQuery.edit', (e,action,model) =>
      @editorView = new QuickQueryEditorView(action,model)
      if action == 'drop'
        @editorView.openTextEditor()
      else
        @modalPanel = atom.workspace.addModalPanel(item: @editorView , visible: true)
        @editorView.focusFirst()

    @connectView.bind 'quickQuery.connect', (e,connectionInfo) =>
      connectionPromise = @buildConnection(connectionInfo)
      @browser.addConnection(connectionPromise)
      connectionPromise.then(
        (connection) => @modalPanel.hide()
        (err) => @setModalPanel content: err, type: 'error'
      )

    @bottomPanel = atom.workspace.addBottomPanel(item: @queryResult, visible:false )
    @rightPanel = atom.workspace.addRightPanel(item: @browser, visible:false )

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace',
      'quick-query:run': => @run()
      'quick-query:new-editor': => @newEditor()
      'quick-query:toggle-browser': => @toggleBrowser()
      'core:cancel': => @cancel()
      'quick-query:new-connection': => @newConnection()
    @subscriptions.add atom.commands.add 'ol#quick-query-connections', 'core:delete': => @delete()

    atom.config.onDidChange 'quick-query.resultsInTab', ({newValue, oldValue}) =>
      @bottomPanel.hide()
      unless newValue
        @queryResult = new QuickQueryResultView()
        @bottomPanel = atom.workspace.addBottomPanel(item: @queryResult, visible:false )

  deactivate: ->
    @modalPanel.destroy()
    @subscriptions.dispose()
    @quickQueryView.destroy()

  serialize: ->
     connections: @connections.map (c)-> c.serialize()
  newEditor: ->
    atom.workspace.open().then (editor) =>
      grammars = atom.grammars.getGrammars()
      grammar = (i for i in grammars when i.name is 'SQL')[0]
      editor.setGrammar(grammar)
  newConnection: ->
    @modalPanel = atom.workspace.addModalPanel(item: @connectView, visible: true)
    @connectView.focusFirst()
  run: ->
    editor = atom.workspace.getActiveTextEditor()
    unless editor
      @setModalPanel content:"This tab is not a editor", type:'error'
      return
    text = editor.getSelectedText()
    text = editor.getText() if(text == '')

    if @connection
      @connection.query text, (message, rows, fields) =>
        if (message)
          @setModalPanel(message)
          if message.type == 'success'
            @afterExecute(editor)
        else
          @queryResult.show(rows, fields)
          if atom.config.get('quick-query.resultsInTab')
            @showResultInTab()
          else
            @bottomPanel.show()
          @queryResult.fixSizes()
          @modalPanel.hide() if @modalPanel
    else
      @setModalPanel content: "No connection selected"

  toggleBrowser: ->
    if @browser.is(':visible')
      @rightPanel.hide()
    else
      @browser.showConnections()
      @rightPanel.show()


  setModalPanel: (message)->
    item = document.createElement('div')
    item.textContent = message.content
    if message.type == 'error'
      item.classList.add('text-error')
    @modalPanel = atom.workspace.addModalPanel(item: item , visible: true)

  buildConnection: (connectionInfo)->
    new Promise (resolve, reject)->
      # if connectionInfo.protocol == 'mysql'
      connection = new QuickQueryMysqlConnection connectionInfo
      connection.connect (err) ->
        if err
          reject(err)
        else
          resolve(connection)

  showResultInTab: ->
    pane = atom.workspace.getActivePane()
    items = pane.getItems()
    filter = items.filter (item) ->
      item instanceof QuickQueryResultView
    if filter.length == 0
      item = pane.addItem @queryResult
    else
      item = filter[0]
    pane.activateItem item

  afterExecute: (editor)->
    if @editorView && @editorView.editor == editor
      if !editor.getPath?()
        editor.setText('')
        atom.workspace.destroyActivePaneItem()
      @browser.refreshTree(@editorView.model)
      @modalPanel.hide() if @modalPanel
      @editorView = null

  cancel: ->
    @modalPanel.hide() if @modalPanel
    @bottomPanel.hide()

  delete: ->
    connection = @browser.delete()
    if connection
      i = @connections.indexOf(connection)
      @connections.splice(i,1)
      @connection = null
