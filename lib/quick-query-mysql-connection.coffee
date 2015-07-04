mysql = require 'mysql'

{Emitter} = require 'atom'

class QuickQueryMysqlColumn
  type: 'column'
  child_type: null
  constructor: (@table,row) ->
    @connection = @table.connection
    @name = row['Field']
    @column = @name # TODO remove
    @primary_key = row["Key"] == "PRI"
    @datatype = row['Type']
    @default = row['Default']
    @nullable = row['Null'] == 'YES'
  toString: ->
    @name
  parent: ->
    @table
  children: (callback)->
    callback([])

class QuickQueryMysqlTable
  type: 'table'
  child_type: 'column'
  constructor: (@database,row,fields) ->
    @connection = @database.connection
    @name = row[fields[0].name]
    @table = @name # TODO remove
  toString: ->
    @name
  parent: ->
    @database
  children: (callback)->
    @connection.getColumns(@,callback)
class QuickQueryMysqlDatabase
  type: 'database'
  child_type: 'table'
  constructor: (@connection,row) ->
    @name = row["Database"]
    @database = @name # TODO remove
  toString: ->
    @name
  parent: ->
    @connection
  children: (callback)->
    @connection.getTables(@,callback)

module.exports =
class QuickQueryMysqlConnection

  fatal: false
  connection: null
  protocol: 'mysql'
  type: 'connection'
  child_type: 'database'
  defaulPort: 3306
  timeout: 5000 #time ot is set in 5s. queries should be fast.

  n_types: 'TINYINT SMALLINT MEDIUMINT INT INTEGER BIGINT FLOAT DOUBLE REAL DECIMAL NUMERIC TIMESTAMP YEAR ENUM SET'.split /\s+/
  s_types: 'CHAR VARCHAR TINYBLOB TINYTEXT MEDIUMBLOB MEDIUMTEXT LONGBLOB LONGTEXT BLOB TEXT DATETIME DATE TIME'.split /\s+/

  constructor: (@info)->
    @info.dateStrings = true
    @emitter = new Emitter()

  connect: (callback)->
    @connection = mysql.createConnection(@info)
    @connection.on 'error', (err) =>
      if err && err.code == 'PROTOCOL_CONNECTION_LOST'
        @fatal = true
    @connection.connect(callback)

  serialize: ->
    c = @connection.config
    host: c.host,
    port: c.port,
    protocol: @protocol
    user: c.user,
    password: c.password

  dispose: ->
    @close()

  close: ->
    @connection.end()

  query: (text,callback) ->
    if @fatal
      @connection = mysql.createConnection(@info)
      @connection.on 'error', (err) =>
        if err && err.code == 'PROTOCOL_CONNECTION_LOST'
          @fatal = true
      @fatal = false
    @connection.query {sql: text , timeout: @timeout }, (err, rows, fields)=>
      message = null
      if (err)
        message = { type: 'error' , content: err }
        @fatal = err.fatal
      else if !fields
        message = { type: 'success', content:  rows.affectedRows+" row(s) affected" }
      callback(message,rows,fields)

  setDefaultDatabase: (database)->
    @connection.changeUser database: database, =>
      @emitter.emit 'did-change-default-database', @connection.config.database

  getDefaultDatabase: ->
    @connection.config.database

  parent: -> @

  children: (callback)->
    @getDatabases (databases,err)->
      unless err? then callback(databases) else console.log err

  getDatabases: (callback) ->
    text = "SHOW DATABASES"
    @query text , (err, rows, fields) =>
      if !err
        databases = rows.map (row) =>
          new QuickQueryMysqlDatabase(@,row)
        databases = databases.filter (database) => !@hiddenDatabase(database.name)
      callback(databases,err)

  getTables: (database,callback) ->
    database_name = @connection.escapeId(database.name)
    text = "SHOW TABLES IN #{database_name}"
    @query text , (err, rows, fields) =>
      if !err
        tables = rows.map (row) =>
          new QuickQueryMysqlTable(database,row,fields)
        callback(tables)

  getColumns: (table,callback) ->
    table_name = @connection.escapeId(table.name)
    database_name = @connection.escapeId(table.database.name)
    text = "SHOW COLUMNS IN #{table_name} IN #{database_name}"
    @query text , (err, rows, fields) =>
      if !err
        columns = rows.map (row) =>
          new QuickQueryMysqlColumn(table,row)
        callback(columns)

  hiddenDatabase: (database) ->
    database == "information_schema" ||
    database == "performance_schema" ||
    database == "mysql"

  simpleSelect: (table, columns = '*') ->
    if columns != '*'
      columns = columns.map (col) =>
        @connection.escapeId(col.name)
      columns = "\n "+columns.join(",\n ") + "\n"
    table_name = @connection.escapeId(table.name)
    database_name = @connection.escapeId(table.database.name)
    "SELECT #{columns} FROM #{database_name}.#{table_name} LIMIT 1000"


  createDatabase: (model,info)->
    database = @connection.escapeId(info.name)
    "CREATE SCHEMA #{database};"

  createTable: (model,info)->
    database = @connection.escapeId(model.name)
    table = @connection.escapeId(info.name)
    "CREATE TABLE #{database}.#{table} ( \n"+
    " `id` INT NOT NULL ,\n"+
    " PRIMARY KEY (`id`) );"

  createColumn: (model,info)->
    database = @connection.escapeId(model.database.name)
    table = @connection.escapeId(model.name)
    column = @connection.escapeId(info.name)
    nullable = if info.nullable then 'NULL' else 'NOT NULL'
    dafaultValue = @escape(info.default,info.datatype) || 'NULL'
    "ALTER TABLE #{database}.#{table} ADD COLUMN #{column}"+
    " #{info.datatype} #{nullable} DEFAULT #{dafaultValue};"


  alterTable: (model,delta)->
    database = @connection.escapeId(model.database.name)
    newName = @connection.escapeId(delta.new_name)
    oldName = @connection.escapeId(delta.old_name)
    query = "ALTER TABLE #{database}.#{oldName} RENAME TO #{database}.#{newName};"

  alterColumn: (model,delta)->
    database = @connection.escapeId(model.table.database.name)
    table = @connection.escapeId(model.table.name)
    newName = @connection.escapeId(delta.new_name)
    oldName = @connection.escapeId(delta.old_name)
    nullable = if delta.nullable then 'NULL' else 'NOT NULL'
    dafaultValue = @escape(delta.default,delta.datatype) || 'NULL'
    "ALTER TABLE #{database}.#{table} CHANGE COLUMN #{oldName} #{newName}"+
    " #{delta.datatype} #{nullable} DEFAULT #{dafaultValue};"

  dropDatabase: (model)->
    database = @connection.escapeId(model.name)
    "DROP SCHEMA #{database};"

  dropTable: (model)->
    database = @connection.escapeId(model.database.name)
    table = @connection.escapeId(model.name)
    "DROP TABLE #{database}.#{table};"

  dropColumn: (model)->
    database = @connection.escapeId(model.table.database.name)
    table = @connection.escapeId(model.table.name)
    column = @connection.escapeId(model.name)
    "ALTER TABLE #{database}.#{table} DROP COLUMN #{column};"


  updateRecord: (row,fields,values)->
    tables = @_tableGroup(fields)
    for name,table of tables
      @getColumns table, (columns)=>
        keys = (key for key in columns when key.primary_key)
        allkeys = true
        allkeys &= row[key.name]? for key in keys
        if allkeys && keys.length > 0
          assings = fields.map (field) =>
            column = (column for column in columns when column.name == field.orgName)[0]
            "#{@connection.escapeId(field.orgName)} = #{@escape(values[field.name],column.datatype)}"
          database = @connection.escapeId(table.database.name)
          table = @connection.escapeId(table.name)
          where = keys.map (key)=> "#{@connection.escapeId(key.name)} = #{@escape(row[key.name],key.datatype)}"
          update = "UPDATE #{database}.#{table}"+
          " SET #{assings.join(',')}"+
          " WHERE "+where.join(' AND ')+";"
          @emitter.emit 'sentence-ready', update

  insertRecord: (fields,values)->
    tables = @_tableGroup(fields)
    for name,table of tables
      @getColumns table, (columns)=>
        aryfields = table.fields.map (field) =>
          @connection.escapeId(field.orgName)
        strfields = aryfields.join(',')
        aryvalues = table.fields.map (field) =>
          column = (column for column in columns when column.name == field.orgName)[0]
          @escape(values[field.name],column.datatype)
        strvalues = aryvalues.join(',')
        database = @connection.escapeId(table.database.name)
        table = @connection.escapeId(table.name)
        insert = "INSERT INTO #{database}.#{table}"+
        " (#{strfields}) VALUES (#{strvalues});"
        @emitter.emit 'sentence-ready', insert

  deleteRecord: (row,fields)->
    tables = @_tableGroup(fields)
    for name,table of tables
      @getColumns table, (columns)=>
        keys = (key for key in columns when key.primary_key)
        allkeys = true
        allkeys &= row[key.name]? for key in keys
        if allkeys && keys.length > 0
          database = @connection.escapeId(table.database.name)
          table = @connection.escapeId(table.name)
          where = keys.map (key)=> "#{@connection.escapeId(key.name)} = #{@escape(row[key.name],key.datatype)}"
          del = "DELETE FROM #{database}.#{table}"+
          " WHERE "+where.join(' AND ')+";"
          @emitter.emit 'sentence-ready', del

  _tableGroup: (fields)->
    tables = {}
    for field in fields
      if field.orgTable?
        tables[field.orgTable] ?=
          name: field.orgTable
          database: {name: field.db}
          fields: []
        tables[field.orgTable].fields.push(field)
    tables

  sentenceReady: (callback)->
    @emitter.on 'sentence-ready', callback

  onDidChangeDefaultDatabase: (callback)->
    @emitter.on 'did-change-default-database', callback

  getDataTypes: ->
    @n_types.concat(@s_types)

  toString: ->
    @protocol+"://"+@connection.config.user+"@"+@connection.config.host

  escape: (value,type)->
    for t1 in @s_types
      if value == null || type.search(new RegExp(t1, "i")) != -1
        return @connection.escape(value)
    value.toString()
