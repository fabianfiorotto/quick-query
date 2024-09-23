mysql = require 'mysql2'

{Emitter} = require 'atom'

class MysqlColumn
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

class MysqlTable
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
class MysqlDatabase
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
class MysqlConnection

  fatal: false
  connection: null
  protocol: 'mysql'
  type: 'connection'
  child_type: 'database'
  timeout: 40000

  n_types: 'TINYINT SMALLINT MEDIUMINT INT INTEGER BIGINT FLOAT DOUBLE REAL DECIMAL NUMERIC TIMESTAMP YEAR ENUM SET'.split /\s+/
  s_types: 'CHAR VARCHAR TINYBLOB TINYTEXT MEDIUMBLOB MEDIUMTEXT LONGBLOB LONGTEXT BLOB TEXT DATETIME DATE TIME'.split /\s+/

  allowEdition: true
  @sshSupport: true
  @defaultPort: 3306

  constructor: (@info)->
    @info.dateStrings = true
    @info.multipleStatements = true
    @emitter = new Emitter()

  connect: (callback)->
    @connection = mysql.createConnection(@info)
    @connection.on 'error', (err) =>
      if err && err.code == 'PROTOCOL_CONNECTION_LOST'
        @fatal = true
      callback(err.message) if err?
    @connection.connect(callback)

  serialize: ->
    c = @connection.config
    host: c.host,
    port: c.port,
    protocol: @protocol
    database: c.database,
    user: c.user,
    password: c.password
    ssh: if @info.ssh? then @info.ssh else null

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
    @connection.query {sql: text ,rowsAsArray: true,  timeout: @timeout }, (err, rows, fields)=>
      if (err)
        @fatal = err.fatal
        callback  type: 'error' , content: err.toString()
      else if !fields
        callback type: 'success', content:  rows.affectedRows+" row(s) affected"
      else if fields.length == 0 || (!Array.isArray(fields[0]) && fields[0]?)
        callback(null,rows,fields)
      else #-- Multiple Statements
        affectedRows = rows.map (row)->
          if row.affectedRows? then row.affectedRows else 0
        affectedRows = affectedRows.reduce (r1,r2)-> r1+r2
        if fields[0]? && affectedRows == 0
          callback(null,rows[0],fields[0])
        else
          callback type: 'success', content:  affectedRows+" row(s) affected"

  objRowsMap: (rows,fields,callback)->
    rows.map (r,i) =>
      row = {}
      row[field.name] = r[j] for field,j in fields
      if callback? then callback(row) else row

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
        databases = @objRowsMap rows,fields, (row) =>
          new MysqlDatabase(@,row)
        databases = databases.filter (database) => !@hiddenDatabase(database.name)
      callback(databases,err)

  getTables: (database,callback) ->
    database_name = @connection.escapeId(database.name)
    text = "SHOW TABLES IN #{database_name}"
    @query text , (err, rows, fields) =>
      if !err
        tables = @objRowsMap rows,fields, (row) =>
          new MysqlTable(database,row,fields)
        callback(tables)

  getColumns: (table,callback) ->
    table_name = @connection.escapeId(table.name)
    database_name = @connection.escapeId(table.database.name)
    text = "SHOW COLUMNS IN #{table_name} IN #{database_name}"
    @query text , (err, rows, fields) =>
      if !err
        columns = @objRowsMap rows,fields, (row) =>
          new MysqlColumn(table,row)
        callback(columns)

  hiddenDatabase: (database) ->
    database == "information_schema" ||
    database == "performance_schema" ||
    database == "sys" ||
    database == "mysql"

  simpleSelect: (table, columns = '*') ->
    if columns != '*'
      columns = columns.map (col) =>
        @connection.escapeId(col.name)
      columns = "\n "+columns.join(",\n ") + "\n"
    table_name = @connection.escapeId(table.name)
    database_name = @connection.escapeId(table.database.name)
    "SELECT #{columns} FROM #{database_name}.#{table_name} LIMIT 1000;"


  createDatabase: (model,info)->
    database = @connection.escapeId(info.name)
    "CREATE SCHEMA #{database};"

  createTable: (model,info)->
    database = @connection.escapeId(model.name)
    table = @connection.escapeId(info.name)
    """
    CREATE TABLE #{database}.#{table} (
       `id` INT NOT NULL ,
       PRIMARY KEY (`id`)
     );
    """

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

  updateRecord: (changes)->
    tables = @_tableGroup(changes)
    Promise.all(
      @_updateRecordByTable(changes,table) for name,table of tables
    ).then (updates) -> (new Promise (resolve, reject) -> resolve(updates.join("\n")))

  _updateRecordByTable: (changes,table)->
    new Promise (resolve, reject) =>
      @getColumns table, (columns)=>
        @_matchColumns(changes,columns)
        keys = @_allKeys(table.changes,columns)
        if keys?
          update_changes = table.changes.filter (change)->
            change.column? && typeof change.newValue isnt 'undefined'
          return resolve('') if update_changes.length == 0
          assings = update_changes.map (change, i) =>
            "#{@connection.escapeId(change.field.orgName)} = #{@escape(change.newValue,change.column.datatype)}"
          database = @connection.escapeId(table.database.name)
          tableName = @connection.escapeId(table.name)
          where = keys.map (k)=>
            "#{@connection.escapeId(k.column.name)} = #{@escape(k.value,k.column.datatype)}"
          update = "UPDATE #{database}.#{tableName}"+
          " SET #{assings.join(',')}"+
          " WHERE "+where.join(' AND ')+";"
          resolve(update)
        else
          resolve('')

  insertRecord: (changes)->
    tables = @_tableGroup(changes)
    Promise.all(
      @_insertRecordByTable(changes,table) for name,table of tables
    ).then (inserts) -> (new Promise (resolve, reject) -> resolve(inserts.join("\n")))

  _insertRecordByTable: (changes,table)->
    new Promise (resolve, reject) =>
      @getColumns table, (columns)=>
        @_matchColumns(changes,columns)
        insert_changes = table.changes.filter (change)->
          change.column? && typeof change.value isnt 'undefined'
        return resolve('') if insert_changes.length == 0
        aryfields = insert_changes.map (change) =>
          @connection.escapeId(change.field.orgName)
        strfields = aryfields.join(',')
        aryvalues = insert_changes.map (change) =>
          @escape(change.value,change.column.datatype)
        strvalues = aryvalues.join(',')
        database = @connection.escapeId(table.database.name)
        tableName = @connection.escapeId(table.name)
        insert = "INSERT INTO #{database}.#{tableName}"+
        " (#{strfields}) VALUES (#{strvalues});"
        resolve(insert)

  deleteRecord: (changes)->
    tables = @_tableGroup(changes)
    Promise.all(
      @_deleteRecordByTable(changes, table) for name,table of tables
    ).then (deletes) -> (new Promise (resolve, reject) -> resolve(deletes.join("\n")))

  _deleteRecordByTable: (changes,table)->
    new Promise (resolve, reject) =>
      @getColumns table, (columns)=>
        @_matchColumns(changes,columns)
        keys = @_allKeys(table.changes,columns)
        if keys?
          database = @connection.escapeId(table.database.name)
          tableName = @connection.escapeId(table.name)
          where = keys.map (k)=> "#{@connection.escapeId(k.column.name)} = #{@escape(k.value,k.column.datatype)}"
          del = "DELETE FROM #{database}.#{tableName}"+
          " WHERE "+where.join(' AND ')+";"
          resolve(del)
        else
          resolve('')

  _matchColumns: (changes,columns)->
    for change in changes
      for column in columns
        change.column = column if column.name == change.field.orgName && change.field.orgTable == column.table.name

  _tableGroup: (changes)->
    tables = {}
    for change in changes
      field = change.field
      if field.orgTable? and field.orgTable != ''
        tables[field.orgTable] ?=
          name: field.orgTable
          database: {name: field.db}
          changes: []
        tables[field.orgTable].changes.push(change)
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
    @protocol+"://"+@connection.config.user+"@"+@connection.config.host

  escape: (value,type)->
    for t1 in @s_types
      if value == null || type.search(new RegExp(t1, "i")) != -1
        return @connection.escape(value)
    value.toString()
