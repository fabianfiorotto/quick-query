{View, $, $$_} = require './space-pen'
{Emitter, CompositeDisposable, Disposable} = require 'atom'
json2csv = require('json2csv')
fs = require('fs')

module.exports =
class GridView extends View
  readonly: false

  constructor:  ()->
    @chuncksize = 100
    @subscriptions = new CompositeDisposable()
    @emitter = new Emitter()
    super

  initialize: ->
    @subscriptions.add atom.commands.add @table[0],
      'core:move-left':  => @moveSelection('left')
      'core:move-right': => @moveSelection('right')
      'core:move-up':    => @moveSelection('up')
      'core:move-down':  => @moveSelection('down')
      'core:undo':       => @undo()
      'core:confirm':    => @editSelected()
      'core:copy':       => @copy()
      'core:paste':      => @paste()
      'core:backspace':  => @setNull()
      'core:delete':     => @deleteRecord()
      'core:page-up':    => @moveSelection('page-up')
      'core:page-down':  => @moveSelection('page-down')
      'core:focus-next': => @focusNextCell()
      'core:cancel':     => @editSelected()
    @subscriptions.add atom.commands.add @element,
      'quick-query:copy': => @copy()
      'quick-query:copy-all': => @copyAll()
      'quick-query:save-csv': => @saveCSV()
      'quick-query:insert': => @insertRecord()
      'quick-query:null': => @setNull()
      'quick-query:undo': => @undo()
      'quick-query:delete': => @deleteRecord()
    windowResizeBk = (=> @fixSizes())
    window.addEventListener 'resize', windowResizeBk
    @subscriptions.add(new Disposable(->
      window.removeEventListener 'resize', windowResizeBk
    ))
    @handleScrollEvent()

  getTitle: -> @title ? 'untitled'

  @content: ->
    @div class: 'quick-query-grid' , =>
      @table class: 'table quick-query-grid-corner', =>
        @thead => (@tr => (@th class: 'corner', outlet: 'corner', =>
          @span class: 'hash', '#'
          @span class: 'loading-spinner', ''
          @button class: 'btn icon icon-pencil',title: 'Apply changes' , outlet: 'applyButton' , ''
        ))
      @table class: 'table quick-query-grid-numbers', outlet: 'numbers', =>
        @tbody bind: 'numbersBody', ''
      @table class: 'table quick-query-grid-header', outlet: 'header', =>
        @thead outlet: 'thead', ''
      @div class: 'quick-query-grid-table-wrapper', outlet: 'tableWrapper' , =>
        @table class: 'quick-query-grid-table table', outlet: 'table', tabindex: -1 , =>
          @tbody bind: 'tbody', ''
      @div class: 'edit-long-text', outlet: 'editLongText' , ''

  showRows: (@rows, @fields, @readonly)->
    @canceled = false
    @rowLoadded = 0
    @element.classList.remove('changed', 'confirmation')
    if @readonly
      @element.removeAttribute('data-allow-edition')
    else
      @element.setAttribute('data-allow-edition', 'yes')
    @keepHidden = false
    fields = @fields
    @thead.html( $$_ ->
      @tr =>
        @th field.name for field in fields
    )
    @tbody.innerHTML = ''
    @numbersBody.innerHTML = '';
    @tableWrapper.scrollTop(0);
    @showRowsChunk()
    @rowHeight = @table.find('tbody tr:first-child').height()
    @table.find('tbody').height(@rows.length * @rowHeight) if @rowHeight != 0

  showRowsChunk: () ->
    @element.classList.add('loading')
    chunk = @rows.slice(@rowLoadded, @rowLoadded + @chuncksize);
    for row,i in chunk
      array_row = Array.isArray(row)

      number = @rowLoadded + i + 1
      @numbersBody.appendChild($$_ ->
        @tr => @td(number)
      )
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
        if not @readonly
          td.addEventListener 'dblclick', (e)=>
            rect = e.currentTarget.getBoundingClientRect()
            col = e.pageX - rect.left - 8
            @editRecord(e.currentTarget, col)
        tr.appendChild td
      @tbody.appendChild(tr)
    @rowLoadded += @chuncksize
    @emitter.emit 'did-change-row-status', null
    if @tableWrapper.scrollTop() > @rowHeight * @rowLoadded && !@canceled
      setTimeout((=> @showRowsChunk()) , 1)
    else
      @fixSizes()
      @element.classList.remove('loading')
    if @rowLoadded >= @rows.length
      @table.find('tbody').height('')


  copyAll: ->
    return unless @rows? && @fields?
    if Array.isArray(@rows[0])
      fields = @fields.map (field,i) ->
        label: field.name
        value: (row)-> row[i]
    else
      fields = @fields.map (field) -> field.name
    rows = @rows.map (row) ->
      simpleRow = JSON.parse(JSON.stringify(row))
      simpleRow
     parser = new json2csv.Parser(del: "\t", fields: fields , defaultValue: '')
     csv = parser.parse(rows)
     atom.clipboard.write(csv)

  saveCSV: ->
    return unless @rows? && @fields?
    atom.getCurrentWindow().showSaveDialog title: 'Save Query Result as CSV', defaultPath: process.cwd(), (filepath) =>
      return unless filepath?
      if Array.isArray(@rows[0])
        fields = @fields.map (field,i) ->
          label: field.name
          value: (row)-> row[i]
      else
        fields = @fields.map (field) -> field.name
      rows = @rows.map (row) ->
        simpleRow = JSON.parse(JSON.stringify(row))
        simpleRow[field] ?= '' for field in fields
        simpleRow
      parser = new json2csv.Parser(del: "\t", fields: fields , defaultValue: '')
      csv = parser.parse(rows)
      fs.writeFile filepath, csv, (err)->
        if (err) then console.log(err) else console.log('file saved')


  showInvisibles: (td)->
    td.innerHTML = td.innerHTML
      .replace(/\r\n/g,'<span class="crlf"></span>')
      .replace(/\n/g,'<span class="lf"></span>')
      .replace(/\r/g,'<span class="cr"></span>')
    s.textContent = "\r\n" for s in td.getElementsByClassName("crlf")
    s.textContent = "\n" for s in td.getElementsByClassName("lf")
    s.textContent = "\r" for s in td.getElementsByClassName("cr")

  isTableFocused: -> @table.is(':focus')
  isEditingLongText: -> @element.classList.contains('editing-long-text')

  focusTable: ->
    @table.focus()

  getCursor: ->
    td = @selectedTd()
    return null unless td
    tr = td.parentNode
    x = [tr.children...].indexOf(td)
    y = [tr.parentNode.children...].indexOf(tr)
    [x,y]

  setCursor: (x,y)->
    td1 = @selectedTd()
    td2 = @getTd(x, y)
    return unless td1 && td2 && td1 != td2
    td1.classList.remove('selected')
    td2.classList.add('selected')

  stopLoop: ->
    @canceled = true

  rowsStatus: ->
    table = @element.querySelector('.quick-query-grid-table')
    added = table.querySelectorAll('tr.added').length
    status = (@rows.length + added).toString()
    status += if status == '1' then ' row' else ' rows'
    if @rowLoadded < @rows.length
      tr_count = table.querySelectorAll('tr').length
      status = "#{tr_count} of #{status}"
    status += ",#{added} added" if added > 0
    modified = table.querySelectorAll('tr.modified').length
    status += ",#{modified} modified" if modified > 0
    removed = table.querySelectorAll('tr.removed').length
    status += ",#{removed} deleted" if removed > 0
    if added+modified+removed>0
      @element.classList.add('changed')
    else
      @element.classList.remove('changed')
    status

  copy: ->
    td = @selectedTd()
    atom.clipboard.write(td.textContent) if td

  paste: ->
    return if @readonly
    td = @selectedTd()
    val = atom.clipboard.read()
    @setCellVal(td,val)

  moveSelection: (direction)->
    td1 = @selectedTd()
    return if td1.classList.contains('editing')
    tr = td1.parentNode
    [x, y] = @getCursor()
    td2 = switch direction
      when 'right' then td1.nextElementSibling
      when 'left'  then td1.previousElementSibling
      when 'up'    then tr.previousElementSibling?.children[x]
      when 'down'  then tr.nextElementSibling?.children[x]
      when 'page-up', 'page-down'
        trs = tr.parentNode.children
        page_size = Math.floor(@tableWrapper.height()/td1.offsetHeight)
        tr_index = if direction == 'page-up'
          Math.max(0, y - page_size)
        else
          Math.min(trs.length-1, y + page_size)
        trs[tr_index].children[cursor.x]
    if td2
      td1.classList.remove('selected')
      td2.classList.add('selected')
      @scrollToTd(td2)

  scrollToTd: (td)->
    table = @tableWrapper.offset()
    table.bottom = table.top + @tableWrapper.height()
    table.right = table.left + @tableWrapper.width()
    cell = td.getBoundingClientRect()
    if cell.top < table.top
      @tableWrapper.scrollTop(@tableWrapper.scrollTop() - table.top + cell.top)
    if cell.bottom > table.bottom
      @tableWrapper.scrollTop(@tableWrapper.scrollTop() + cell.bottom - table.bottom + 1.5 * cell.height)
    if cell.left < table.left
      @tableWrapper.scrollLeft(@tableWrapper.scrollLeft() - table.left + cell.left)
    if cell.right > table.right
      @tableWrapper.scrollLeft(@tableWrapper.scrollLeft() + cell.right - table.right + 1.5 * cell.width)

  editRecord: (td, cursor)->
    return if td.getElementsByTagName("atom-text-editor").length > 0
    td.classList.add('editing')
    editor = document.createElement('atom-text-editor')
    editor.classList.add('editor')
    editor.setAttribute('mini','mini');
    textEditor = editor.getModel()
    textEditor.setText(td.textContent) unless td.classList.contains('null')
    if textEditor.getLineCount() == 1
      td.innerHTML = ''
      td.appendChild(editor)
      if cursor?
        charWidth = textEditor.getDefaultCharWidth()
        textEditor.setCursorBufferPosition([0, Math.floor(cursor/charWidth)])
      textEditor.onDidChangeCursorPosition (e) => @miniEditorScroll(e, editor)
    else
      editor = document.createElement('atom-text-editor')
      editor.classList.add('editor')
      textEditor = editor.getModel()
      textEditor.setText(td.textContent)
      textEditor.update({autoHeight: false})
      @element.classList.add('editing-long-text')
      @editLongText.html(editor)
    textEditor.getBuffer().clearUndoStack()
    editor.addEventListener 'blur', (e) =>
      editor = e.currentTarget
      @element.classList.remove('editing-long-text')
      td = $('.editing',@table)[0]
      val = editor.getModel().getText()
      @setCellVal(td,val)
      # HACK that brings resize handler back after edit long text
      @element.style.marginTop = 0; setTimeout((=> @element.style.marginTop = ''), 50)
    editor.focus()

  miniEditorScroll: (e, editor)->
    return if editor.offsetWidth <= @tableWrapper.width()
    textEditor = editor.getModel()
    # center cursor on screen
    td = editor.parentNode
    tr = td.parentNode
    charWidth = textEditor.getDefaultCharWidth()
    column = e.newScreenPosition.column
    trleft = -1 * tr.getBoundingClientRect().left
    tdleft = td.getBoundingClientRect().left
    width = @tableWrapper.width() / 2
    left = trleft + tdleft - width
    if Math.abs(@tableWrapper.scrollLeft() - (left + column * charWidth)) > width
      @tableWrapper.scrollLeft(left + column * charWidth)

  editSelected: ->
    td = @selectedTd()
    return unless td? && !@readonly
    editors = td.getElementsByTagName("atom-text-editor")
    if editors.length == 0
      @editRecord(td)
    else
      val = editors[0].getModel().getText()
      @setCellVal(td,val)
      @table.focus()

  setCellVal: (td,text)->
    return unless td
    td.classList.remove('editing','null')
    tr = td.parentNode
    #$tr.hasClass('status-removed') return
    td.textContent = text
    @showInvisibles(td)
    @fixSizes()
    if tr.classList.contains('added')
      td.classList.remove('default')
      td.classList.add('status-added')
    else if text != td.getAttribute('data-original-value')
        tr.classList.add('modified')
        td.classList.add('status-modified')
    else
      td.classList.remove('status-modified')
      if tr.querySelector('td.status-modified') == null
        tr.classList.remove('modified')
    @emitter.emit 'did-change-row-status', tr

  insertRecord: ->
    @tableWrapper.scrollTop -> this.scrollHeight
    checkFn = () =>
      if @rowLoadded >= @rows.length
        @insertNewNow()
      else
        setTimeout(checkFn ,10)
    checkFn()

  insertNewNow: ->
    number = @numbers.find('tr').length + 1
    @numbers.children('tbody').append( $$_ ->
      @tr => @td number
    )
    tr = document.createElement 'tr'
    tr.classList.add 'added'
    @header.find("th").each =>
      td = document.createElement 'td'
      td.addEventListener 'mousedown', (e)=>
        @table.find('td').removeClass('selected')
        e.currentTarget.classList.add('selected')
      td.classList.add('default')
      td.addEventListener 'dblclick', (e) =>
        rect = e.currentTarget.getBoundingClientRect()
        col = e.pageX - rect.left - 8
        @editRecord(e.currentTarget, col)
      tr.appendChild(td)
    @table.find('tbody').append(tr)
    @fixSizes() if number == 1
    @tableWrapper.scrollTop -> this.scrollHeight
    @emitter.emit 'did-change-row-status', tr

  selectedTd: -> @element.querySelector('td.selected')
  getTd: (x,y) -> @element.querySelector(".quick-query-grid-table tr:nth-child(#{y}) td:nth-child(#{x})")

  deleteRecord: ->
    td = @selectedTd()
    return unless not @readonly && td?
    tr = td.parentNode
    tr.classList.remove('modified')
    for td1 in tr.children
      td1.classList.remove('status-modified')
    tr.classList.add('status-removed','removed')
    @emitter.emit 'did-change-row-status', tr

  undo: ->
    td = @selectedTd()
    return unless td?
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
      @emitter.emit 'did-change-row-status', tr

  setNull: ->
    td = @selectedTd()
    return unless not @readonly && td? && !td.classList.contains('null')
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
    @emitter.emit 'did-change-row-status', tr

  getChanges: ->
    allChanges = []
    @table.find('tbody tr').each (i,tr)=>
      changes = []
      rowChanges = null
      apply = () => @applyChangesToRow(tr, i)
      if tr.classList.contains('modified')
        row = @rows[i]
        for td,j in tr.childNodes
          change = { field: @fields[j],  value: row[j], apply }
          if td.classList.contains('status-modified')
            change.newValue = if td.classList.contains('null') then null else td.textContent
          changes.push change
        rowChanges = {type: 'modified', changes}
      else if tr.classList.contains('added')
        for td,j in tr.childNodes
          change = { field: @fields[j], apply }
          unless td.classList.contains('default')
            change.value = if td.classList.contains('null') then null else td.textContent
          changes.push change
        rowChanges = {type: 'added', changes}
        allChanges.push(rowChanges)
      else if tr.classList.contains('status-removed')
        row = @rows[i]
        changes = @fields.map (field,j)-> {field: field, value: row[j], apply}
        rowChanges = {type: 'delete', changes}
      allChanges.push(rowChanges) if rowChanges
    return allChanges

  applyChangesToRow: (tr,index)->
    tbody = tr.parentNode
    values = for td in tr.children
      if td.classList.contains('null') then null else td.textContent
    if tr.classList.contains('status-removed')
      @rows.splice(index,1)
      tbody.removeChild(tr)
      @numbers.children('tbody').children('tr:last-child').remove()
    else if tr.classList.contains('added')
      @rows.push values
      tr.classList.remove('added')
      for td in tr.children
        td.classList.remove('status-added','default')
        td.setAttribute 'data-original-value', td.textContent
        td.dataset.originalValueNull = td.classList.contains('null')
    else if tr.classList.contains('modified')
      @rows[index] = values
      tr.classList.remove('modified')
      for td in tr.children
        td.classList.remove('status-modified')
        td.setAttribute 'data-original-value', td.textContent
        td.dataset.originalValueNull = td.classList.contains('null')
    @emitter.emit 'did-change-row-status', tr

  fixSizes: ->
    row_count = @table.find('tbody tr').length
    if row_count > 0
      tds = @table.find('tbody tr:first').children()
      @header.find('thead tr').children().each (i, th) =>
        td = tds[i]
        thw = th.offsetWidth
        tdw = td.offsetWidth
        w = Math.max(tdw,thw)
        td.style.minWidth = w+"px"
        th.style.minWidth = w+"px"
    else
      @table.width(@header.width())
    @applyButton.toggleClass('tight',row_count < 100)
    @applyButton.toggleClass('x2',row_count < 10)
    @fixScrolls()

  fixScrolls: ->
    headerHeght = @header.height()
    if @numbers.find('tr').length > 0
      numbersWidth = @numbers.width()
      @corner.css width: numbersWidth
    else
      numbersWidth = @corner.outerWidth()
    @tableWrapper.css left: numbersWidth , top: (headerHeght)
    scroll = headerHeght  - @tableWrapper.scrollTop()
    @numbers.css top: scroll
    scroll = numbersWidth - @tableWrapper.scrollLeft()
    @header.css left: scroll


  handleScrollEvent: ->
    @tableWrapper.scroll (e) =>

      if (!@rowHeight || @rowHeight == 0) && @rowLoadded < @rows.length
        @rowHeight = @table.find('tbody tr:first-child').height()
        @table.find('tbody').height(@rows.length * @rowHeight)

      if e.target.scrollTop > @rowHeight * @rowLoadded - @tableWrapper.height()
        @showRowsChunk()

      scroll = e.target.scrollTop - @header.height()
      @numbers.css top: (-1*scroll)
      scroll = e.target.scrollLeft - @numbers.width()
      @header.css left: -1*scroll

  onRowStatusChanged: (callback)->
    @emitter.on 'did-change-row-status', callback

  # Tear down any state and detach
  destroy: ->
    @subscriptions.dispose()
    @emitter.dispose()
    # @element.remove()
