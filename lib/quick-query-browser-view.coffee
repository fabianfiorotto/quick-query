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
      connection = $li.data('item')
      i = @connections.indexOf(connection)
      @connections.splice(i,1)
      @showConnections()
    connection

  setDefault: ->
    $li = @find('li.selected')
    unless $li.hasClass('default')
      $li.parent().find('li').removeClass('default')
      $li.addClass('default')
      model = $li.data('item')
      console.log model.connection.connection.config
      model.connection.setDefaultDatabase model.name

  addConnection: (connectionPromise) ->
    connectionPromise.then (connection)=>
      @selectedConnection = connection
      @connections.push(connection)
      @trigger('quickQuery.connectionSelected',[connection])
      @showConnections()

  showConnections: ()->
    $ol = @find('ol#quick-query-connections')
    $ol.empty()
    for connection in @connections
        $li = $('<li/>').addClass('entry list-nested-item collapsed')
        $div = $('<div/>').addClass('header list-item')
        $icon = $('<span/>').addClass('icon')
        if connection == @selectedConnection
          $li.addClass('default')
        $div.mousedown (e) =>
          $li = $(e.currentTarget).parent()
          $li.parent().find('li').removeClass('selected')
          $li.addClass('selected')
          $li.parent().find('li').removeClass('default')
          $li.addClass('default')
          @expandConnection($li) if e.which != 3
        $div.text(connection)
        $div.prepend($icon)
        $li.data('item',connection)
        $li.html($div)
        @setItemClasses(connection,$li)
        $ol.append($li)

  expandConnection: ($li)->
    connection = $li.data('item')
    if connection != @selectedConnection
      @selectedConnection = connection
      @trigger('quickQuery.connectionSelected',[connection])
    $li.toggleClass('collapsed expanded')
    if $li.hasClass("expanded")
      connection.getDatabases (databases,err) =>
        #@showDatabases(databases,$li) unless err
        @showItems(connection,databases,$li) unless err


  showItems: (parentItem,childrenItems,$e)->
    ol_class = switch parentItem.child_type
      when 'database'
        "quick-query-databases"
      when 'table'
        "quick-query-tables"
      when 'column'
        "quick-query-columns"
    $ol = $e.find("ol.#{ol_class}")
    if $ol.length == 0
      $ol = $('<ol/>').addClass('list-tree entries')
      if parentItem.child_type != 'column'
        $ol.addClass("has-collapsable-children")
      $ol.addClass(ol_class)
      $e.append($ol)
    else
      $ol.empty()
    for childItem in childrenItems
      $li = $('<li/>').addClass('entry')
      $div = $('<div/>').addClass('header list-item')
      $icon = $('<span/>').addClass('icon')
      if childItem.type != 'column'
        $li.addClass('list-nested-item collapsed')
      if childItem.type == 'database' && childItem.name == @selectedConnection.getDefaultDatabase()
        $li.addClass('default')
      $div.mousedown (e) =>
        $li = $(e.currentTarget).parent()
        $li.closest('ol#quick-query-connections').find('li').removeClass('selected')
        $li.addClass('selected')
        @expandItem($li) if e.which != 3
      $div.text(childItem)
      $div.prepend($icon)
      $li.data('item',childItem)
      $li.html($div)
      @setItemClasses(childItem,$li)
      $ol.append($li)

  setItemClasses: (item,$li)->
    $div = $li.children('.header')
    $icon = $div.children('.icon')
    switch item.type
      when 'connection'
        $li.addClass('quick-query-connection')
        $div.addClass("qq-connection-item")
        $icon.addClass('icon-plug')
      when 'database'
        $li.addClass('quick-query-database')
        $div.addClass("qq-database-item")
        $icon.addClass('icon-database')
      when 'table'
        $li.addClass('quick-query-table')
        $div.addClass("qq-table-item")
        $icon.addClass('icon-browser')
      when 'column'
        $li.addClass('quick-query-column')
        $div.addClass("qq-column-item")
        if item.primary_key
          $icon.addClass('icon-key')
        else
          $icon.addClass('icon-tag')

  expandItem: ($li) ->
    $li.toggleClass('collapsed expanded')
    if $li.hasClass("expanded")
      model = $li.data('item')
      model.children (children) =>
        @showItems(model,children,$li)

  refreshTree: (model)->
    $li = switch model.type
      when 'database'
        @find('li.quick-query-connection').filter (i,e)->
          $(e).data('item') == model.parent()
      when 'table'
        @find('li.quick-query-database').filter (i,e)->
          $(e).data('item') == model.parent()
      when 'column'
        @find('li.quick-query-table').filter (i,e)->
          $(e).data('item') == model.parent()
    $li.removeClass('collapsed')
    $li.addClass('expanded')
    $li.find('ol').empty();
    model.parent().children (children) =>
      @showItems(model.parent(),children,$li)


  simpleSelect: ->
    $li = @find('li.selected.quick-query-table')
    if $li.length > 0
      model = $li.data('item')
      model.connection.getColumns model ,(columns) =>
        text = model.connection.simpleSelect(model,columns)
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
      model = $li.data('item')
      @trigger('quickQuery.edit',['create',model])


  alter: ->
    $li = @find('li.selected')
    if $li.length > 0
      model = $li.data('item')
      @trigger('quickQuery.edit',['alter',model])

  drop: ->
    $li = @find('li.selected')
    if $li.length > 0
      model = $li.data('item')
      @trigger('quickQuery.edit',['drop',model])

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
