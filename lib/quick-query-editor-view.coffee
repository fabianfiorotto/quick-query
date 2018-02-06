{View, SelectListView  , $} = require 'atom-space-pen-views'


class SelectDataType extends SelectListView
  initialize: ->
    super
    @list.hide()
    @filterEditorView.focus (e)=>
      @list.show()
    @filterEditorView.blur (e)=>
      @list.hide()
  viewForItem: (item) ->
     "<li> #{item} </li>"
  confirmed: (item) ->
    @filterEditorView.getModel().setText(item)
    @list.hide()
  setError: (message='') ->
    #do nothing
  cancel: ->
    #do nothing
module.exports =
class QuickQueryEditorView extends View

  editor: null
  action: null
  model: null
  model_type: null

  constructor: (@action,@model) ->
    if @action == 'create'
      @model_type = @model.child_type
    else
      @model_type = @model.type
    super

  initialize: ->

    connection = if @model.type == 'connection' then @model else @model.connection
    @selectDataType.setItems(connection.getDataTypes())

    @nameEditor = @find('#quick-query-editor-name')[0].getModel()
    # @datatypeEditor = @find('#quick-query-datatype')[0].getModel()
    @datatypeEditor = @selectDataType.filterEditorView.getModel();
    @defaultValueEditor = @find('#quick-query-default')[0].getModel()

    @find('#quick-query-nullable').click (e) ->
          $(this).toggleClass('selected')
          $(this).html(if $(this).hasClass('selected') then 'YES' else 'NO')

    @find('#quick-query-null').change (e) =>
      $null = $(e.currentTarget)
      if $null.is(':checked')
        @find('#quick-query-default').addClass('hide')
        @find('#quick-query-default-is-null').removeClass('hide')
      else
        @find('#quick-query-default').removeClass('hide')
        @find('#quick-query-default-is-null').addClass('hide')

    @find('#quick-query-editor-done, #quick-query-nullable').keydown (e) ->
      $(this).click() if e.keyCode == 13
    @find('#quick-query-editor-done').click (e) =>
      @openTextEditor()
      @closest('atom-panel.modal').hide()

    if @action != 'create'
      @nameEditor.insertText(@model.name)

    if @model_type == 'column'
      @find('.quick-query-column-editor').removeClass('hide')
    if @model_type == 'column' && @action == 'alter'
      @datatypeEditor.setText(@model.datatype)
      @defaultValueEditor.setText(@model.default || "")
      @find('#quick-query-null').prop('checked', !@model.default?).change()
      if @model.nullable
        @find('#quick-query-nullable').click()

  @content: ->
    @div class: 'quick-query-editor' , =>
      @div class: 'row', =>
        @div class: 'col-sm-12' , =>
          @label 'name'
          @currentBuilder.tag 'atom-text-editor', id: 'quick-query-editor-name' , class: 'editor', mini: 'mini'
      @div class: 'row quick-query-column-editor hide', =>
        @div class: 'col-sm-6' , =>
          @label 'type'
          # @currentBuilder.tag 'atom-text-editor', id: 'quick-query-datatype' , class: 'editor', mini: 'mini'
          @subview 'selectDataType', new SelectDataType()
        @div class: 'col-sm-2' , =>
          @label 'nullable'
          @button id:'quick-query-nullable',class: 'btn' ,'NO'
        @div class: 'col-sm-3' , =>
          @label 'default'
          @currentBuilder.tag 'atom-text-editor', id: 'quick-query-default' , class: 'editor', mini: 'mini'
          @div id: 'quick-query-default-is-null' ,class:'hide' , "Null"
        @div class: 'col-sm-1' , =>
          @input  id: 'quick-query-null', type: 'checkbox' , style: "margin-top:24px;"
      @div class: 'row', =>
        @div class: 'col-sm-12', =>
          @button 'Done', id: 'quick-query-editor-done' , class: 'btn btn-default icon icon-check'


  openTextEditor: ()->
    comment  = "-- Check the sentence before execute it\n"+
               "-- This editor will close after you run the sentence \n"
    editText = switch @action
      when 'create'
        @getCreateText()
      when 'alter'
        @getAlterText()
      when 'drop'
        @getDropText()
    if editText != ''
      atom.workspace.open().then (editor) =>
        atom.textEditors.setGrammarOverride(editor, 'source.sql')
        editor.insertText(comment+editText)
        @editor = editor

  getCreateText: ()->
    newName= @nameEditor.getText()
    switch @model_type
      when 'database'
        info = {name: newName }
        @model.createDatabase(@model,info)
      when 'table'
        info = {name: newName }
        @model.connection.createTable(@model,info)
      when 'schema'
        info = {name: newName }
        @model.connection.createSchema(@model,info)
      when 'column'
        datatype = @datatypeEditor.getText()
        nullable = @find('#quick-query-nullable').hasClass('selected')
        defaultValue = if @find('#quick-query-null').is(':checked')
          null
        else
          @defaultValueEditor.getText()
        info =
          name: newName ,
          datatype: datatype ,
          nullable: nullable,
          default: defaultValue
        @model.connection.createColumn(@model,info)

  getAlterText: ()->
    newName= @nameEditor.getText()
    switch @model_type
      when 'table'
        delta = { old_name: @model.name , new_name: newName }
        @model.connection.alterTable(@model,delta)
      when 'column'
        datatype = @datatypeEditor.getText()
        nullable = @find('#quick-query-nullable').hasClass('selected')
        defaultValue = if @find('#quick-query-null').is(':checked')
          null
        else
          @defaultValueEditor.getText()
        delta =
          old_name: @model.name ,
          new_name: newName ,
          datatype: datatype ,
          nullable: nullable,
          default: defaultValue
        @model.connection.alterColumn(@model,delta)

  getDropText: ()->
    switch @model_type
      when 'database'
        @model.connection.dropDatabase(@model)
      when 'schema'
        @model.connection.dropSchema(@model)
      when 'table'
        @model.connection.dropTable(@model)
      when 'column'
        @model.connection.dropColumn(@model)

  getColumnInfo: ->

  focusFirst: ->
    setTimeout((=> @find('#quick-query-editor-name').focus()) ,10)
