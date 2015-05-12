{ScrollView, $} = require 'atom-space-pen-views'

module.exports =
class QuickQueryBrowserView extends ScrollView

  editor: null
  connection: null
  connections: null

  constructor:  (connections)->
    @connections = connections
    @selectedConnection = connections[0]

    atom.commands.add '#quick-query-connections', 'quick-query:select-1000': => @simpleSelect()
    atom.commands.add '#quick-query-connections', 'quick-query:alter': => @alter()
    atom.commands.add '#quick-query-connections', 'quick-query:drop': => @drop()
    atom.commands.add '#quick-query-connections', 'quick-query:create': => @create()
    atom.commands.add '#quick-query-connections', 'quick-query:copy': => @copy()
    atom.commands.add '#quick-query-connections', 'quick-query:set-default': => @setDefault()

    super

  initialize: ->
    @find('#quick-query-new-connection').click (e) =>
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'quick-query:new-connection')
    @find('#quick-query-run').click (e) =>
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'quick-query:run')
    @find('#quick-query-connections').blur (e) =>
      $tree = $(e.currentTarget)
      $li = $tree.find('li.selected')
      $li.removeClass('selected')
    @handleResizeEvents()
  # Returns an object that can be retrieved when package is activated
  getTitle: ->
    return 'Query Result'
  serialize: ->

  @content: ->
    @div class: 'quick-query-browser tree-view-resizer tool-panel', 'data-show-on-right-side': true, =>
      @div =>
        @button id: 'quick-query-run', class: 'btn icon icon-playback-play' , title: 'Run' , style: 'width:50%'
        @button id: 'quick-query-new-connection', class: 'btn icon icon-plus' , title: 'New connection' , style: 'width:50%'
      @div class: 'tree-view-scroller', outlet: 'scroller', =>
        @ol id:'quick-query-connections' , class: 'tree-view list-tree has-collapsable-children focusable-panel', tabindex: -1, outlet: 'list'
      @div class: 'tree-view-resize-handle', outlet: 'resizeHandle'


  # Tear down any state and detach
  destroy: ->
    @element.remove()

  delete: ->
    connection = null
    $li = @find('ol:focus li.selected')
    if $li.length == 1
      connection = $li.data('connection')
      i = @connections.indexOf(connection)
      @connections.splice(i,1)
      @showConnections()
    connection


  setDefault: ->
    $li = @find('li.selected')
    unless $li.hasClass('default')
      $li.parent().find('li').removeClass('default')
      $li.addClass('default')
      model = @getItemModel($li)
      console.log model.connection.connection.config
      model.connection.setDefaultDatabase model.database

  addConnection: (connection) ->
    @selectedConnection = connection
    @connections.push(connection)
    @trigger('quickQuery.connectionSelected',[connection])
    @showConnections()

  showConnections: ()->
    $ol = @find('ol#quick-query-connections')
    $ol.empty()
    for connection in @connections
        $li = $('<li/>').addClass('entry list-nested-item collapsed')
        $li.addClass('quick-query-connection')
        if connection == @selectedConnection
          $li.addClass('default')
        $div = $('<div/>').addClass('header list-item qq-connection-item')
        $div.mousedown (e) =>
          $li = $(e.currentTarget).parent()
          $li.parent().find('li').removeClass('selected')
          $li.addClass('selected')
          $li.parent().find('li').removeClass('default')
          $li.addClass('default')
          @expandConnection($li) if e.which != 3
        $icon = $('<span/>').addClass('icon-plug')
        $div.text(connection)
        $div.prepend($icon)
        $li.data('connection',connection)
        $li.html($div)
        $ol.append($li)

  expandConnection: ($li)->
    connection = $li.data('connection')
    if connection != @selectedConnection
      @selectedConnection = connection
      @trigger('quickQuery.connectionSelected',[connection])
    $li.toggleClass('collapsed expanded')
    if $li.hasClass("expanded")
      connection.getDatabases (err,databases) =>
        @showDatabases(databases,$li) unless err

  showDatabases: (databases,$e) ->
    $ol = $e.find("ol.quick-query-databases")
    if $ol.length == 0
      $ol = $('<ol/>').addClass('list-tree entries has-collapsable-children')
      $ol.addClass("quick-query-databases")
      $e.append($ol)
    else
      $ol.empty()
    for database in databases
        $li = $('<li/>').addClass('entry list-nested-item collapsed')
        $li.addClass('quick-query-database')
        if database == @selectedConnection.getDefaultDatabase()
          $li.addClass('default')
        $div = $('<div/>').addClass('header list-item qq-database-item')
        $div.mousedown (e) =>
          $li = $(e.currentTarget).parent()
          $li.closest('ol#quick-query-connections').find('li').removeClass('selected')
          $li.addClass('selected')
          @expandDatabase($li) if e.which != 3
        $icon = $('<span/>').addClass('icon-database')
        $div.text(database)
        $div.prepend($icon)
        $li.data('database',database)
        $li.html($div)
        $ol.append($li)


  expandDatabase: ($li) ->
    $li.toggleClass('collapsed expanded')
    if $li.hasClass("expanded")
      model = @getItemModel($li)
      model.connection.getTables model.database , (tables) =>
        @showTables(tables,$li)

  showTables: (tables,$e) ->
    $ol = $e.find("ol.quick-query-tables")
    if $ol.length == 0
      $ol = $('<ol/>').addClass('list-tree entries has-collapsable-children')
      $ol.addClass("quick-query-tables")
      $e.append($ol)
    else
      $ol.empty()
    for table in tables
      $li = $('<li/>').addClass('entry list-nested-item collapsed')
      $li.addClass('quick-query-table')
      $div = $('<div/>').addClass('header list-item qq-table-item')
      $icon = $('<span/>').addClass('icon-browser')
      $div.text(table)
      $div.prepend($icon)
      $div.mousedown (e)=>
        $li = $(e.currentTarget).parent()
        $li.closest('ol#quick-query-connections').find('li').removeClass('selected')
        $li.addClass('selected')
        @expandTable($li) if e.which != 3
      $li.data('table',table)
      $li.html($div)
      $ol.append($li)

  expandTable: ($li) ->
    $li.toggleClass('collapsed expanded')
    if $li.hasClass('expanded')
      model = @getItemModel($li)
      model.connection.getColumns model.table , model.database , (columns, fields) =>
         @showColums(columns,$li)

  showColums: (columns,$e)->
    $ol = $e.find("ol.quick-query-columns")
    if $ol.length == 0
      $ol = $('<ol/>').addClass('list-tree entries')
      $ol.addClass("quick-query-columns")
      $e.append($ol)
    else
      $ol.empty()
    for column in columns
      $li = $('<li/>').addClass('entry')
      $li.addClass('quick-query-column')
      $div = $('<div/>').addClass('header list-item qq-column-item')
      if column.primary_key
        $icon = $('<span/>').addClass('icon-key')
      else
        $icon = $('<span/>').addClass('icon-tag')
      $div.text(column.name)
      $div.prepend($icon)
      $div.mousedown (e) =>
        $li = $(e.currentTarget).parent()
        @selectColumn($li)
      $li.data('column',column)
      $li.html($div)
      $ol.append($li)

  selectColumn: ($li) ->
    $li.closest('ol#quick-query-connections').find('li').removeClass('selected')
    $li.addClass('selected')

  refreshTree: (model)->
    switch model.type
      when 'database'
        $li = @find('li.quick-query-connection').filter (i,e)->
          $(e).data('connection') == model.connection
        $li.removeClass('collapsed')
        $li.addClass('expanded')
        model.connection.getDatabases model.database , (err,databases) =>
          @showDatabases(databases,$li) unless err
      when 'table'
        $li = @find('li.quick-query-database').filter (i,e)->
          $(e).data('database') == model.database
        $li.removeClass('collapsed')
        $li.addClass('expanded')
        model.connection.getTables model.database , (tables) =>
          @showTables(tables,$li)
      when 'column'
        $li = @find('li.quick-query-table').filter (i,e)->
          $(e).data('table') == model.table
        $li.removeClass('collapsed')
        $li.addClass('expanded')
        model.connection.getColumns model.database , (columns) =>
          @showTables(columns,$li)


  simpleSelect: ->
    $li = @find('li.selected.quick-query-table')
    if $li.length > 0
      model = @getItemModel($li)
      model.connection.getColumns model.table,model.database,(columns) =>
        text = model.connection.simpleSelect(model.table,model.database,columns)
        atom.workspace.open().then (editor) =>
          grammars = atom.grammars.getGrammars()
          grammar = (i for i in grammars when i.name is 'SQL')[0]
          editor.setGrammar(grammar)
          editor.insertText(text)

  copy: ->
    $li = @find('li.selected')
    $header = $li.find('div.header')
    if $header.length > 0
      atom.clipboard.write($header.text())

  create: ->
    $li = @find('li.selected')
    if $li.length > 0
      model = @getItemModel($li)
      @trigger('quickQuery.edit',['create',model])


  alter: ->
    $li = @find('li.selected')
    if $li.length > 0
      model = @getItemModel($li)
      @trigger('quickQuery.edit',['alter',model])

  drop: ->
    $li = @find('li.selected')
    if $li.length > 0
      model = @getItemModel($li)
      @trigger('quickQuery.edit',['drop',model])


  getItemModel: ($li)->
    connection = $li.closest('.quick-query-connection').data('connection')
    switch
      when $li.hasClass('quick-query-connection')
        {type: 'connection', connection:connection}
      when $li.hasClass('quick-query-database')
        database = $li.data('database')
        {type: 'database', database: database , connection:connection}
      when $li.hasClass('quick-query-table')
        database = $li.closest('.quick-query-database').data('database')
        table = $li.data('table')
        {type: 'table', table: table , database: database , connection:connection }
      when $li.hasClass('quick-query-column')
        database = $li.closest('.quick-query-database').data('database')
        table = $li.closest('.quick-query-table').data('table')
        column = $li.data('column')
        {type: 'column', column: column.name , info: column, table: table , database: database , connection:connection }

  #resizing methods copied from tree-view
  handleResizeEvents: ->
    @on 'dblclick', '.tree-view-resize-handle',  (e) => @resizeToFitContent()
    @on 'mousedown', '.tree-view-resize-handle', (e) => @resizeStarted(e)
  resizeStarted: =>
    $(document).on('mousemove', @resizeTreeView)
    $(document).on('mouseup', @resizeStopped)
  resizeStopped: =>
    $(document).off('mousemove', @resizeTreeView)
    $(document).off('mouseup', @resizeStopped)
  resizeTreeView: ({pageX, which}) =>
    return @resizeStopped() unless which is 1
    if @data('show-on-right-side')
      width = $(document.body).width() - pageX
    else
      width = pageX
    @width(width)
  resizeToFitContent: ->
    @width(1) # Shrink to measure the minimum width of list
    @width(@list.outerWidth())
