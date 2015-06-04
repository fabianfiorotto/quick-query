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

  showRows: (@rows, @fields)->
    @keepHidden = false
    @closest('atom-panel.bottom').css overflow: 'hidden' #HACK
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
        $td.text(row[field.name])
        $td.mousedown (e)->
          $(this).closest('table').find('td').removeClass('selected')
          $(this).addClass('selected')
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
    if $td.length == 1
      atom.clipboard.write($td.text())

  saveCSV: ->
    if @rows? && @fields?
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
    @tableWrapper.height( @height() - headerHeght - 2)
    scroll = headerHeght  - @tableWrapper.scrollTop()
    @numbers.css 'margin-top': scroll
    scroll = -1 * @tableWrapper.scrollLeft()
    @table.find('thead').css 'margin-left': scroll


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
