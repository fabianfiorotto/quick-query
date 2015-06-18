{View, $} = require 'atom-space-pen-views'
json2csv = require('json2csv')

module.exports =
class QuickQueryResultView extends View
  keepHidden: false
  rows: null,
  fields: null

  constructor:  ()->
    atom.commands.add '.quick-query-result',
     'quick-query:copy': => @copy()
     'quick-query:save-csv': => @saveCSV()
     'quick-query:insert': => @insertRecord() if @is(':visible')
     'quick-query:null': => @setNull()
     'quick-query:undo': => @undo()
     'quick-query:delete': => @deleteRecord()
     'quick-query:apply': => @apply() if @is(':visible')
    super

  initialize: ->
    $(window).resize =>
      @fixSizes()
    @handleResizeEvents()

  getTitle: ->
    return 'Query Result'
  serialize: ->

  @content: ->
    @div class: 'quick-query-result' , =>
      @div class: 'quick-query-result-resize-handler', ''
      @div class: 'quick-query-result-table-wrapper', outlet: 'tableWrapper' , =>
        @table class: 'table quick-query-result-numbers', =>
          @thead => (@tr => @th '#')
          @tbody outlet: 'numbers', ''
        @table class: 'quick-query-result-table table', outlet: 'table' , ''

  # Tear down any state and detach
  destroy: ->
    # @element.remove()

  showRows: (@rows, @fields,@connection)->
    @keepHidden = false
    $thead = $('<thead/>')
    $tr = $('<tr/>')
    for field in @fields
      $th = $('<th/>')
      $th.text(field.name)
      $tr.append($th)
    $thead.html($tr)
    @table.html($thead)
    @numbers.empty()
    $tbody = $('<tbody/>')
    for row,i in @rows
      $tr = $('<tr/>')
      $td = $('<td/>')
      $td.text(i+1)
      @numbers.append($('<tr/>').html($td))
      for field in fields
        $td = $('<td/>')
        if row[field.name]?
          $td.attr('data-original-value',row[field.name])
          $td.text(row[field.name])
        else
          $td.data('original-value-null',true)
          $td.addClass('null').text('NULL')
        $td.mousedown (e)->
          $(this).closest('table').find('td').removeClass('selected')
          $(this).addClass('selected')
        $td.dblclick (e)=> @editRecord($(e.currentTarget))
        $tr.append($td)
      $tbody.append($tr)
    @table.append($tbody)
    if atom.config.get('quick-query.resultsInTab')
      @find('.quick-query-result-resize-handler').hide()
      @find('.quick-query-result-numbers').css top:0
      $thead.css 'margin-top':0
    @tableWrapper.unbind('scroll').scroll (e) =>
      scroll = $(e.target).scrollTop() - $thead.outerHeight()
      @numbers.css 'margin-top': (-1*scroll)
      scroll = $(e.target).scrollLeft()
      $thead.css 'margin-left': (-1*scroll)
  copy: ->
    $td = @find('td.selected')
    if $td.length == 1 && @is(':visible')
      atom.clipboard.write($td.text())

  saveCSV: ->
    if @rows? && @fields? && @is(':visible')
      filepath = atom.showSaveDialogSync()
      if filepath?
        fields = JSON.parse(JSON.stringify(@fields))
        fields = @fields.map (field) -> field.name
        rows = @rows.map (row) ->
          simpleRow = JSON.parse(JSON.stringify(row))
          simpleRow[field] ?= '' for field in fields
          simpleRow
        json2csv  data: rows , fields: fields , (err, csv)->
          if (err)
            console.log(err)
          else
            fs.writeFile filepath, csv, (err)->
              if (err) then console.log(err) else console.log('file saved')

  editRecord: ($td)->
    if $td.children().length == 0
      $td.addClass('editing')
      editor = $("<atom-text-editor/>").attr('mini','mini').addClass('editor')
      textEditor = editor[0].getModel()
      textEditor.setText($td.text()) if !$td.hasClass('null')
      $td.html(editor)
      editor.width(editor.width()) #HACK for One theme
      editor.keydown (e) ->
        $(this).blur() if e.keyCode == 13
      textEditor.onDidChangeCursorPosition (e) =>
        if editor.width() > @tableWrapper.width() #center cursor on screen
          charWidth =  textEditor.getDefaultCharWidth()
          column = e.newScreenPosition.column
          trleft = -1 * editor.closest('tr').offset().left
          tdleft =  editor.closest('td').offset().left
          width = @tableWrapper.width() / 2
          left = trleft + tdleft - width
          if Math.abs(@tableWrapper.scrollLeft() - (left + column * charWidth)) > width
            @tableWrapper.scrollLeft(left + column * charWidth)
      editor.blur (e) =>
        $td = $(e.currentTarget).parent()
        $td.removeClass('editing selected')
        $tr = $td.closest('tr')
        #$tr.hasClass('status-removed') return
        $td.removeClass('null')
        $td.text(e.currentTarget.getModel().getText())
        @fixSizes()
        if $tr.hasClass('added')
          $td.removeClass('default')
          $td.addClass('status-added')
        else
          if e.target.getModel().getText() != $td.attr('data-original-value')
            $tr.addClass('modified')
            $td.addClass('status-modified')
          else
            $td.removeClass('status-modified')
            if $tr.find('td.status-modified').length == 0
              $tr.removeClass('modified')
      editor.focus()

  insertRecord: ->
    $td = $("<td/>").text(@numbers.children().length)
    $tr = $("<tr/>").html($td)
    @numbers.append($tr)
    $tr = $("<tr/>")
    $tr.addClass('added')
    @table.find("th").each =>
      $td = $("<td/>")
      $td.mousedown (e)->
        $(this).closest('table').find('td').removeClass('selected')
        $(this).addClass('selected')
      $td.addClass('default')
      $td.dblclick (e) => @editRecord($(e.currentTarget))
      $tr.append($td)
    @table.find('tbody').append($tr)
    @tableWrapper.scrollTop -> this.scrollHeight

  deleteRecord: ->
    $td = @find('td.selected')
    if $td.length == 1 && @is(':visible')
      $tr = $td.parent()
      $tr.removeClass('modified')
      $tr.find('td').removeClass('status-modified selected')
      $tr.addClass('status-removed removed')

  undo: ->
    $td = @find('td.selected')
    if $td.length == 1 && @is(':visible')
      $tr = $td.closest('tr')
      if $tr.hasClass('removed')
        $tr.removeClass('status-removed removed')
      else if $tr.hasClass('added')
        $td.removeClass('null').addClass('default').text('')
      else
        if $td.data('original-value-null')
          $td.addClass('null').text('NULL')
        else
          value = $td.attr('data-original-value')
          $td.removeClass('null').text(value)
        $td.removeClass('status-modified')
        if $tr.find('td.status-modified').length == 0
          $tr.removeClass('modified')

  setNull: ->
    $td = @find('td.selected')
    if $td.length == 1 && @is(':visible') && !$td.hasClass('null')
      $tr = $td.closest('tr')
      #$tr.hasClass('status-removed') return
      $td.text('NULL')
      $td.addClass('null')
      if $tr.hasClass('added')
        $td.removeClass('default')
        $td.addClass('status-added')
      else
        $tr.addClass('modified')
        $td.addClass('status-modified')
      $td.removeClass('selected')

  apply: ->
    @table.find('tbody tr').each (i,tr)=>
      values = {}
      if $(tr).hasClass('modified')
        row = @rows[i]
        $(tr).find('td').each (j,td) =>
          if $(td).hasClass('status-modified')
            values[@fields[j].name] = if $(td).hasClass('null') then null else $(td).text()
        fields = @fields.filter (field) -> values.hasOwnProperty(field.name)
        @connection.updateRecord(row,fields,values)
      else if $(tr).hasClass('added')
        $(tr).find('td').each (j,td) =>
          unless $(td).hasClass('default')
            values[@fields[j].name] = if $(td).hasClass('null') then null else $(td).text()
        fields = @fields.filter (field) -> values.hasOwnProperty(field.name)
        @connection.insertRecord(fields,values)
      else if $(tr).hasClass('status-removed')
        row = @rows[i]
        @connection.deleteRecord(row,@fields)
  hiddenResults: ->
    @keepHidden

  hideResults: ->
    @keepHidden = true

  fixSizes: ->
    if @table.find('tbody tr').length > 0
      tds = @table.find('tbody tr:first').children()
      @table.find('thead tr').children().each (i, th) =>
        td = tds[i]
        thw = $(th).outerWidth()
        tdw = $(td).outerWidth()
        w = Math.max(tdw,thw)
        $(td).css('min-width',w+"px")
        $(th).css('min-width',w+"px")
      @fixScrolls()
    else
      @table.width(@table.find('thead').width())

  fixScrolls: ->
    headerHeght = @table.find('thead').outerHeight()
    numbersWidth = @numbers.width()
    @tableWrapper.css 'margin-left': numbersWidth , 'margin-top': (headerHeght - 1)
    @tableWrapper.height( @height() - headerHeght - 1)
    scroll = headerHeght  - @tableWrapper.scrollTop()
    @numbers.css 'margin-top': scroll
    scroll = -1 * @tableWrapper.scrollLeft()
    @table.find('thead').css 'margin-left': scroll

  fixNumbers: ->  #ugly HACK
    @table.height(@table.height()+1)
    @table.height(@table.height()-1)

  handleResizeEvents: ->
    @on 'mousedown', '.quick-query-result-resize-handler', (e) => @resizeStarted(e)
  resizeStarted: ->
    $(document).on('mousemove', @resizeResultView)
    $(document).on('mouseup', @resizeStopped)
  resizeStopped: ->
    $(document).off('mousemove', @resizeResultView)
    $(document).off('mouseup', @resizeStopped)
  resizeResultView: ({pageY, which}) =>
    return @resizeStopped() unless which is 1
    height = @outerHeight() + @offset().top - pageY
    @height(height)
    @fixScrolls()
