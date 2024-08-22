{SelectListView  , $} = require './space-pen'
{Emitter} = require 'atom'

module.exports =
class TableFinderView extends SelectListView
  initialize: ->
    @step = 1
    @emitter = new Emitter()
    super
  getFilterKey: ->
    'name'
  viewForItem: (item) ->
     if item.parent().type == 'schema'
       $li = $("<li/>").html("#{item.parent().name}.#{item.name}")
     else
       $li = $("<li/>").html(item.name)
     $span = $('<span/>').addClass('icon')
     if item.type == 'database'
       $span.addClass('icon-database')
     else
       $span.addClass('icon-browser')
     $li.prepend($span)
     $li
  confirmed: (item) ->
    if @step == 1
      @step2(item)
    else
      @emitter.emit('found', item)

  cancel: ->
    super
    if @step == 2
      @step1()
    else
      @emitter.emit('canceled')

  searchTable: (@connection)->
    @step1()

  step1: ()->
    @step = 1
    @connection.getDatabases (databases,err) =>
      unless err
        @setItems(databases)
        if defaultdatabase = @connection.getDefaultDatabase()
          unless @connection.hiddenDatabase(defaultdatabase)
            @filterEditor.getModel().setText(defaultdatabase)

  step2: (database)->
    @step = 2
    if database.child_type == 'table'
      database.children (tables) =>
        @filterEditor.getModel().setText('')
        @setItems(tables)
    else
      database.children (schemas) =>
        alltables = []
        i = 0
        for schema in schemas
          schema.children (tables) =>
            i++
            Array.prototype.push.apply(alltables,tables)
            if i == schemas.length
              @filterEditorView.getModel().setText('')
              @setItems(alltables)

  destroy: ->
    super
    @emiter.dispose()

  onFound: (callback)->
    @emitter.on('found', callback)

  onCanceled: (callback)->
    @emitter.on('canceled', callback)
