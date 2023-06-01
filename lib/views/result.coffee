{View, $} = require './space-pen'
GridView = require './grid'
json2csv = require('json2csv')
fs = require('fs')

module.exports =
class ResultView extends View
  keepHidden: false
  rows: null,
  fields: null
  canceled: false

  constructor:  ()->
    super

  initialize: ->
    @handleResizeEvents() unless atom.config.get('quick-query.resultsInTab')
    @grid.applyButton.click (e) => @applyChanges()
    @acceptButton.keydown (e) =>
      if e.keyCode == 13 then @acceptButton.click()
      if e.keyCode == 39 then @cancelButton.focus()
    @cancelButton.keydown (e) =>
      if e.keyCode == 13 then @cancelButton.click()
      if e.keyCode == 37 then @acceptButton.focus()


  getTitle: -> 'Query Result'

  serialize: ->

  @content: ->
    @div class: 'quick-query-result' , =>
      @div class: 'quick-query-result-resize-handler', outlet: 'handler', ''
      @subview 'grid', new GridView()
      @div class: 'preview', outlet: 'preview' , ''
      @div class: 'buttons', =>
        @button class: 'btn btn-success icon icon-check',outlet:'acceptButton', ''
        @button class: 'btn btn-error icon icon-x',outlet:'cancelButton',''

  focusTable: ->
    @grid.focusTable() unless @element.classList.contains('confirmation')

  # Tear down any state and detach
  destroy: ->
    # @element.remove()

  showRows: (rows, fields,@connection)->
    @grid.showRows rows, fields, !@connection.allowEdition

  cancel: ->
    @grid.stopLoop()
    if @grid.isEditingLongText()
      @grid.focusTable()
    else if !@grid.isTableFocused()
      @panel?.hide()
      @hideResults()

  getSentences: ()->
    allChanges = @grid.getChanges()
    promises = for rowChanges in allChanges
      switch rowChanges.type
        when 'modified' then @connection.updateRecord(rowChanges.changes)
        when 'added'    then @connection.insertRecord(rowChanges.changes)
        when 'delete'   then @connection.deleteRecord(rowChanges.changes)
    Promise.all(promises).then (sentences) =>
      for rowChanges, i in allChanges
        changes: rowChanges.changes
        type: rowChanges.type
        sentence: sentences[i]

  copyChanges: ->
    @getSentences().then (allSentences)->
      sentences = allSentences.map (g)-> g.sentence
      atom.clipboard.write(sentences.join("\n"))
    .catch (err)-> console.log err

  confirm: ->
    @acceptButton.focus()
    new Promise (resolve,reject) =>
      @acceptButton.off('click.confirm').one 'click.confirm', (e) -> resolve(true)
      @cancelButton.off('click.confirm').one 'click.confirm', (e) -> resolve(false)

  applyChanges: ->
    @getSentences().then (allSentences) =>
      sentences = allSentences.map (g)-> g.sentence
      return if sentences.length == 0
      if sentences.every( (sentence)-> !/\S/.test(sentence) )
        wr = """
         Couldn't generate SQL\n
         Make sure that:\n
         * The primary key is included in the query.\n
         * The edited column isn't a computed column.\n
        """
        atom.notifications.addWarning(wr, dismissable: true)
        return
      @element.classList.add('confirmation')
      @loadPreview(sentences)
      @confirm().then (accept) =>
        @element.classList.remove('confirmation')
        if accept then @executeChanges(changeGroup) for changeGroup in allSentences
        @grid.focusTable()
    .catch (err) -> console.log(err)

  loadPreview: (sentences)->
    editorElement = document.createElement('atom-text-editor')
    editorElement.setAttributeNode(document.createAttribute('gutter-hidden'))
    editorElement.setAttributeNode(document.createAttribute('readonly'))
    editor = editorElement.getModel()
    editor.update({autoHeight: false})
    help = "-- The following SQL is going to be executed to apply the changes.\n"
    editor.setText(help+sentences.join("\n"), bypassReadOnly: true)
    atom.textEditors.setGrammarOverride(editor, 'source.sql')
    @preview.html(editorElement)

  executeChanges: (changeGroup)->
    @connection.query changeGroup.sentence, (msg,_r,_f) =>
      if msg && msg.type == 'error'
        e = msg.content.replace(/`/g,'\\`')
        err = """
          The following sentence gave an error.
          Please create an issue if you think that
          the SQL wasn't properly generated: <br/> #{e}"
        """
        atom.notifications.addError err, detail:sentence ,dismissable: true
      else
        change.apply() for change in changeGroup.changes

  toggleResults: ->
    if @keepHidden
      @showResults()
    else
      @hideResults()

  hiddenResults: ->
    @keepHidden

  showResults: ->
    @panel?.show()
    @keepHidden = false

  hideResults: ->
    @panel?.hide()
    @keepHidden = true

  handleResizeEvents: ->
    @handler.on 'mousedown', (e) => @resizeStarted(e)

  resizeStarted: ->
    $(document).on('mousemove', @resizeResultView)
    $(document).on('mouseup', @resizeStopped)
  resizeStopped: ->
    $(document).off('mousemove', @resizeResultView)
    $(document).off('mouseup', @resizeStopped)

  resizeResultView: ({pageY, which}) =>
    return @resizeStopped() unless which is 1
    height = @element.offsetHeight + @element.getBoundingClientRect().top - pageY
    @element.style.height = height + 'px'
    @grid.fixScrolls()
