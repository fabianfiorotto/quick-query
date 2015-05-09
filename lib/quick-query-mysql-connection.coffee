mysql = require 'mysql'

module.exports =
class QuickQueryMysqlConnection

  fatal: false
  connection: null
  protocol: 'mysql'
  defaulPort: 3306
  timeout: 5000 #time ot is set in 5s. queries should be fast.

  n_types: 'TINYINT SMALLINT MEDIUMINT INT INTEGER BIGINT FLOAT DOUBLE REAL DECIMAL NUMERIC TIMESTAMP YEAR ENUM SET'.split /\s+/
  s_types: 'CHAR VARCHAR TINYBLOB TINYTEXT MEDIUMBLOB MEDIUMTEXT LONGBLOB LONGTEXT BLOB TEXT DATETIME DATE TIME'.split /\s+/

  constructor: (@info , callback)->
    @connection = mysql.createConnection(@info)
    @connection.connect(callback)

  serialize: ->
    c = @connection.config
    host: c.host,
    port: c.port,
    user: c.user,
    password: c.password

  dispose: ->
    @connection.end()

  query: (text,callback) ->
    if @fatal
      @connection = mysql.createConnection(@info)
      @fatal = false
    @connection.query {sql: text , timeout: @timeout }, (err, rows, fields)=>
      message = null
      if (err)
        message = { type: 'error' , content: err }
        @fatal = err.fatal
      else if !fields
        message = { type: 'success', content:  rows.affectedRows+" row(s) affected" }
      callback(message,rows,fields)



  getDatabases: (callback) ->
    text = "SHOW DATABASES"
    @query text , (err, rows, fields) =>
      if !err
        databases = rows.map (row) -> row["Database"]
        databases = databases.filter (database) => !@hiddenDatabase(database)
      callback(err,databases)

  getTables: (database,callback) ->
    text = "SHOW TABLES IN #{database}"
    @query text , (err, rows, fields) =>
      if !err
        tables = rows.map (row) ->
          row[fields[0].name]
        callback(tables)

  getColumns: (table,database,callback) ->
    text = "SHOW COLUMNS IN #{table} IN #{database}"
    @query text , (err, rows, fields) =>
      if !err
        columns = rows.map (row) =>
          {
            name: row['Field'],
            primary_key: row["Key"] == "PRI"
            datatype: row['Type']
            default: row['Default']
            nullable: row['Null'] == 'YES'
          }
        callback(columns)

  hiddenDatabase: (database) ->
    database == "information_schema" ||
    database == "performance_schema" ||
    database == "mysql"

  simpleSelect: (table,database)->
    table = @connection.escapeId(table)
    database = @connection.escapeId(database)
    "SELECT * FROM #{database}.#{table} LIMIT 1000"


  createDatabase: (model,info)->
    database = @connection.escapeId(info.name)
    "CREATE SCHEMA #{database};"

  createTable: (model,info)->
    database = @connection.escapeId(model.database)
    table = @connection.escapeId(info.name)
    "CREATE TABLE #{database}.#{table} ( \n"+
    " `id` INT NOT NULL ,\n"+
    " PRIMARY KEY (`id`) );"

  createColumn: (model,info)->
    database = @connection.escapeId(model.database)
    table = @connection.escapeId(model.table)
    column = @connection.escapeId(info.name)
    nullable = if info.nullable then 'NULL' else 'NOT NULL'
    dafaultValue = @escape(info.default,info.datatype) || 'NULL'
    "ALTER TABLE #{database}.#{table} ADD COLUMN #{column}"+
    " #{info.datatype} #{nullable} DEFAULT #{dafaultValue};"


  alterTable: (model,delta)->
    database = @connection.escapeId(model.database)
    newName = @connection.escapeId(delta.new_name)
    oldName = @connection.escapeId(delta.old_name)
    query = "ALTER TABLE #{database}.#{oldName} RENAME TO #{database}.#{newName};"

  alterColumn: (model,delta)->
    database = @connection.escapeId(model.database)
    table = @connection.escapeId(model.table)
    newName = @connection.escapeId(delta.new_name)
    oldName = @connection.escapeId(delta.old_name)
    nullable = if delta.nullable then 'NULL' else 'NOT NULL'
    dafaultValue = @escape(delta.default,delta.datatype) || 'NULL'
    "ALTER TABLE #{database}.#{table} CHANGE COLUMN #{oldName} #{newName}"+
    " #{delta.datatype} #{nullable} DEFAULT #{dafaultValue};"

  dropDatabase: (model)->
    database = @connection.escapeId(model.database)
    "DROP SCHEMA #{database};"

  dropTable: (model)->
    database = @connection.escapeId(model.database)
    table = @connection.escapeId(model.table)
    "DROP TABLE #{database}.#{table};"

  dropColumn: (model)->
    database = @connection.escapeId(model.database)
    table = @connection.escapeId(model.table)
    column = @connection.escapeId(model.column)
    "ALTER TABLE #{database}.#{table} DROP COLUMN #{column};"

  getDataTypes: ->
    @n_types.concat(@s_types)

  toString: ->
    @protocol+"://"+@connection.config.user+"@"+@connection.config.host

  escape: (value,type)->
    for t1 in @s_types
      if type.search(new RegExp(t1, "i")) == -1
        return @connection.escape(value)
    str
