{ScrollView, $} = require 'atom-space-pen-views'

module.exports =
class QuickQueryBrowserView extends ScrollView

  editor: null
  connection: null
  connections: []
  selectedConnection: null

  constructor: ->
    super

  initialize: ->
    if !atom.config.get('quick-query.browserButtons')
      @addClass('no-buttons')
    atom.config.onDidChange 'quick-query.browserButtons', ({newValue, oldValue}) =>
      @toggleClass('no-buttons',!newValue)
    @find('#quick-query-new-connection').click (e) =>
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'quick-query:new-connection')
    @find('#quick-query-run').click (e) =>
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'quick-query:run')

  # Returns an object that can be retrieved when package is activated
  getTitle: -> 'Databases'

  serialize: ->

  @content: ->
    @div class: 'quick-query-browser tool-panel', =>
      @div class: 'btn-group', outlet: 'buttons', =>
        @button id: 'quick-query-run', class: 'btn icon icon-playback-play' , title: 'Run' , style: 'width:50%'
        @button id: 'quick-query-new-connection', class: 'btn icon icon-plus' , title: 'New connection' , style: 'width:50%'
      @ol id:'quick-query-connections' , class: 'list-tree has-collapsable-children focusable-panel', tabindex: -1, outlet: 'list'


  # Tear down any state and detach
  destroy: ->
    @element.remove()

  delete: ->
    connection = null
    $li = @find('ol:focus li.selected')
    model = $li.data('item')
    if $li.hasClass('quick-query-connection')
      @removeConnection(model)
    else
      @trigger('quickQuery.edit',['drop',model])

  removeConnection: (connection)->
    i = @connections.indexOf(connection)
    @connections.splice(i,1)
    @showConnections()
    @trigger('quickQuery.connectionDeleted',[connection])

  getURI: -> 'quick-query://browser'
  getDefaultLocation: ->
    if atom.config.get('quick-query.showBrowserOnLeftSide')
      'left'
    else
      'right'
  getAllowedLocations: -> ['left', 'right']
  isPermanentDockItem: -> true

  setDefault: ->
    $li = @find('li.selected')
    unless $li.hasClass('default')
      model = $li.data('item')
      model.connection.setDefaultDatabase model.name

  moveUp: ->
    $li = @find('li.selected')
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
    $i = $li = @find('li.selected')
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
      @trigger('quickQuery.connectionSelected',[connection])
      @showConnections()
      connection.onDidChangeDefaultDatabase (database) =>
        @defaultDatabaseChanged(connection,database)

  defaultDatabaseChanged: (connection,database)->
    @list.children().each (i,e)->
      if $(e).data('item') == connection
        $(e).find(".quick-query-database").removeClass('default')
        $(e).find(".quick-query-database[data-name=\"#{database}\"]").addClass('default')

  newItem: (item)->
    li = document.createElement 'li'
    li.classList.add('entry')
    li.setAttribute('data-name',item.name)
    div = document.createElement 'div'
    div.classList.add('header','list-item')
    li.appendChild div
    icon = document.createElement 'span'
    icon.classList.add('icon')
    div.textContent = item.toString()
    div.insertBefore icon, div.firstChild
    @setItemClasses(item,li,div,icon)
    return $(li)

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
      @trigger('quickQuery.connectionSelected',[connection])
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

  setItemClasses: (item,li,div,icon)->
    switch item.type
      when 'connection'
        li.classList.add('quick-query-connection')
        div.classList.add("qq-connection-item")
        icon.classList.add('icon-plug')
      when 'database'
        li.classList.add('quick-query-database')
        div.classList.add("qq-database-item")
        icon.classList.add('icon-database')
        if item.name == @selectedConnection.getDefaultDatabase()
          li.classList.add('default')
      when 'schema'
        li.classList.add('quick-query-schema')
        div.classList.add("qq-schema-item")
        icon.classList.add('icon-book')
      when 'table'
        li.classList.add('quick-query-table')
        div.classList.add("qq-table-item")
        icon.classList.add('icon-browser')
      when 'column'
        li.classList.add('quick-query-column')
        div.classList.add("qq-column-item")
        if item.primary_key
          icon.classList.add('icon-key')
        else
          icon.classList.add('icon-tag')
    if item.type != 'column'
      li.classList.add('list-nested-item','collapsed')

  timeout: (t,bk) -> setTimeout(bk,t)

  expandSelected: (callback)->
    $li = @find('li.selected')
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
        if time2 - time1 < 5000
          $li.removeClass('busy')
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
    $li = @find(selector).filter (i,e)-> $(e).data('item') == model
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
      if bottom > @list.scrollBottom()
        @list.scrollBottom(bottom)
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
    $li = @find('li.selected.quick-query-table')
    if $li.length > 0
      model = $li.data('item')
      model.connection.getColumns model ,(columns) =>
        text = model.connection.simpleSelect(model,columns)
        atom.workspace.open().then (editor) =>
          atom.textEditors.setGrammarOverride(editor, 'source.sql')
          editor.insertText(text)

  copy: ->
    $li = @find('li.selected')
    $header = $li.children('div.header')
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

  selectConnection: (connection)->
    return unless connection != @selectedConnection
    @list.children().each (i,li) =>
      if $(li).data('item') == connection
        @list.children().removeClass('default')
        $(li).addClass('default')
        @selectedConnection = connection
        @trigger('quickQuery.connectionSelected',[connection])

  #events
  onConnectionSelected: (callback)->
    @bind 'quickQuery.connectionSelected', (e,connection) =>
      callback(connection)

  onConnectionDeleted: (callback)->
    @bind 'quickQuery.connectionDeleted', (e,connection) =>
      callback(connection)
