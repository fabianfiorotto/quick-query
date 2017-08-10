
class QuickQueryCachedTable
  type: 'table'
  child_type: 'column'
  childs: []
  constructor: (@parent,@real) ->
    @connection = @parent.connection
    @name = @real.name
  toString: ->
    @name
  parent: ->
    @parent
  children: (callback)->
    time = Date.now()
    if !@last? || time - @last >  @connection.timeout * 1000
      @last = time
      @real.children (@childs)=>
        callback(@childs)
    else
      callback(@childs)

class QuickQueryCachedSchema
  type: 'schema'
  child_type: 'table'
  childs: []
  constructor: (@database,@real) ->
    @connection = @database.connection
    @name = @real.name
  toString: ->
    @name
  parent: ->
    @database
  children: (callback)->
    time = Date.now()
    if !@last? || time - @last >  @connection.timeout * 1000
      @last = time
      @real.children (childs)=>
        @childs = childs.map (child)=> new QuickQueryCachedTable(@,child)
        callback(@childs)
    else
      callback(@childs)

class QuickQueryCachedDatabase
  type: 'database'
  childs: []
  constructor: (@connection,@real) ->
    @name = @real.name
    @child_type = @real.child_type
  toString: ->
    @name
  parent: ->
    @connection
  children: (callback)->
    time = Date.now()
    if !@last? || time - @last >  @connection.timeout * 1000
      @last = time
      @real.children (childs)=>
        if @child_type == 'schema'
          @childs = childs.map (child)=> new QuickQueryCachedSchema(@,child)
        else
          @childs = childs.map (child)=> new QuickQueryCachedTable(@,child)
        callback(@childs)
    else
      callback(@childs)

module.exports = class QuickQueryCachedConnection

  type: 'connection'
  child_type: 'database'

  constructor: (info)->
    @realConnection = info.connection
    @protocol = @realConnection.protocol
    @timeout = info.timeout
    @timeout ?= 15 #seconds
    @last = null

  getDefaultDatabase: -> @realConnection.getDefaultDatabase()

  children: (callback)->
    time = Date.now()
    if !@last? || time - @last >  @timeout * 1000
      @last = time
      @realConnection.children (childs) =>
        @childs = childs.map (child)=> new QuickQueryCachedDatabase(@,child)
        callback(@childs)
    else
      callback(@childs)

  query: (str) -> @realConnection.query(str) #should I cache this?

  simpleSelect: (table,columns='*')->
    @realConnection.simpleSelect(table,columns)
