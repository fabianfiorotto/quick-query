QuickQueryCachedConnection = require './quick-query-cached-connection'

module.exports = class QuickQueryAutocomplete
  selector: '.source.sql'
  disableForSelector: '.source.sql .comment, .source.sql .string.quoted.single'
  excludeLowerPriority: false

  constructor:(browser)->
    # @connection = browser.connection
    # browser.onConnectionSelected (@connection)=>
    if browser.connection?
      @connection = new QuickQueryCachedConnection(connection: browser.connection)
    browser.onConnectionDeleted (connection)=> @connection = null
    browser.onConnectionSelected (connection)=>
      @connection = new QuickQueryCachedConnection(connection:  connection)


  prepareSugestions: (suggestions,prefix)->
    texts = suggestions.map (s) -> s.text
    suggestions = suggestions.filter (s, index) -> texts.indexOf(s.text) == index
    suggestions = suggestions.sort((s1,s2)-> Math.sign(s1.score - s2.score ))
    suggestions.map (item)->
      if item.type == 'table'
        text: item.text
        displayText: item.text
        replacementPrefix: prefix
        type: 'qq-table'
        iconHTML: '<i class="icon-browser"></i>'
      else if item.type == 'schema'
        text: item.text
        displayText: item.text
        replacementPrefix: prefix
        type: 'qq-schema'
        iconHTML: '<i class="icon-book"></i>'
      else if item.type == 'database'
        text: item.text
        displayText: item.text
        replacementPrefix: prefix
        type: 'qq-database'
        iconHTML: '<i class="icon-database"></i>'
      else
        text: item.text
        displayText: item.text
        replacementPrefix: prefix
        type: 'qq-column'
        iconHTML: if item.type == 'key'
            '<i class="icon-key"></i>'
          else
            '<i class="icon-tag"></i>'

  getScore: (string,prefix)-> string.indexOf(prefix)

  getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix, activatedManually}) ->
    return [] if prefix.length < 2 || !@connection? || !atom.config.get('quick-query.autompleteIntegration')
    new Promise (resolve) =>
      lwr_prefix = prefix.toLowerCase()
      editor_text = editor.getText().toLowerCase()
      defaultDatabase = @connection.getDefaultDatabase()
      suggestions = []
      @connection.children (databases) =>
        for database in databases
          lwr_database = database.name.toLowerCase()
          if activatedManually
            score = @getScore(lwr_database,lwr_prefix)
            if score? && score != -1
              suggestions.push
                text: database.name
                lower: lwr_database
                score: score
                type: 'database'
          if defaultDatabase == database.name or (editor_text.includes(lwr_database) and @connection.protocol != 'postgres')
            database.children (items) =>
              if database.child_type == 'schema'
                @getSchemasSuggestions items , suggestions, lwr_prefix, editor_text,activatedManually, =>
                  resolve(@prepareSugestions(suggestions,prefix))
              else
                @getTablesSuggestions items,suggestions,lwr_prefix, editor_text, =>
                  resolve(@prepareSugestions(suggestions,prefix))


  getSchemasSuggestions: (schemas,suggestions,prefix, editor_text, activatedManually , fn)->
    remain = schemas.length
    fn() if remain == 0
    for schema in schemas
      if activatedManually
        lwr_schema = schema.name.toLowerCase()
        score = @getScore(lwr_schema,prefix)
        if score? && score != -1
          suggestions.push
            text: schema.name
            lower: lwr_schema
            score: score
            type: 'schema'
      schema.children (tables) =>
        @getTablesSuggestions tables , suggestions, prefix, editor_text, =>
          remain--; fn() if remain == 0


  getTablesSuggestions: (tables,suggestions,prefix, editor_text, fn)->
    remain = tables.length
    fn() if remain == 0
    for table in tables
      lwr_table = table.name.toLowerCase()
      score = @getScore(lwr_table,prefix)
      if score? && score != -1
        suggestions.push
          text: table.name
          lower: lwr_table
          score: score
          type: 'table'
      if editor_text.includes(lwr_table)
        table.children (columns) =>
          for column in columns
            lwr_column = column.name.toLowerCase()
            score = @getScore(lwr_column,prefix)
            if score? && score != -1
              suggestions.push
                text: column.name
                lower: lwr_table
                score: score
                type: if column.primary_key then 'key' else 'column'
          remain--; fn() if remain == 0
      else
        remain--; fn() if remain == 0
