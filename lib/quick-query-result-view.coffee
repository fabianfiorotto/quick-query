{ScrollView, $} = require 'atom-space-pen-views'

module.exports =
class QuickQueryResultView extends ScrollView

  constructor:  ()->
    super

  initialize: ->
    $(window).resize =>
      @fixSizes()
    @handleResizeEvents()

  # Returns an object that can be retrieved when package is activated
  getTitle: ->
    return 'Query Result'
  serialize: ->

  @content: ->
    @div class: 'quick-query-result' , =>
      @div class: 'quick-query-result-resize-handler', ''
      @table class: 'table', ''


  # Tear down any state and detach
  destroy: ->
    # @element.remove()

  show: (rows, fields)->
    $table = @find('table.table')
    $thead = $('<thead/>')
    $tr = $('<tr/>')
    $th = $('<th/>')
    $tr.html($th)
    for field in fields
      $th = $('<th/>')
      $th.text(field.name)
      $tr.append($th)
    $thead.html($tr)
    $table.html($thead)
    $tbody = $('<tbody/>')
    for row,i in rows
      $tr = $('<tr/>')
      $td = $('<td/>')
      $td.text(i+1)
      $tr.append($td)
      for field in fields
        $td = $('<td/>')
        $td.text(row[field.name])
        $tr.append($td)
      $tbody.append($tr)
    $table.append($tbody)

  fixSizes: ->
    if @find('tbody tr').length > 0
      tds = @find('tbody tr:first').children()
      @find('thead tr').children().each (i, th) =>
        td = tds[i]
        thw = $(th).outerWidth()
        tdw = $(td).outerWidth()
        w = Math.max(tdw,thw)
        $(td).css('min-width',w+"px")
        $(th).css('min-width',w+"px")

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
