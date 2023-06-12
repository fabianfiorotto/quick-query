{View, $} = require './space-pen'
{Emitter} = require 'atom'

module.exports =
class ModalView extends View

  constructor: (message)->
    @message = message
    @emitter = new Emitter()
    super

  @content: (message)->
    componentClass = if message.type == 'error' then 'text-error' else ''
    @div class: "quick-query-modal-message #{componentClass}", mouseover: 'animate', =>
      @span class: 'message', message.content
      if message.type == 'error'
        @span  click: 'copy', class: 'icon icon-clippy', title: "Copy to clipboard"
      @span click: 'close', class: 'icon icon-x'

  animate: ->
    @element.classList.add('animated') if @message.type == 'error'

  copy: ->
    atom.clipboard.write(@message.content)

  close: ->
    @emitter.emit 'close'

  onClose: (bk)->
    @emitter.on 'close', bk

  destroy: ->
    @element.remove()
    @emitter.dispose()
