QuickQueryConnectView = require './quick-query-connect-view'
QuickQueryResultView = require './quick-query-result-view'
QuickQueryBrowserView = require './quick-query-browser-view'
QuickQueryEditorView = require './quick-query-editor-view'
QuickQueryTableFinderView = require './quick-query-table-finder-view'
QuickQueryMysqlConnection = require './quick-query-mysql-connection'
QuickQueryPostgresConnection = require './quick-query-postgres-connection'

{CompositeDisposable} = require 'atom'

module.exports = QuickQuery =
  config:
    resultsInTab:
      type: 'boolean'
      default: false
      title: 'Show results in a tab'

  editorView: null
  browser: null
  modalPanel: null
  bottomPanel: null
  rightPanel: null
  subscriptions: null
  connection: null
  connections: null
  queryEditors: []
  tableFinder: null

  activate: (state) ->
    protocols =
      mysql:
        name: "MySql"
        handler:QuickQueryMysqlConnection
      postgres:
        name: "PostgreSQL"
        handler: QuickQueryPostgresConnection
      "ssl-postgres":
        name: "PostgreSQL (ssl)"
        handler: QuickQueryPostgresConnection
        default:
          protocol: 'postgres'
          ssl: true

    @connections = []

    @tableFinder = new QuickQueryTableFinderView()

    @browser = new QuickQueryBrowserView()

    @connectView = new QuickQueryConnectView(protocols)

    if state.connections
      for connectionInfo in state.connections
        connectionPromise = @connectView.buildConnection(connectionInfo)
        @browser.addConnection(connectionPromise)
        connectionPromise.then(
          (connection) =>
              @connections.push(connection)
              connection.sentenceReady (text) =>
                @addSentence(text)
          (err) => console.log(err)
        )

    @browser.onConnectionSelected (connection) =>
      @connection = connection

    @browser.onConnectionDeleted (connection) =>
      i = @connections.indexOf(connection)
      @connections.splice(i,1)
      connection.close()
      @connection = null

    @browser.bind 'quickQuery.edit', (e,action,model) =>
      @editorView = new QuickQueryEditorView(action,model)
      if action == 'drop'
        @editorView.openTextEditor()
      else
        @modalPanel.destroy() if @modalPanel?
        @modalPanel = atom.workspace.addModalPanel(item: @editorView , visible: true)
        @editorView.focusFirst()

    @tableFinder.onCanceled => @modalPanel.destroy()
    @tableFinder.onFound (table) =>
      @modalPanel.destroy()
      @browser.reveal table, =>
        @browser.simpleSelect()

    @connectView.bind 'quickQuery.connect', (e,connectionPromise) =>
      @browser.addConnection(connectionPromise)
      connectionPromise.then(
        (connection) =>
            @connections.push(connection)
            @modalPanel.destroy()
            connection.sentenceReady (text) =>
              @addSentence(text)
        (err) => @setModalPanel content: err, type: 'error'
      )

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
      'quick-query:find-table-to-select': => @findTable()

    atom.commands.add '.quick-query-result',
     'quick-query:copy': => @activeResultView().copy()
     'quick-query:copy-all': => @activeResultView().copyAll()
     'quick-query:save-csv': => @activeResultView().saveCSV()
     'quick-query:insert': => @activeResultView().insertRecord()
     'quick-query:null': => @activeResultView().setNull()
     'quick-query:undo': => @activeResultView().undo()
     'quick-query:delete': => @activeResultView().deleteRecord()
     'quick-query:apply': => @activeResultView().apply()

    atom.config.onDidChange 'quick-query.resultsInTab', ({newValue, oldValue}) =>
      if !newValue
        for i in @queryEditors
          i.panel.hide()
          i.panel.destroy()
        @queryEditors = []

    atom.workspace.onDidChangeActivePaneItem (item) =>
      if !atom.config.get('quick-query.resultsInTab')
        for i in @queryEditors
          resultView = i.panel.getItem()
          if i.editor == item && !resultView.hiddenResults()
            i.panel.show()
            resultView.fixNumbers()
          else
            i.panel.hide()

    atom.workspace.paneContainer.onDidDestroyPaneItem (d) =>
      @queryEditors = @queryEditors.filter (i) =>
        i.panel.destroy() if i.editor == d.item
        i.editor != d.item

  addSentence: (text) ->
    queryEditor = atom.workspace.getActiveTextEditor()
    if queryEditor
      queryEditor.moveToBottom()
      queryEditor.insertNewline()
      queryEditor.insertText(text)
    else
      atom.workspace.open().then (editor) =>
        grammars = atom.grammars.getGrammars()
        grammar = (i for i in grammars when i.name is 'SQL')[0]
        editor.setGrammar(grammar)
        editor.insertText(text)

  deactivate: ->
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
    @modalPanel.destroy() if @modalPanel?
    @modalPanel = atom.workspace.addModalPanel(item: @connectView, visible: true)
    @connectView.focusFirst()
  run: ->
    @queryEditor = atom.workspace.getActiveTextEditor()
    unless @queryEditor
      @setModalPanel content:"This tab is not an editor", type:'error'
      return
    text = @queryEditor.getSelectedText()
    text = @queryEditor.getText() if(text == '')

    if @connection
      @setModalPanel content:"Running query...", spinner: true
      @connection.query text, (message, rows, fields) =>
        if (message)
          @setModalPanel(message)
          if message.type == 'success'
            @afterExecute(@queryEditor)
        else
          @setModalPanel content:"Loading results...", spinner: true
          if atom.config.get('quick-query.resultsInTab')
            queryResult = @showResultInTab()
          else
            queryResult = @showResultView(@queryEditor)
          queryResult.showRows rows, fields, @connection , =>
            @modalPanel.destroy() if @modalPanel
            queryResult.fixSizes() if rows.length > 100
          queryResult.fixSizes()

    else
      @setModalPanel content: "No connection selected"

  toggleBrowser: ->
    if @browser.is(':visible')
      @rightPanel.hide()
    else
      @browser.showConnections()
      @rightPanel.show()

  findTable: ()->
    if @connection
      @tableFinder.searchTable(@connection)
      @modalPanel.destroy() if @modalPanel?
      @modalPanel = atom.workspace.addModalPanel(item: @tableFinder , visible: true)
      @tableFinder.focusFilterEditor()
    else
      @setModalPanel content: "No connection selected"

  setModalPanel: (message)->
    item = document.createElement('div')
    item.classList.add('quick-query-modal-message')
    item.textContent = message.content
    if message.spinner? && message.spinner
      spinner = document.createElement('span')
      spinner.classList.add('loading')
      spinner.classList.add('loading-spinner-tiny')
      spinner.classList.add('inline-block')
      item.insertBefore(spinner,item.childNodes[0])
    if message.type == 'error'
      item.classList.add('text-error')
    close = document.createElement('span')
    close.classList.add('icon-x')
    close.onclick = (=> @modalPanel.destroy())
    item.appendChild(close)
    @modalPanel.destroy() if @modalPanel?
    @modalPanel = atom.workspace.addModalPanel(item: item , visible: true)

  showResultInTab: ->
    pane = atom.workspace.getActivePane()
    filter = pane.getItems().filter (item) ->
      item instanceof QuickQueryResultView
    if filter.length == 0
      queryResult = new QuickQueryResultView()
      pane.addItem queryResult
    else
      queryResult = filter[0]
    pane.activateItem queryResult
    queryResult

  afterExecute: (queryEditor)->
    if @editorView && @editorView.editor == queryEditor
      if !queryEditor.getPath?()
        queryEditor.setText('')
        atom.workspace.destroyActivePaneItem()
      @browser.refreshTree(@editorView.model)
      @modalPanel.destroy() if @modalPanel
      @editorView = null

  showResultView: (queryEditor)->
    e = (i for i in @queryEditors when i.editor == queryEditor)
    if e.length > 0
      e[0].panel.show()
      queryResult = e[0].panel.getItem()
    else
      queryResult = new QuickQueryResultView()
      bottomPanel = atom.workspace.addBottomPanel(item: queryResult, visible:true )
      @queryEditors.push({editor: queryEditor,  panel: bottomPanel})
    queryResult

  activeResultView: ->
    if atom.config.get('quick-query.resultsInTab')
      atom.workspace.getActivePaneItem()
    else
      editor = atom.workspace.getActiveTextEditor()
      for i in @queryEditors
        return i.panel.getItem() if i.editor == editor

  provideConnectView: ->
    @connectView

  cancel: ->
    @modalPanel.destroy() if @modalPanel
    for i in @queryEditors
      if i.editor == atom.workspace.getActiveTextEditor()
        resultView = i.panel.getItem()
        i.panel.hide()
        resultView.hideResults()
