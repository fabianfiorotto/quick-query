{View, $} = require 'atom-space-pen-views'
json2csv = require('json2csv')
fs = require('fs')

module.exports =
class QuickQueryResultView extends View
  keepHidden: false
  rows: null,
  fields: null
  canceled: false

  constructor:  ()->
    super

  initialize: ->
    $(window).resize =>
      @fixSizes()
    @handleResizeEvents()

  getTitle: -> 'Query Result'

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

  showRows: (@rows, @fields,@connection,done)->
    @table.css('height','') #added in fixNumbers()
    @attr 'data-allow-edition' , =>
      if @connection.allowEdition then 'yes' else null
    @keepHidden = false
    thead = document.createElement('thead')
    tr = document.createElement('tr')
    for field in @fields
      th = document.createElement('th')
      th.textContent = field.name
      tr.appendChild(th)
    thead.appendChild(tr)
    @table.html(thead)
    @numbers.empty()
    tbody = document.createElement('tbody')
    # for row,i in @rows
    @canceled = false
    @forEachChunk @rows , done , (row,i) =>
      array_row = Array.isArray(row)
      tr = document.createElement('tr')
      td = document.createElement('td')
      td.textContent = i+1
      tr.appendChild td
      @numbers.append(tr)
      tr = document.createElement('tr')
      for field,j in @fields
        td = document.createElement('td')
        row_value = if array_row then row[j] else row[field.name]
        if row_value?
          td.setAttribute 'data-original-value' , row_value
          td.textContent = row_value
          @showInvisibles(td)
        else
          td.dataset.originalValueNull = true
          td.classList.add 'null'
          td.textContent = 'NULL'
        td.addEventListener 'mousedown', (e)=>
          @table.find('td').removeClass('selected')
          e.currentTarget.classList.add('selected')
        if @connection.allowEdition
          td.addEventListener 'dblclick', (e)=> @editRecord(e.currentTarget)
        tr.appendChild td
      tbody.appendChild(tr)
    @table.append(tbody)
    if atom.config.get('quick-query.resultsInTab')
      @find('.quick-query-result-resize-handler').hide()
      @find('.quick-query-result-numbers').css top:0
      thead.style.marginTop = 0
    @tableWrapper.unbind('scroll').scroll (e) =>
      scroll = $(e.target).scrollTop() - thead.offsetHeight
      @numbers.css 'margin-top': (-1*scroll)
      scroll = $(e.target).scrollLeft()
      thead.style.marginLeft = (-1*scroll)+"px"

  showInvisibles: (td)->
    td.innerHTML = td.innerHTML
      .replace(/\r\n/g,'<span class="crlf"></span>')
      .replace(/\n/g,'<span class="lf"></span>')
      .replace(/\r/g,'<span class="cr"></span>')
    s.textContent = "\r\n" for s in td.getElementsByClassName("crlf")
    s.textContent = "\n" for s in td.getElementsByClassName("lf")
    s.textContent = "\r" for s in td.getElementsByClassName("cr")

  forEachChunk: (array,done,fn)->
    chuncksize = 100
    index = 0
    doChunk = ()=>
      cnt = chuncksize
      while cnt > 0 && index < array.length
        fn.call(@,array[index], index, array)
        ++index
        cnt--
      if index < array.length
        @loop = setTimeout(doChunk, 1)
      else
        @loop = null
        done?()
    doChunk()

  stopLoop: ->
    if @loop?
      clearTimeout(@loop)
      @loop = null
      @canceled = true

  rowsStatus: ->
    added = @table.find('tr.added').length
    status = (@rows.length + added).toString()
    status += if status == '1' then ' row' else ' rows'
    if @canceled
      tr_count = @table.find('tr').length - 1
      status = "#{tr_count} of #{status}"
    status += ",#{added} added" if added > 0
    modified = @table.find('tr.modified').length
    status += ",#{modified} modified" if modified > 0
    removed = @table.find('tr.removed').length
    status += ",#{removed} deleted" if removed > 0
    status

  copy: ->
    $td = @find('td.selected')
    if $td.length == 1
      atom.clipboard.write($td.text())

  copyAll: ->
    if @rows? && @fields?
      if Array.isArray(@rows[0])
        fields = @fields.map (field,i) ->
          label: field.name
          value: (row)-> row[i]
      else
        fields = @fields.map (field) -> field.name
      rows = @rows.map (row) ->
        simpleRow = JSON.parse(JSON.stringify(row))
        simpleRow
      json2csv del: "\t", data: rows , fields: fields , defaultValue: '' , (err, csv)->
        if (err)
          console.log(err)
        else
          atom.clipboard.write(csv)

  saveCSV: ->
    if @rows? && @fields?
      filepath = atom.showSaveDialogSync()
      if filepath?
        if Array.isArray(@rows[0])
          fields = @fields.map (field,i) ->
            label: field.name
            value: (row)-> row[i]
        else
          fields = @fields.map (field) -> field.name
        rows = @rows.map (row) ->
          simpleRow = JSON.parse(JSON.stringify(row))
          simpleRow[field] ?= '' for field in fields #HERE
          simpleRow
        json2csv  data: rows , fields: fields , defaultValue: '' , (err, csv)->
          if (err)
            console.log(err)
          else
            fs.writeFile filepath, csv, (err)->
              if (err) then console.log(err) else console.log('file saved')

  editRecord: (td)->
    if td.getElementsByTagName("atom-text-editor").length == 0
      td.classList.add('editing')
      editor = document.createElement('atom-text-editor')
      editor.setAttribute('mini','mini');
      editor.classList.add('editor')
      textEditor = editor.getModel()
      textEditor.setText(td.textContent) unless td.classList.contains('null')
      td.innerHTML = ''
      td.appendChild(editor)
      editor.addEventListener 'keydown', (e) ->
        $(this).blur() if e.keyCode == 13
      textEditor.onDidChangeCursorPosition (e) =>
        if editor.offsetWidth > @tableWrapper.width() #center cursor on screen
          td = editor.parentNode
          tr = td.parentNode
          charWidth =  textEditor.getDefaultCharWidth()
          column = e.newScreenPosition.column
          trleft = -1 * $(tr).offset().left
          tdleft =  $(td).offset().left
          width = @tableWrapper.width() / 2
          left = trleft + tdleft - width
          if Math.abs(@tableWrapper.scrollLeft() - (left + column * charWidth)) > width
            @tableWrapper.scrollLeft(left + column * charWidth)
      editor.addEventListener 'blur', (e) =>
        td = e.currentTarget.parentNode
        td.classList.remove('editing','selected','null')
        tr = td.parentNode
        #$tr.hasClass('status-removed') return
        td.textContent = e.currentTarget.getModel().getText()
        @showInvisibles(td)
        @fixSizes()
        if tr.classList.contains('added')
          td.classList.remove('default')
          td.classList.add('status-added')
        else
          if e.currentTarget.getModel().getText() != td.getAttribute('data-original-value')
            tr.classList.add('modified')
            td.classList.add('status-modified')
          else
            td.classList.remove('status-modified')
            if tr.querySelector('td.status-modified') == null
              tr.classList.remove('modified')
        @trigger('quickQuery.rowStatusChanged',[tr])
      $(editor).focus()

  insertRecord: ->
    td = document.createElement 'td'
    tr = document.createElement 'tr'
    number = @numbers.children().length + 1
    td.textContent = number
    tr.appendChild(td)
    @numbers.append(tr)
    tr = document.createElement 'tr'
    tr.classList.add 'added'
    @table.find("th").each =>
      td = document.createElement 'td'
      td.addEventListener 'mousedown', (e)=>
        @table.find('td').removeClass('selected')
        e.currentTarget.classList.add('selected')
      td.classList.add('default')
      td.addEventListener 'dblclick', (e) => @editRecord(e.currentTarget)
      tr.appendChild(td)
    @table.find('tbody').append(tr)
    @fixSizes() if number == 1
    @tableWrapper.scrollTop -> this.scrollHeight
    @trigger('quickQuery.rowStatusChanged',[tr])

  selectedTd: -> @find('td.selected').get(0)

  deleteRecord: ->
    td = @selectedTd()
    if td?
      tr = td.parentNode
      tr.classList.remove('modified')
      for td1 in tr.children
        td1.classList.remove('status-modified','selected')
      tr.classList.add('status-removed','removed')
      @trigger('quickQuery.rowStatusChanged',[tr])

  undo: ->
    td = @selectedTd()
    if td?
      tr = td.parentNode
      if tr.classList.contains('removed')
        tr.classList.remove('status-removed','removed')
      else if tr.classList.contains('added')
        td.classList.remove('null')
        td.classList.add('default')
        td.textContent = ''
      else
        if td.dataset.originalValueNull
          td.classList.add('null')
          td.textContent = 'NULL'
        else
          value = td.getAttribute('data-original-value')
          td.classList.remove('null')
          td.textContent = value
          @showInvisibles(td)
        td.classList.remove('status-modified')
        if tr.querySelector('td.status-modified') == null
          tr.classList.remove('modified')
      @trigger('quickQuery.rowStatusChanged',[tr])

  setNull: ->
    td = @selectedTd()
    if td? && !td.classList.contains('null')
      tr = td.parentNode
      #$tr.hasClass('status-removed') return
      td.textContent = 'NULL'
      td.classList.add('null')
      if tr.classList.contains('added')
        td.classList.remove('default')
        td.classList.add('status-added')
      else if td.dataset.originalValueNull
        td.classList.remove('status-modified')
        if tr.querySelector('td.status-modified') == null
          tr.classList.remove('modified')
      else
        tr.classList.add('modified')
        td.classList.add('status-modified')
      td.classList.remove('selected')
      @trigger('quickQuery.rowStatusChanged',[tr])

  apply: ->
    @table.find('tbody tr').each (i,tr)=>
      values = {}
      if tr.classList.contains('modified')
        row = @rows[i]
        for td,j in tr.childNodes
          if td.classList.contains('status-modified')
            value = if td.classList.contains('null') then null else td.textContent
            values[@fields[j].name] = value
        fields = @fields.filter (field) -> values.hasOwnProperty(field.name)
        @connection.updateRecord(row,fields,values)
      else if tr.classList.contains('added')
        for td,j in tr.childNodes
          unless td.classList.contains('default')
            value = if td.classList.contains('null') then null else td.textContent
            values[@fields[j].name] = value
        fields = @fields.filter (field) -> values.hasOwnProperty(field.name)
        @connection.insertRecord(fields,values)
      else if tr.classList.contains('status-removed')
        row = @rows[i]
        @connection.deleteRecord(row,@fields)

  hiddenResults: ->
    @keepHidden

  showResults: ->
    @keepHidden = false

  hideResults: ->
    @keepHidden = true

  fixSizes: ->
    if @table.find('tbody tr').length > 0
      tds = @table.find('tbody tr:first').children()
      @table.find('thead tr').children().each (i, th) =>
        td = tds[i]
        thw = th.offsetWidth
        tdw = td.offsetWidth
        w = Math.max(tdw,thw)
        td.style.minWidth = w+"px"
        th.style.minWidth = w+"px"
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

  onRowStatusChanged: (callback)->
    @bind 'quickQuery.rowStatusChanged', (e,row)-> callback(row)

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
