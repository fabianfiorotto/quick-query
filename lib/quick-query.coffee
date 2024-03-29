ConnectView = require './views/connect'
ResultView = require './views/result'
BrowserView = require './views/browser'
EditorView = require './views/editor'
TableFinderView = require './views/table-finder'
DumpLoader = require './views/dump-loader'
MysqlConnection = require './connections/mysql'
PostgresConnection = require './connections/postgres'
Autocomplete = require './autocomplete'
CsvEditor = require './views/csv-editor'
ModalView = require './views/modal'
ViewSpinner = require './views/spinner'

path = require 'path'
fs = require 'fs'
{remote} = require 'electron'

{CompositeDisposable} = require 'atom'

module.exports = QuickQuery =
  config:
    autompleteIntegration:
      type: 'boolean'
      default: true
      title: 'Autocomplete integration'
    canUseStatusBar:
      type: 'boolean'
      default: true
      title: 'Show info in status bar'
    browserButtons:
      type: 'boolean'
      default: true
      title: 'Browser buttons'
    resultsInTab:
      type: 'boolean'
      default: false
      title: 'Show results in a tab'
    storeGlobally:
      type: 'boolean'
      default: false
      title: 'Store connections globally'

  editorView: null
  browser: null
  modalPanel: null
  modalConnect: null
  modalSpinner: null
  bottomPanel: null
  sidePanel: null
  subscriptions: null
  connection: null
  connections: null
  queryEditors: []
  tableFinder: null

  activate: (state) ->
    protocols =
      mysql:
        name: "MySql"
        handler:MysqlConnection
      postgres:
        name: "PostgreSQL"
        handler: PostgresConnection
      "ssl-postgres":
        name: "PostgreSQL (ssl)"
        handler: PostgresConnection
        default:
          protocol: 'postgres'
          ssl: true

    @connections = []

    @tableFinder = new TableFinderView()

    @browser = new BrowserView()

    @connectView = new ConnectView(protocols)
    @modalConnect = atom.workspace.addModalPanel(item: @connectView , visible: false)

    @modalSpinner = atom.workspace.addModalPanel(item: new ViewSpinner() , visible: false)

    storage = state
    if atom.config.get('quick-query.storeGlobally')
      gloalStoragePath = path.join(process.env.ATOM_HOME, 'quick-query.json')
      if fs.existsSync(gloalStoragePath)
        storage = JSON.parse(fs.readFileSync(gloalStoragePath))
    if storage.connections?
      for connectionInfo in storage.connections
        connectionPromise = @connectView.buildConnection(connectionInfo)
        @browser.addConnection(connectionPromise)

    @browser.onConnectionSelected (connection) =>
      @connection = connection

    @browser.onConnectionDeleted (connection) =>
      i = @connections.indexOf(connection)
      @connections.splice(i,1)
      connection.close()
      if @connections.length > 0
        @browser.selectConnection(@connections[@connections.length-1])
      else
        @connection = null

    @browser.onItemEdit ([action,model]) =>
      @editorView = new EditorView(action,model)
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

    @connectView.onConnectionStablished (connection)=>
      @connections.push(connection)
      if atom.config.get('quick-query.storeGlobally')
        gloalStoragePath = path.join(process.env.ATOM_HOME, 'quick-query.json')
        connectionsInfo = JSON.stringify(connections: @connections.map((c)-> c.serialize()),null,2)
        fs.writeFile gloalStoragePath, connectionsInfo , ((err)-> console.log(err) if err?)

    @connectView.onWillConnect (connectionPromise) =>
      @browser.addConnection(connectionPromise)
      connectionPromise.then(
        (connection) => @modalConnect.hide()
        (err) => @setModalPanel content: err, type: 'error'
      )

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace',
      'quick-query:run': => @run()
      'quick-query:new-editor': => @newEditor()
      'quick-query:toggle-browser': => @toggleBrowser()
      'quick-query:toggle-results': => @toggleResults()
      'core:cancel': => @cancel()
      'quick-query:new-connection': => @newConnection()
      'quick-query:find-table-to-select': => @findTable()
      'quick-query:open-dump-loader': => @openDumpLoader()
      'quick-query:open-csv': => @openCSV()

    @subscriptions.add atom.commands.add '.quick-query-grid-table',
      'core:save':    => @activeResultPane().applyChanges() if atom.config.get('quick-query.resultsInTab')
      'core:save-as': => @activeResultGrid().saveCSV() if atom.config.get('quick-query.resultsInTab')
      'quick-query:copy-changes': => @activeResultView().copyChanges()
      'quick-query:apply-changes': => @activeResultView().applyChanges()

    @subscriptions.add atom.commands.add '#quick-query-connections',
      'quick-query:export-connections': => @exportConnections()
      'quick-query:import-connections': => @importConnections()
      'quick-query:reconnect':   => @reconnect()

    @subscriptions.add atom.workspace.addOpener (uri,options) =>
      return new DumpLoader(@browser, filename: uri) if @isSqlDump(uri)
      return new DumpLoader(@browser,options) if (uri == 'quick-query://dump-loader')
      return new CsvEditor({filepath: uri, text: options.text}) if options.qqCsv
      return @browser if (uri == 'quick-query://browser')

    atom.config.onDidChange 'quick-query.resultsInTab', ({newValue, oldValue}) =>
      if newValue
        for i in @queryEditors
          i.panel.hide()
          i.panel.destroy()
        @queryEditors = []
      else
        pane = atom.workspace.getActivePane()
        for item in pane.getItems()
          pane.destroyItem(item) if item instanceof ResultView

    atom.config.onDidChange 'quick-query.storeGlobally', ({newValue, oldValue}) =>
      gloalStoragePath = path.join(process.env.ATOM_HOME, 'quick-query.json')
      if newValue
        connectionsInfo = JSON.stringify(connections: @connections.map((c)-> c.serialize()),null,2)
        fs.writeFile gloalStoragePath, connectionsInfo , ((err)-> console.log(err) if err?)
      else if fs.existsSync(gloalStoragePath)
        fs.unlink gloalStoragePath, ((err)-> console.log(err) if err?)

    atom.workspace.getCenter().onDidChangeActivePaneItem (item) =>
      @hideStatusBar()
      if !atom.config.get('quick-query.resultsInTab')
        for i in @queryEditors
          resultView = i.panel.getItem()
          if i.editor == item && !resultView.hiddenResults()
            i.panel.show()
          else
            i.panel.hide()
          @updateStatusBar(resultView) if i.editor == item
      else if item instanceof ResultView
        item.focusTable()
        @updateStatusBar(item)

    atom.workspace.getCenter().onDidDestroyPaneItem (d) =>
      @queryEditors = @queryEditors.filter (i) =>
        i.panel.destroy() if i.editor == d.item
        i.editor != d.item

  deactivate: ->
    c.close() for c in @connections
    @subscriptions.dispose()
    i.panel.destroy() for i in @queryEditors
    @browser.destroy()
    @connectView.destroy()
    @modalPanel?.destroy()
    @modalConnect.destroy()
    @modalSpinner.destroy()
    @statusBarTile?.destroy()
    pane = atom.workspace.getActivePane()
    for item in pane.getItems() when item instanceof ResultView
      pane.destroyItem(item)

  serialize: ->
    if !atom.config.get('quick-query.storeGlobally')
      connections: @connections.map((c)-> c.serialize()),
  newEditor: ->
    atom.workspace.open().then (editor) =>
      atom.textEditors.setGrammarOverride(editor, 'source.sql')
  newConnection: ->
    @modalConnect.show()
    @connectView.focusFirst()

  run: ->
    @queryEditor = atom.workspace.getCenter().getActiveTextEditor()
    unless @queryEditor
      @setModalPanel content:"This tab is not an editor", type:'error'
      return
    text = @queryEditor.getSelectedText()
    text = @queryEditor.getText() if(text == '')

    if @connection
      @showModalSpinner content:"Running query..."
      @connection.query text, (message, rows, fields) =>
        if (message)
          @modalSpinner.hide()
          if message.type == 'error'
            @setModalPanel message
          else
            @addInfoNotification(message.content);
          if message.type == 'success'
            @afterExecute(@queryEditor)
        else
          @modalSpinner.hide()
          if atom.config.get('quick-query.resultsInTab')
            queryResult = @showResultInTab()
          else
            queryResult = @showResultView(@queryEditor)
          queryResult.showRows rows, fields, @connection
          @updateStatusBar(queryResult)

    else
      @addWarningNotification("No connection selected")

  openDumpLoader: ->
    atom.workspace.open('quick-query://dump-loader')

  toggleBrowser: ->
    atom.workspace.toggle('quick-query://browser')

  exportConnections: ->
    options =
      title: 'Export connections'
      defaultPath: path.join(process.cwd(), 'connections.json')
    atom.getCurrentWindow().showSaveDialog options, (filepath) =>
      if filepath?
        connectionsInfo = JSON.stringify(@connections.map((c)-> c.serialize()),null,2)
        fs.writeFile filepath, connectionsInfo , ((err)-> console.log(err) if err?)

  importConnections: ->
    currentWindow = atom.getCurrentWindow()
    options =
      properties: ['openFile']
      title: 'Import Connections'
      filters: [{ name: 'Connections', extensions: ['json'] }]
    remote.dialog.showOpenDialog(currentWindow, options).then (dialog) =>
      if dialog && !dialog.canceled
        for connectionInfo in JSON.parse(fs.readFileSync(dialog.filePaths[0]))
          connectionPromise = @connectView.buildConnection(connectionInfo)
          @browser.addConnection(connectionPromise)

  reconnect: ->
    oldConnection = @connection
    pos = @browser.connections.indexOf(oldConnection)
    connectionInfo = oldConnection.serialize()
    connectionPromise = @connectView.buildConnection(connectionInfo)
    @browser.addConnection(connectionPromise,pos)
    connectionPromise.then(
      (newConnection) => @browser.removeConnection(oldConnection)
      (err) => @setModalPanel content: err, type: 'error'
    )

  findTable: ()->
    if @connection
      @tableFinder.searchTable(@connection)
      @modalPanel.destroy() if @modalPanel?
      @modalPanel = atom.workspace.addModalPanel(item: @tableFinder , visible: true)
      @tableFinder.focusFilterEditor()
    else
      @addWarningNotification "No connection selected"

  isSqlDump: (uri)->
    if path.extname(uri) == '.gz'
      baseuri = path.basename(uri, '.gz')
      path.extname(baseuri) == '.sql' || path.extname(baseuri) == '.mysql'
    else
      path.extname(uri) == '.mysql'

  addWarningNotification:(message) ->
    notification = atom.notifications.addWarning(message);
    view = atom.views.getView(notification)
    view?.element.addEventListener 'click', (e) -> view.removeNotification()

  addInfoNotification: (message)->
    notification = atom.notifications.addInfo(message);
    view = atom.views.getView(notification)
    view?.element.addEventListener 'click', (e) -> view.removeNotification()

  openCSV: ->
    editor = atom.workspace.getCenter().getActiveTextEditor()
    unless editor
      @setModalPanel content:"This tab is not an editor", type:'error'
      return
    text = editor.getText()
    filepath = editor.getPath()
    editor.destroy()
    atom.workspace.open(filepath, qqCsv: true, text: text)

  setModalPanel: (message)->
    modal = new ModalView(message)
    modal.onClose => @modalPanel.destroy()
    @modalPanel.destroy() if @modalPanel?
    @modalPanel = atom.workspace.addModalPanel(item: modal , visible: true)
    @modalPanel.onDidDestroy => modal.destroy()

  showModalSpinner: (message)->
    @modalSpinner.getItem().setMessage(message)
    @modalSpinner.show()

  showResultInTab: ->
    pane = atom.workspace.getCenter().getActivePane()
    filter = pane.getItems().filter (item) ->
      item instanceof ResultView
    if filter.length == 0
      queryResult = new ResultView()
      queryResult.grid.onRowStatusChanged => @updateStatusBar(queryResult)
      pane.addItem queryResult
    else
      queryResult = filter[0]
    pane.activateItem queryResult
    queryResult

  afterExecute: (queryEditor)->
    if @editorView && @editorView.editor == queryEditor
      if !queryEditor.getPath?()
        queryEditor.setText('')
        queryEditor.destroy()
      if @editorView.action == 'create'
        @browser.refreshTree(@editorView.model)
      else
        @browser.refreshTree(@editorView.model.parent())
      @modalPanel.destroy() if @modalPanel
      @editorView = null

  showResultView: (queryEditor)->
    e = (i for i in @queryEditors when i.editor == queryEditor)
    if e.length > 0
      e[0].panel.show()
      queryResult = e[0].panel.getItem()
    else
      queryResult = new ResultView()
      queryResult.grid.onRowStatusChanged => @updateStatusBar(queryResult)
      bottomPanel = atom.workspace.addBottomPanel(item: queryResult, visible:true )
      queryResult.panel = bottomPanel
      @queryEditors.push({editor: queryEditor,  panel: bottomPanel})
    queryResult

  activeResultPane: ->
    return null if atom.config.get('quick-query.resultsInTab')
    editor = atom.workspace.getCenter().getActiveTextEditor()
    for i in @queryEditors
      return i.panel if i.editor == editor

  activeResultView: ->
    if atom.config.get('quick-query.resultsInTab')
      item = atom.workspace.getActivePaneItem()
      if item instanceof ResultView
        return item
      else
        return null
    else
      @activeResultPane()?.getItem()

  activeResultGrid: ->
    @activeResultView()?.grid

  provideBrowserView: -> @browser

  provideConnectView: -> @connectView

  provideAutocomplete: -> new Autocomplete(@browser)

  consumeStatusBar: (statusBar) ->
    element = document.createElement('a')
    element.classList.add('quick-query-tile', 'hide')
    element.onclick = (=> @toggleResults())
    @statusBarTile = statusBar.addLeftTile(item: element, priority: 10)

  hideStatusBar: ->
    if @statusBarTile?
      span = @statusBarTile.getItem()
      span.classList.add('hide')

  updateStatusBar: (queryResult) ->
    return unless @statusBarTile? && queryResult?.grid?.rows?
    return unless atom.config.get('quick-query.canUseStatusBar')
    element = @statusBarTile.getItem()
    element.classList.remove('hide')
    if atom.config.get('quick-query.resultsInTab')
      element.textContent = "(#{queryResult.grid.rowsStatus()})"
    else
      element.textContent = "#{queryResult.getTitle()} (#{queryResult.grid.rowsStatus()})"

  toggleResults: ->
    return if atom.config.get('quick-query.resultsInTab')
    resultView = @activeResultView()
    resultView?.toggleResults();

  cancel: ->
    @modalPanel.destroy() if @modalPanel
    @modalConnect.hide()
    resultView = @activeResultView()
    if resultView?
      resultView.cancel()
      @updateStatusBar(resultView)
    @modalSpinner.hide()
