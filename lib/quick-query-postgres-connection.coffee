pg = require 'pg'

{Emitter} = require 'atom'

# don't parse dates and times.
pg.types.setTypeParser  1082 , (x) -> x
pg.types.setTypeParser  1183 , (x) -> x
pg.types.setTypeParser  1114 , (x) -> x
pg.types.setTypeParser  1184 , (x) -> x

class QuickQueryPostgresColumn
  type: 'column'
  child_type: null
  constructor: (@table,row) ->
    @connection = @table.connection
    @name = row['column_name']
    @primary_key = row['constraint_type'] == 'PRIMARY KEY'
    if row['character_maximum_length']
      @datatype = "#{row['data_type']} (#{row['character_maximum_length']})"
    else
      @datatype = row['data_type']
    @default = row['column_default']
    if @default == 'NULL' || @default == "NULL::#{row['data_type']}"
      @default = null
    if @default != null
      m =  @default.match(/'(.*?)'::/)
      if m && m[1] then @default = m[1]
    @nullable = row['is_nullable'] == 'YES'
  toString: ->
    @name
  parent: ->
    @table
  children: (callback)->
    callback([])

class QuickQueryPostgresTable
  type: 'table'
  child_type: 'column'
  constructor: (@schema,row,fields) ->
    @connection = @schema.connection
    @name = row["table_name"]
  toString: ->
    @name
  parent: ->
    @schema
  children: (callback)->
    @connection.getColumns(@,callback)

class QuickQueryPostgresSchema
  type: 'schema'
  child_type: 'table'
  constructor: (@database,row,fields) ->
    @connection = @database.connection
    @name = row["schema_name"]
  toString: ->
    @name
  parent: ->
    @database
  children: (callback)->
    @connection.getTables(@,callback)

class QuickQueryPostgresDatabase
  type: 'database'
  child_type: 'schema'
  constructor: (@connection,row) ->
    @name = row["datname"]
  toString: ->
    @name
  parent: ->
    @connection
  children: (callback)->
    @connection.getSchemas(@,callback)
    #@connection.getTables(@,callback)

module.exports =
class QuickQueryPostgresConnection

  fatal: false
  connection: null
  protocol: 'postgres'
  type: 'connection'
  child_type: 'database'
  defaulPort: 5432
  timeout: 5000 #time ot is set in 5s. queries should be fast.
  n_types: 'bigint bigserial bit boolean box bytea circle integer interval json line lseg money numeric path point polygon real smallint smallserial timestamp tsquery tsvector uuid xml'.split(/\s+/).concat(['bit varying'])
  s_types: ['character','character varying','date','inet','cidr','time','macaddr','text']

  constructor: (@info)->
    @emitter = new Emitter()
    @info.database = 'postgres'
    # @info.database = 'IBDT'
    @connections = {}

  connect: (callback)->
    @defaultConnection = new pg.Client(@info);
    @defaultConnection.connect (err)=>
      @connections[@info.database] = @defaultConnection
      callback(err)

  serialize: ->
    c = @defaultConnection
    host: c.host,
    port: c.port,
    user: c.user,
    protocol: @protocol
    password: c.password

  getDatabaseConnection: (database,callback) ->
    if(@connections[database])
      callback(@connections[database]) if callback
    else
      @info.database = database
      newConnection = new pg.Client(@info)
      newConnection.connect (err)=>
        if err
          console.log(err)
        else
          @connections[database] = newConnection
          callback(newConnection) if callback


  setDefaultDatabase: (database)->
    @getDatabaseConnection database, (connection) =>
      @defaultConnection = connection
      @emitter.emit 'did-change-default-database', connection.database

  getDefaultDatabase: ->
    @defaultConnection.database

  dispose: ->
    for connection in @connections
      connection.end()

  queryDatabaseConnection: (text,connection,callback, recursive = false) ->
    connection.query { text: text , rowMode: 'array'} , (err, result) =>
      if(err)
        if err.code == '0A000' && err.message.indexOf('cross-database') != -1 && !recursive
            database = err.message.match(/"(.*?)"/)[1].split('.')[0]
            @getDatabaseConnection database , (connection1) =>
              @queryDatabaseConnection(text,connection1,callback,true) #Recursive call!
        else
          callback({ type: 'error', content: err.message})
      else if result.command != 'SELECT'
        if isNaN(result.rowCount)
          callback type: 'success', content: "Success"
        else
          callback  type: 'success', content: "#{result.rowCount} row(s) affected"
      else
        rows = []
        for r in result.rows
          row = {}
          for field,i in result.fields
            row[field.name] = r[i]
          rows.push row
        callback(null,rows,result.fields)

  query: (text,callback) ->
    @queryDatabaseConnection(text,@defaultConnection,callback)

  getDatabases: (callback) ->
    text = "SELECT datname FROM pg_database "+
    "WHERE datistemplate = false"
    @query text , (err, rows, fields) =>
      if !err
        databases = rows.map (row) =>
           new QuickQueryPostgresDatabase(@,row)
        databases = databases.filter (database) => !@hiddenDatabase(database.name)
      callback(databases,err)


  getSchemas: (database, callback)->
    @getDatabaseConnection database.name, (connection) =>
      text = "SELECT schema_name FROM information_schema.schemata "+
      "WHERE catalog_name = '#{database.name}' "+
      "AND schema_name NOT IN ('pg_toast','pg_temp_1','pg_toast_temp_1','pg_catalog','information_schema')"
      @queryDatabaseConnection text, connection , (err, rows, fields) =>
        if !err
          schemas = rows.map (row) ->
            new QuickQueryPostgresSchema(database,row)
          callback(schemas)


  getTables: (schema,callback) ->
    @getDatabaseConnection schema.database.name, (connection) =>
      text = "SELECT table_name "+
      "FROM information_schema.tables "+
      "WHERE table_catalog = '#{schema.database.name}' "+
      "AND table_schema = '#{schema.name}'"
      @queryDatabaseConnection text, connection , (err, rows, fields) =>
        if !err
          tables = rows.map (row) ->
            new QuickQueryPostgresTable(schema,row)
          callback(tables)

  getColumns: (table,callback) ->
    @getDatabaseConnection table.schema.database.name, (connection)=>
      text = "SELECT tc.constraint_type ,c.* "+
      "FROM information_schema.columns c "+
      "LEFT OUTER JOIN information_schema.key_column_usage kc "+
      "ON kc.column_name = c.column_name "+
      "AND kc.table_name = c.table_name "+
      "AND kc.table_schema = c.table_schema "+
      "LEFT OUTER JOIN information_schema.table_constraints tc "+
      "ON kc.table_name = tc.table_name "+
      "AND kc.table_schema = tc.table_schema "+
      "AND tc.constraint_type = 'PRIMARY KEY' "+
      "WHERE c.table_name = '#{table.name}' "+
      "AND c.table_schema = '#{table.schema.name}' "+
      "AND c.table_catalog = '#{table.schema.database.name}'"
      @queryDatabaseConnection text, connection , (err, rows, fields) =>
        if !err
          columns = rows.map (row) =>
            new QuickQueryPostgresColumn(table,row)
          callback(columns)

  hiddenDatabase: (database) ->
    database == "postgres"

  simpleSelect: (table, columns = '*') ->
    if columns != '*'
      columns = columns.map (col) =>
        @defaultConnection.escapeIdentifier(col.name)
      columns = "\n "+columns.join(",\n ") + "\n"
    table_name = @defaultConnection.escapeIdentifier(table.name)
    schema_name = @defaultConnection.escapeIdentifier(table.schema.name)
    database_name = @defaultConnection.escapeIdentifier(table.schema.database.name)
    "SELECT #{columns} FROM #{database_name}.#{schema_name}.#{table_name} LIMIT 1000"


  createDatabase: (model,info)->
    database = @defaultConnection.escapeIdentifier(info.name)
    "CREATE DATABASE #{database};"

  createSchema: (model,info)->
    schema = @defaultConnection.escapeIdentifier(info.name)
    @setDefaultDatabase(model.name)
    "CREATE SCHEMA #{schema};"

  createTable: (model,info)->
    database = @defaultConnection.escapeIdentifier(model.database.name)
    schema = @defaultConnection.escapeIdentifier(model.name)
    table = @defaultConnection.escapeIdentifier(info.name)
    "CREATE TABLE #{database}.#{schema}.#{table} ( \n"+
    " \"id\" INT NOT NULL ,\n"+
    " CONSTRAINT \"#{info.name}_pk\" PRIMARY KEY (\"id\") );"

  createColumn: (model,info)->
    database = @defaultConnection.escapeIdentifier(model.schema.database.name)
    schema = @defaultConnection.escapeIdentifier(model.schema.name)
    table = @defaultConnection.escapeIdentifier(model.name)
    column = @defaultConnection.escapeIdentifier(info.name)
    nullable = if info.nullable then 'NULL' else 'NOT NULL'
    dafaultValue = if info.default == null then 'NULL' else @escape(info.default,info.datatype)
    "ALTER TABLE #{database}.#{schema}.#{table} ADD COLUMN #{column}"+
    " #{info.datatype} #{nullable} DEFAULT #{dafaultValue};"


  alterTable: (model,delta)->
    database = @defaultConnection.escapeIdentifier(model.schema.database.name)
    schema = @defaultConnection.escapeIdentifier(model.schema.name)
    newName = @defaultConnection.escapeIdentifier(delta.new_name)
    oldName = @defaultConnection.escapeIdentifier(delta.old_name)
    query = "ALTER TABLE #{database}.#{schema}.#{oldName} RENAME TO #{newName};"

  alterColumn: (model,delta)->
    database = @defaultConnection.escapeIdentifier(model.table.schema.database.name)
    schema = @defaultConnection.escapeIdentifier(model.table.schema.name)
    table = @defaultConnection.escapeIdentifier(model.table.name)
    newName = @defaultConnection.escapeIdentifier(delta.new_name)
    oldName = @defaultConnection.escapeIdentifier(delta.old_name)
    nullable = if delta.nullable then 'DROP NOT NULL' else 'SET NOT NULL'
    defaultValue = if delta.default == null then 'NULL' else @escape(delta.default,delta.datatype)
    result = "ALTER TABLE #{database}.#{schema}.#{table}"+
    "\nALTER COLUMN #{oldName} SET DATA TYPE #{delta.datatype},"+
    "\nALTER COLUMN #{oldName} #{nullable},"+
    "\nALTER COLUMN #{oldName} SET DEFAULT #{defaultValue}"
    if oldName != newName
      result += "\nALTER TABLE #{database}.#{schema}.#{table}"+
      " RENAME COLUMN #{oldName} TO #{newName};"
    result

  dropDatabase: (model)->
    database = @defaultConnection.escapeIdentifier(model.name)
    "DROP DATABASE #{database};"

  dropSchema: (model)->
    schema = @defaultConnection.escapeIdentifier(model.name)
    @setDefaultDatabase(model.database.name)
    "DROP SCHEMA #{schema};"

  dropTable: (model)->
    database = @defaultConnection.escapeIdentifier(model.schema.database.name)
    schema = @defaultConnection.escapeIdentifier(model.schema.name)
    table = @defaultConnection.escapeIdentifier(model.name)
    "DROP TABLE #{database}.#{schema}.#{table};"

  dropColumn: (model)->
    database = @defaultConnection.escapeIdentifier(model.table.schema.database.name)
    schema = @defaultConnection.escapeIdentifier(model.table.schema.name)
    table = @defaultConnection.escapeIdentifier(model.table.name)
    column = @defaultConnection.escapeIdentifier(model.name)
    "ALTER TABLE #{database}.#{schema}.#{table} DROP COLUMN #{column};"

  onDidChangeDefaultDatabase: (callback)->
    @emitter.on 'did-change-default-database', callback

  getDataTypes: ->
    @n_types.concat(@s_types)

  toString: ->
    @protocol+"://"+@defaultConnection.user+"@"+@defaultConnection.host

  escape: (value,type)->
    for t1 in @s_types
      if type.search(new RegExp(t1, "i")) == -1
        return @defaultConnection.escapeLiteral(value)
    str
