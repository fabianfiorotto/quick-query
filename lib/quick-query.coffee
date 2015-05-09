QuickQueryConnectView = require './quick-query-connect-view'
QuickQueryResultView = require './quick-query-result-view'
QuickQueryBrowserView = require './quick-query-browser-view'
QuickQueryEditorView = require './quick-query-editor-view'
QuickQueryMysqlConnection = require './quick-query-mysql-connection'
{CompositeDisposable} = require 'atom'

mysql = require 'mysql'

module.exports = QuickQuery =
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

    # info = { host: 'localhost', user: 'root', password: 'root' }
    # @connection = new QuickQueryMysqlConnection(info)
    # @browser.addConnection(@connection)

    if state.connections
      for connecectionInfo in state.connections
        connection = new QuickQueryMysqlConnection connecectionInfo , (err) =>
          @browser.addConnection(connection) unless err

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
      connection = new QuickQueryMysqlConnection connectionInfo , (err) =>
        if err
          @setModalPanel(err)
        else
          @browser.addConnection(connection)
          @modalPanel.hide()

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
    editor = atom.workspace.getActivePaneItem()
    text = editor.getSelectedText()
    text = editor.getText() if(text == '')

    if @connection
      @connection.query text, (message, rows, fields) =>
        if (message)
          @setModalPanel(message.content)
          if message.type == 'success'
            @afterExecute(editor)
        else
          @queryResult.show(rows, fields)
          if true
            @bottomPanel.show()
          else
            @showResultInTab()
          @queryResult.fixSizes()

    else
      @setModalPanel("No connection selected")

  toggleBrowser: ->
    if @browser.is(':visible')
      @rightPanel.hide()
    else
      @browser.showConnections()
      @rightPanel.show()


  setModalPanel: (text)->
    item = document.createElement('div')
    item.textContent = text
    @modalPanel = atom.workspace.addModalPanel(item: item , visible: true)

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
