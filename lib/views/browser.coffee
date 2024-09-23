{View, $, $$} = require './space-pen'
{Emitter, CompositeDisposable} = require 'atom'

module.exports =
class BrowserView extends View

  editor: null
  connection: null
  connections: []
  selectedConnection: null

  constructor: ->
    @emitter = new Emitter()
    @subscriptions = new CompositeDisposable()
    super

  initialize: ->
    @subscriptions.add atom.commands.add @element,
      'quick-query:import-dump': => @importDump()
      'quick-query:select-1000': => @simpleSelect()
      'quick-query:set-default': => @setDefault()
      'quick-query:alter':  => @alter()
      'quick-query:drop':   => @drop()
      'quick-query:create': => @create()
      'quick-query:copy':   => @copy()
      'core:copy':       => @copy()
      'core:delete':     => @delete()
      'core:move-up':    => @moveUp()
      'core:move-down':  => @moveDown()
      'core:confirm':    => @expandSelected()
    if !atom.config.get('quick-query.browserButtons')
      @element.classList.add('no-buttons')
    atom.config.onDidChange 'quick-query.browserButtons', ({newValue, oldValue}) =>
      if newValue then @element.classList.remove('no-buttons') else @element.classList.add('no-buttons')
    @newConnection.click (e) =>
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'quick-query:new-connection')
    @searchButton.click (e) =>
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'quick-query:find-table-to-select')
    @runButton.click (e) =>
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'quick-query:run')

  # Returns an object that can be retrieved when package is activated
  getTitle: -> 'Databases'

  serialize: ->

  @content: ->
    @div class: 'quick-query-browser tool-panel', =>
      @div class: 'btn-group', outlet: 'buttons', =>
        @button outlet: 'runButton', class: 'btn icon icon-playback-play' , title: 'Run'
        @button outlet: 'searchButton', class: 'btn icon icon-search-save' , title: 'Search Table'
        @button outlet: 'newConnection', class: 'btn icon icon-plus' , title: 'New connection'
      @ol id:'quick-query-connections' , class: 'list-tree has-collapsable-children focusable-panel', tabindex: -1, outlet: 'list'

  # Tear down any state and detach
  destroy: ->
    @element.remove()
    @subscriptions.disponse()
    @emitter.dispose()

  delete: ->
    connection = null
    $li = $(@element).find('ol:focus li.selected')
    model = $li.data('item')
    if $li.hasClass('quick-query-connection')
      @removeConnection(model)
    else
      @emitter.emit('did-item-edit', ['drop',model])

  removeConnection: (connection)->
    i = @connections.indexOf(connection)
    @connections.splice(i,1)
    @showConnections()
    @emitter.emit('did-connection-deleted', connection)

  getURI: -> 'quick-query://browser'
  getDefaultLocation: ->
    if atom.config.get('quick-query.showBrowserOnLeftSide')
      'left'
    else
      'right'
  getAllowedLocations: -> ['left', 'right']
  isPermanentDockItem: -> true

  getSelected: ->
    $(@element).find('li.selected')

  setDefault: ->
    $li = @getSelected()
    unless $li.hasClass('default')
      model = $li.data('item')
      model.connection.setDefaultDatabase model.name

  moveUp: ->
    $li = @getSelected()
    $prev = $li.prev()
    while $prev.hasClass('expanded') && $prev.find('>ol>li').length > 0
      $prev = $prev.find('>ol>li:last')
    if $prev.length == 0 && $li.parent().get(0) != @list[0]
      $prev = $li.parent().parent()
    if $prev.length
      $prev.addClass('selected')
      $li.removeClass('selected')
      @scrollToItem($prev)

  moveDown: ->
    $i = $li = @getSelected()
    if $li.hasClass('expanded') && $li.find('>ol>li').length > 0
      $next = $li.find('>ol>li:first')
    else
      $next = $li.next()
    while $next.length == 0 && $i.length != 0 && $i.parent().get(0) != @list[0]
      $i = $i.parent().parent()
      $next = $i.next()
    if $next.length
      $next.addClass('selected')
      $li.removeClass('selected')
      @scrollToItem($next)

  scrollToItem: ($li)->
    list_height = @list.outerHeight()
    height = $li.children('div').height()
    top = $li.position().top
    bottom = top + height
    scroll = @list.scrollTop()
    if bottom > list_height
      @list.scrollTop(scroll - list_height + bottom)
    else if top < 0
      @list.scrollTop(scroll + top)

  addConnection: (connectionPromise,pos) ->
    connectionPromise.then (connection)=>
      @selectedConnection = connection
      if pos?
        @connections.splice(pos, 0, connection)
      else
        @connections.push(connection)
      @emitter.emit('did-connection-selected', connection)
      @showConnections()
      connection.onDidChangeDefaultDatabase (database) =>
        @defaultDatabaseChanged(connection,database)

  defaultDatabaseChanged: (connection,database)->
    @list.children().each (i,e)->
      if $(e).data('item') == connection
        $(e).find(".quick-query-database").removeClass('default')
        $(e).find(".quick-query-database[data-name=\"#{database}\"]").addClass('default')

  newItem: (item)->
    nested = if item.type != 'column' then 'list-nested-item collapsed' else ''
    [liClass, divClass, icon] = @getItemClasses(item)
    $$ ->
      @li class: "entry #{liClass} #{nested}", 'data-name': item.name, =>
        @div class: "header list-item #{divClass}", =>
          @span class: "icon #{icon}"
          @text item.toString()

  showConnections: ()->
    $ol = @list
    $ol.empty()
    for connection in @connections
        $li = @newItem(connection)
        $li.attr('data-protocol',connection.protocol)
        if connection == @selectedConnection
          $li.addClass('default')
        $li.children('div').mousedown (e) =>
          $li = $(e.currentTarget).parent()
          $li.parent().find('li').removeClass('selected')
          $li.addClass('selected')
          $li.parent().find('li').removeClass('default')
          $li.addClass('default')
          @expandConnection($li) if e.which != 3
        $li.data('item',connection)
        $ol.append($li)

  expandConnection: ($li,callback)->
    connection = $li.data('item')
    if connection != @selectedConnection
      @selectedConnection = connection
      @emitter.emit('did-connection-selected', connection)
    @expandItem($li,callback)

  showItems: (parentItem,childrenItems,$e)->
    ol_class = switch parentItem.child_type
      when 'database'
        "quick-query-databases"
      when 'schema'
        "quick-query-schemas"
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
    if parentItem.child_type != 'column'
      childrenItems = childrenItems.sort(@compareItemName)
    for childItem in childrenItems
      $li = @newItem(childItem)
      $li.children('div').mousedown (e) =>
        $li = $(e.currentTarget).parent()
        @list.find('li').removeClass('selected')
        $li.addClass('selected')
        @expandItem($li) if e.which != 3
      $li.data('item',childItem)
      $ol.append($li)

  getItemClasses: (item)->
    switch item.type
      when 'connection'
        ['quick-query-connection', 'qq-connection-item', 'icon-plug']
      when 'database'
        liClass = if item.name == @selectedConnection.getDefaultDatabase() then 'default' else ''
        ["quick-query-database #{liClass}",'qq-database-item','icon-database']
      when 'schema'
        ['quick-query-schema','qq-schema-item','icon-book']
      when 'table'
        [ 'quick-query-table', 'qq-table-item', 'icon-browser']
      when 'column'
        icon = if item.primary_key then 'icon-key' else 'icon-tag'
        ['quick-query-column','qq-column-item', icon]

  timeout: (t,bk) -> setTimeout(bk,t)

  expandSelected: (callback)->
    $li = @getSelected()
    @expandItem($li,callback)

  expandItem: ($li,callback) ->
    $li.toggleClass('collapsed expanded')
    if $li.hasClass("expanded") && !$li.hasClass("busy")
      $li.addClass('busy')
      $div = $li.children('div')
      $div.children('.loading,.icon-stop').remove()
      $icon = $div.children('.icon')
      $loading = $('<span>').addClass("loading loading-spinner-tiny inline-block").hide()
      $div.prepend($loading)
      time1 = Date.now()
      t100 = @timeout 100, =>
        $icon.hide()
        $loading.show()
      t5000 = @timeout 5000, =>
        $li.removeClass('busy')
        $loading.attr('class','icon icon-stop')
      model = $li.data('item')
      model.children (children) =>
        clearTimeout(t100)
        clearTimeout(t5000)
        time2 = Date.now()
        $li.removeClass('busy')
        if time2 - time1 < 5000
          $loading.remove()
          $icon.css('display','')
          @showItems(model,children,$li)
          callback(children) if callback

  refreshTree: (model)->
    selector = switch model.type
      when 'connection' then 'li.quick-query-connection'
      when 'database' then 'li.quick-query-database'
      when 'schema' then 'li.quick-query-schema'
      when 'table' then 'li.quick-query-table'
      else 'li'
    $li = $(@element).find(selector).filter (i,e)-> $(e).data('item') == model
    $li.removeClass('collapsed')
    $li.addClass('expanded')
    $li.find('ol').empty();
    model.children (children) => @showItems(model,children,$li)

  expand: (model,callback)->
    if model.type == 'connection'
      @list.children().each (i,li) =>
        if $(li).data('item') == model
          $(li).removeClass('expanded').addClass('collapsed') #HACK?
          @expandConnection $(li) , =>
            callback($(li)) if callback
    else
      parent = model.parent()
      @expand parent, ($li) =>
        $ol = $li.children("ol")
        $ol.children().each (i,li) =>
          item = $(li).data('item')
          if item && item.name == model.name && item.type == model.type
            @expandItem $(li) , =>
              callback($(li)) if callback

  reveal: (model,callback) ->
    @expand model, ($li) =>
      $li.addClass('selected')
      top = $li.position().top
      bottom = top + $li.outerHeight()
      if bottom > @list.scrollTop() + @list.height()
        @list.scrollTop(bottom - @list.height())
      if top < @list.scrollTop()
        @list.scrollTop(top)
      callback() if callback

  compareItemName: (item1,item2)->
    if (item1.name < item2.name)
      return -1
    else if (item1.name > item2.name)
      return 1
    else
      return 0

  simpleSelect: ->
    $li = $(@element).find('li.selected.quick-query-table')
    if $li.length > 0
      model = $li.data('item')
      model.connection.getColumns model ,(columns) =>
        text = model.connection.simpleSelect(model,columns)
        atom.workspace.open().then (editor) =>
          atom.textEditors.setGrammarOverride(editor, 'source.sql')
          editor.insertText(text)
          editor.getBuffer().clearUndoStack()

  importDump: ->
    $li = @getSelected()
    model = $li.data('item')
    atom.workspace.open('quick-query://dump-loader', database: model.name )

  copy: ->
    $li = @getSelected()
    $header = $li.children('div.header')
    if $header.length > 0
      atom.clipboard.write($header.text())

  create: ->
    $li = @getSelected()
    if $li.length > 0
      model = $li.data('item')
      @emitter.emit('did-item-edit', ['create',model])

  alter: ->
    $li = @getSelected()
    if $li.length > 0
      model = $li.data('item')
      @emitter.emit('did-item-edit', ['alter',model])

  drop: ->
    $li = @getSelected()
    if $li.length > 0
      model = $li.data('item')
      @emitter.emit('did-item-edit', ['drop',model])

  selectConnection: (connection)->
    return unless connection != @selectedConnection
    @list.children().each (i,li) =>
      if $(li).data('item') == connection
        @list.children().removeClass('default')
        $(li).addClass('default')
        @selectedConnection = connection
        @emitter.emit('did-connection-selected', connection)

  #events
  onItemEdit: (callback)->
    @emitter.on('did-item-edit', callback)

  onConnectionSelected: (callback)->
    @emitter.on('did-connection-selected', callback)

  onConnectionDeleted: (callback)->
    @emitter.on('did-connection-deleted', callback)
