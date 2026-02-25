{View, $} = require './space-pen'
{Emitter} = require 'atom'

module.exports =
class ConnectionStringView extends View

  constructor: ->
    @emitter = new Emitter()
    super

  @content: ->
    @div class: 'dialog quick-query-connection-string', =>
      @div class: "row", =>
        @div class: "col-sm-12 row" , =>
          @label 'conection string'
          @input outlet: "connectionString", class: "input-text native-key-bindings", placeholder: "protocol://user:password@host:port/database", type: "text", tabindex: 1
      @div class: "col-sm-12" , =>
        @button outlet:"connect", click: 'connectClick', id:"quick-query-connect", class: "btn btn-default icon icon-plug" , tabindex: "99" , "Connect"

  connectClick: ->
    urlStr = @connectionString.val()

    match = urlStr.match(/^([a-z0-9+.-]+):\/\/([^:]+):([^@]+)@([^:/?#]+)(?::(\d+))?\/([^?]+)(?:\?(.+))?$/i)

    return null if !match

    match[1] = 'postgres' if match[1] == 'postgresql'

    info =
      protocol: match[1],
      user: match[2],
      password: match[3],
      host: match[4],
      port: match[5],
      database: match[6],
      query: match[7],

    @emitter.emit 'will-connect', info

  destroy: ->
    @element.remove()
    @emitter.dispose()

  onWillConnect: (callback)->
    @emitter.on 'will-connect', callback
