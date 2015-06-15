{View, $} = require 'atom-space-pen-views'

element: null

module.exports =
class QuickQueryConnectView extends View
  constructor: () ->
    super

  initialize: ->
    portEditor = @find("#quick-query-port")[0].getModel()
    portEditor.setText('3306')

    @find('#quick-query-connect').keydown (e) ->
      $(this).click() if e.keyCode == 13
    @find('#quick-query-protocol')
      .keydown (e) ->
        if e.keyCode == 13
          $(e.target).css height: 'auto'
          e.target.size = 3
        else if  e.keyCode == 37 || e.keyCode == 38
          $(e.target).find('option:selected').prev().prop('selected',true)
        else if  e.keyCode == 39 || e.keyCode == 40
          $(e.target).find('option:selected').next().prop('selected',true)
      .blur (e) ->
        $(e.target).css height: ''
        e.target.size = 0
      .on 'change blur', (e) ->
        if $(e.target).val() == 'mysql'
          portEditor.setText('3306')
        else
          portEditor.setText('5432')


    @find('#quick-query-connect').click (e) =>
      connectionInfo = {
        host: @find("#quick-query-host")[0].getModel().getText(),
        port: @find("#quick-query-port")[0].getModel().getText(),
        user: @find("#quick-query-user")[0].getModel().getText(),
        password: @find("#quick-query-pass")[0].getModel().getText()
        protocol: @find("#quick-query-protocol").val()
      }
      if connectionInfo.protocol == 'ssl-postgres'
        connectionInfo.ssl = true
        connectionInfo.protocol = 'postgres'
      $(@element).trigger('quickQuery.connect',[connectionInfo])

  @content: ->
    @div class: 'dialog quick-query-connect', =>
      @div class: "col-sm-12" , =>
        @label 'protocol'
        @select class: "form-control" , id: "quick-query-protocol", =>
          @option value: "mysql", "MySql"
          @option value: "postgres", "PostgreSQL"
          @option value: "ssl-postgres", "PostgreSQL (ssl)"
      @div class: "col-sm-9" , =>
        @label 'host'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-host", class: 'editor', mini: 'mini', type: 'string'
      @div class:"col-sm-3" , =>
        @label 'port'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-port", class: 'editor', mini: 'mini', type: 'string'
      @div class: "col-sm-6" , =>
        @label 'user'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-user", class: 'editor', mini: 'mini', type: 'string'
      @div class: "col-sm-6" , =>
        @label 'password'
        @currentBuilder.tag 'atom-text-editor', id: "quick-query-pass", class: 'editor', mini: 'mini'
      @div class: "col-sm-12" , =>
        @button id:"quick-query-connect", class: "btn btn-default icon icon-plug" , "Connect"

  destroy: ->
    @element.remove()
  focusFirst: ->
    @find('#quick-query-protocol').focus()
