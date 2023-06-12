{View, $} = require './space-pen'

module.exports =
class SpinnerView extends View

  @content: ->
    @div class: 'quick-query-modal-spinner', =>
      @span class: 'loading loading-spinner-tiny inline-block'
      @span bind: 'message', class: 'message'

  setMessage: (message)->
    @message.textContent = message.content

  destroy: ->
    @element.remove()
