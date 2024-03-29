pg = require 'pg'

{Emitter} = require 'atom'

# don't parse dates, times and json.
pg.types.setTypeParser  1082 , (x) -> x
pg.types.setTypeParser  1183 , (x) -> x
pg.types.setTypeParser  1114 , (x) -> x
pg.types.setTypeParser  1184 , (x) -> x
pg.types.setTypeParser  3802 , (x) -> x
pg.types.setTypeParser  114  , (x) -> x

class PostgresColumn
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
    @id = parseInt(row['ordinal_position'])
  toString: ->
    @name
  parent: ->
    @table
  children: (callback)->
    callback([])

class PostgresTable
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

class PostgresSchema
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

class PostgresDatabase
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
class PostgresConnection

  fatal: false
  connection: null
  protocol: 'postgres'
  type: 'connection'
  child_type: 'database'
  timeout: 5000 #time ot is set in 5s. queries should be fast.
  n_types: 'bigint bigserial bit boolean box bytea circle integer interval line lseg money numeric path point polygon real smallint smallserial timestamp tsquery tsvector xml'.split(/\s+/).concat(['bit varying'])
  s_types: ['character','character varying','date','inet','cidr','time','macaddr','text','uuid','json','jsonb']

  allowEdition: true
  @defaultPort: 5432

  constructor: (@info)->
    @emitter = new Emitter()
    @info.database ?= 'postgres'
    @connections = {}

  connect: (callback)->
    @defaultConnection = new pg.Client(@info);
    @defaultConnection.connect (err)=>
      @connections[@info.database] = @defaultConnection
      @defaultConnection.on 'error', (err) =>
        console.log(err) #fatal error
        @connections[@info.database] = null
        @fatal = true
      callback(err)

  serialize: ->
    c = @defaultConnection
    host: c.host,
    port: c.port,
    ssl: c.ssl
    protocol: @protocol
    database: c.database
    user: c.user,
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
          newConnection.on 'error', (err) =>
            console.log(err) #fatal error
            @connections[database] = null
            if newConnection == @defaultConnection
              @fatal = true
          @connections[database] = newConnection
          callback(newConnection) if callback


  setDefaultDatabase: (database)->
    @getDatabaseConnection database, (connection) =>
      @defaultConnection = connection
      @emitter.emit 'did-change-default-database', connection.database

  getDefaultDatabase: ->
    @defaultConnection.database

  dispose: ->
    @close()

  close: ->
    for database,connection of @connections
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
        for field,i in result.fields
          field.db = connection.database
        callback(null,result.rows,result.fields)

  query: (text,callback) ->
    if @fatal
      @getDatabaseConnection @defaultConnection.database, (connection) =>
        @defaultConnection = connection
        @fatal = false
        @queryDatabaseConnection(text,@defaultConnection,callback)
    else
      @queryDatabaseConnection(text,@defaultConnection,callback)

  objRowsMap: (rows,fields,callback)->
    rows.map (r,i) =>
      row = {}
      row[field.name] = r[j] for field,j in fields
      if callback? then callback(row) else row

  parent: -> @

  children: (callback)->
    @getDatabases (databases,err)->
      unless err? then callback(databases) else console.log err

  getDatabases: (callback) ->
    text = "SELECT datname FROM pg_database
    WHERE datistemplate = false"
    @query text , (err, rows, fields) =>
      if !err
        databases = @objRowsMap rows,fields, (row) =>
           new PostgresDatabase(@,row)
        databases = databases.filter (database) => !@hiddenDatabase(database.name)
      callback(databases,err)


  getSchemas: (database, callback)->
    @getDatabaseConnection database.name, (connection) =>
      text = "SELECT schema_name FROM information_schema.schemata
      WHERE catalog_name = '#{database.name}'
      AND schema_name NOT IN ('pg_toast','pg_temp_1','pg_toast_temp_1','pg_catalog','information_schema')"
      @queryDatabaseConnection text, connection , (err, rows, fields) =>
        if !err
          schemas = @objRowsMap rows, fields , (row) ->
            new PostgresSchema(database,row)
          callback(schemas)


  getTables: (schema,callback) ->
    @getDatabaseConnection schema.database.name, (connection) =>
      text = "
        SELECT table_name
        FROM information_schema.tables
        WHERE table_catalog = '#{schema.database.name}'
        AND table_schema = '#{schema.name}'"
      @queryDatabaseConnection text, connection , (err, rows, fields) =>
        if !err
          tables = @objRowsMap rows,fields, (row) ->
            new PostgresTable(schema,row)
          callback(tables)

  getColumns: (table,callback) ->
    @getDatabaseConnection table.schema.database.name, (connection)=>
      text = "SELECT  pk.constraint_type ,c.*
       FROM information_schema.columns c
       LEFT OUTER JOIN (
        SELECT
         tc.constraint_type,
         kc.column_name,
         tc.table_catalog,
         tc.table_name,
         tc.table_schema
        FROM information_schema.table_constraints tc
        INNER JOIN information_schema.CONSTRAINT_COLUMN_USAGE kc
        ON kc.constraint_name = tc.constraint_name
        AND kc.table_catalog = tc.table_catalog
        AND kc.table_name = tc.table_name
        AND kc.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'PRIMARY KEY'
       ) pk ON pk.column_name = c.column_name
        AND pk.table_catalog = c.table_catalog
        AND pk.table_name = c.table_name
        AND pk.table_schema = c.table_schema
       WHERE c.table_name = '#{table.name}'
       AND c.table_schema = '#{table.schema.name}'
       AND c.table_catalog = '#{table.schema.database.name}'"
      @queryDatabaseConnection text, connection , (err, rows, fields) =>
        if !err
          columns = @objRowsMap rows, fields, (row) =>
            new PostgresColumn(table,row)
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
    "SELECT #{columns} FROM #{database_name}.#{schema_name}.#{table_name} LIMIT 1000;"


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
    """
      CREATE TABLE #{database}.#{schema}.#{table} (
        "id" INT NOT NULL ,
        CONSTRAINT "#{info.name}_pk" PRIMARY KEY ("id")
      );
    """

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
    result = """
      ALTER TABLE #{database}.#{schema}.#{table}
      ALTER COLUMN #{oldName} SET DATA TYPE #{delta.datatype},
      ALTER COLUMN #{oldName} #{nullable},
      ALTER COLUMN #{oldName} SET DEFAULT #{defaultValue}
    """
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

  updateRecord: (changes)->
    tables = @_tableGroup(changes)
    Promise.all(
      @_updateRecordByTable(changes, t) for oid,t of tables
    ).then (updates) -> (new Promise (resolve, reject) -> resolve(updates.join("\n")))

  _updateRecordByTable: (changes, t)->
    new Promise (resolve, reject) =>
      @getTableByOID t.database,t.oid, (table) =>
        table.children (columns) =>
          @_matchColumns(changes,columns,table.id)
          keys = @_allKeys(t.changes,columns)
          if keys?
            update_changes = t.changes.filter (change)->
              change.column? && typeof change.newValue isnt 'undefined'
            return resolve('') if update_changes.length == 0
            assings = update_changes.map (change) =>
              "#{@defaultConnection.escapeIdentifier(change.column.name)} = #{@escape(change.newValue,change.column.datatype)}"
            database = @defaultConnection.escapeIdentifier(table.schema.database.name)
            schema = @defaultConnection.escapeIdentifier(table.schema.name)
            tableName = @defaultConnection.escapeIdentifier(table.name)
            where = keys.map (k)=> "#{@defaultConnection.escapeIdentifier(k.column.name)} = #{@escape(k.value,k.column.datatype)}"
            update = "UPDATE #{database}.#{schema}.#{tableName}"+
            " SET #{assings.join(',')}"+
            " WHERE "+where.join(' AND ')+";"
            resolve(update)
          else
            resolve('')

  insertRecord: (changes)->
    tables = @_tableGroup(changes)
    Promise.all(
      @_insertRecordByTable(changes, t) for oid,t of tables
    ).then (inserts) -> (new Promise (resolve, reject) -> resolve(inserts.join("\n")))

  _insertRecordByTable: (changes, t)->
    new Promise (resolve, reject) =>
      @getTableByOID t.database,t.oid, (table) =>
        table.children (columns) =>
          @_matchColumns(changes,columns,table.id)
          insert_changes = t.changes.filter((change)-> change.column? && typeof change.value isnt 'undefined')
          return resolve('') if insert_changes.length == 0
          aryfields = insert_changes.map (change) =>
            @defaultConnection.escapeIdentifier(change.column.name)
          strfields = aryfields.join(',')
          aryvalues = insert_changes.map (change) =>
            @escape(change.value,change.column.datatype)
          strvalues = aryvalues.join(',')
          database = @defaultConnection.escapeIdentifier(table.schema.database.name)
          schema = @defaultConnection.escapeIdentifier(table.schema.name)
          tableName = @defaultConnection.escapeIdentifier(table.name)
          insert = "INSERT INTO #{database}.#{schema}.#{tableName}"+
          " (#{strfields}) VALUES (#{strvalues});"
          resolve(insert)

  deleteRecord: (changes)->
    tables = @_tableGroup(changes)
    Promise.all(
      @_deleteRecordByTable(changes, t) for oid,t of tables
    ).then (deletes) -> (new Promise (resolve, reject) -> resolve(deletes.join("\n")))

  _deleteRecordByTable: (changes, t)->
    new Promise (resolve, reject) =>
      @getTableByOID t.database,t.oid, (table) =>
        table.children (columns) =>
          @_matchColumns(changes,columns,table.id)
          keys = @_allKeys(t.changes,columns)
          if keys?
            database = @defaultConnection.escapeIdentifier(table.schema.database.name)
            schema = @defaultConnection.escapeIdentifier(table.schema.name)
            tableName = @defaultConnection.escapeIdentifier(table.name)
            where = keys.map (k)=> "#{@defaultConnection.escapeIdentifier(k.column.name)} = #{@escape(k.value,k.column.datatype)}"
            del = "DELETE FROM #{database}.#{schema}.#{tableName}"+
            " WHERE "+where.join(' AND ')+";"
            resolve(del)
          else
            resolve('')

  getTableByOID: (database,oid,callback)->
    @getDatabaseConnection database, (connection) =>
      text = "SELECT s.nspname AS schema_name,
       t.relname AS table_name
       FROM pg_class t
       INNER JOIN pg_namespace s ON t.relnamespace = s.oid
       WHERE t.oid = #{oid}"
      @queryDatabaseConnection text, connection , (err, rows, fields) =>
        db = {name: database, connection: @ }
        if !err && rows.length == 1
          row = @objRowsMap(rows,fields)[0]
          schema = new PostgresSchema(db,row,fields)
          table = new PostgresTable(schema,row)
          table.id = oid
          callback(table)

  _matchColumns: (changes,columns,oid)->
    for change in changes when change.field.tableID == oid
      for column in columns
        change.column = column if column.id == change.field.columnID

  _tableGroup: (changes)->
    tables = {}
    for change in changes
      field = change.field
      if field.tableID? && field.tableID != 0
        oid = field.tableID.toString()
        tables[oid] ?=
          oid: field.tableID
          database: field.db
          changes: []
        tables[oid].changes.push(change)
    tables

  _allKeys: (changes,columns)->
    key_columns = columns.filter (column)-> column.primary_key
    keys = changes.filter (change)->  change.column?.primary_key
    if keys.length > 0 && key_columns.length == keys.length then keys else null


  onDidChangeDefaultDatabase: (callback)->
    @emitter.on 'did-change-default-database', callback

  getDataTypes: ->
    @n_types.concat(@s_types)

  toString: ->
    @protocol+"://"+@defaultConnection.user+"@"+@defaultConnection.host

  escape: (value,type)->
    if value == null
      return 'NULL'
    for t1 in @s_types
      if type.search(new RegExp(t1, "i")) != -1
        return @defaultConnection.escapeLiteral(value)
    value.toString()
