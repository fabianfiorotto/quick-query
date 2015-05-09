{View, $} = require 'atom-space-pen-views'

element: null

module.exports =
class QuickQueryConnectView extends View
  constructor: () ->
    super

  initialize: ->
    @find('#quick-query-connect').keydown (e) ->
      $(this).click() if e.keyCode == 13
    @find('#quick-query-connect').click (e) =>
      connection = {
        host: @find("#quick-query-host")[0].getModel().getText(),
        port: @find("#quick-query-port")[0].getModel().getText(),
        user: @find("#quick-query-user")[0].getModel().getText(),
        password: @find("#quick-query-pass")[0].getModel().getText()
      }
      $(@element).trigger('quickQuery.connect',[connection])
    @find("#quick-query-port")[0].getModel().setText('3306')

  @content: ->
    @div class: 'quick-query-connect', =>
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
    @find('#quick-query-host').focus()
