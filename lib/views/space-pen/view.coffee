$ = require 'jquery'

# My own version of space-pen's View
# View doesn't inherit from a jQuery object
# I removed all jQuery extensions
# Use bind instead of outlet to get the native object
Tags =
  'a abbr address article aside audio b bdi bdo blockquote body button canvas
   caption cite code colgroup datalist dd del details dfn dialog div dl dt em
   fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header html i
   iframe ins kbd label legend li main map mark menu meter nav noscript object
   ol optgroup option output p pre progress q rp rt ruby s samp script section
   select small span strong style sub summary sup table tbody td textarea tfoot
   th thead time title tr u ul var video area base br col command embed hr img
   input keygen link meta param source track wbr'.split /\s+/

Events =
  'blur change click dblclick error focus input keydown
   keypress keyup load mousedown mousemove mouseout mouseover
   mouseup resize scroll select submit unload'.split /\s+/

class Builder

  constructor: (@view)->
    @parentStack = []

  subview: (outlet, subview) ->
    @view[outlet] = subview if outlet?
    subview.parentView = @view
    @parent.appendChild(subview.element) if @parent?

  raw: (html) ->
    div = document.createElement('div')
    div.innerHTML = html
    for child in div.childNodes
      @parent.appendChild(child) if @parent?

  text: (text)->
    node = document.createTextNode(text)
    @parent?.appendChild(node)

  tag: (tagName, args...) ->
    element = document.createElement(tagName)
    options = @extractOptions(args)
    for attributeName, value of options.attributes
      element.setAttribute(attributeName, value)
    if options.text?
      element.textContent = options.text
    else if options.content?
      @parentStack.push(@parent) if @parent
      @parent = element
      options.content()
      @parent = @parentStack.pop()
    if @parent?
      @parent.appendChild(element)
    element

  extractOptions: (args) ->
    options = {}
    for arg in args
      switch typeof(arg)
        when 'function'
          options.content = arg
        when 'string', 'number'
          options.text = arg.toString()
        else
          options.attributes = arg
    options

module.exports =
class View

  Tags.forEach (tagName) ->
    View[tagName] = (args...) -> @currentBuilder.tag(tagName, args...)

  constructor: (args...)->
    unless @element?
      @element = @constructor.render((-> @content(args...)), @, true)
    # Write outlets
    for element in @element.querySelectorAll('[outlet]')
      outlet = element.getAttribute('outlet')
      @[outlet] = $(element) #TODO: Remove jQuery
      element.removeAttribute('outlet')
    for element in @element.querySelectorAll('[bind]')
      bind = element.getAttribute('bind')
      @[bind] = element
      element.removeAttribute('bind')
    view = @
    for eventName in Events
      selector = "[#{eventName}]"
      for element in @element.querySelectorAll(selector)
        do (element) ->
          methodName = element.getAttribute(eventName)
          element.addEventListener eventName, (event) -> view[methodName](event, element)

      if @element.matches(selector)
        methodName = @element.getAttribute(eventName)
        do (methodName) ->
          view.element.addEventListener eventName, (event) -> view[methodName](event, view.element)
    @initialize?(args...)

  @tag: (tagName, args...) -> @currentBuilder.tag(tagName, args...)

  @raw: (html)-> @currentBuilder.raw(html)

  @text: (text)-> @currentBuilder.text(text)

  @subview: (outletName, subview) ->
    @currentBuilder.subview(outletName, subview)

  @render: (fn, view, isNative = false)->
    builder = new Builder(view)
    @builderStack ?= []
    @builderStack.push(builder)
    @currentBuilder = builder
    element = fn.call(@)
    @builderStack.pop()
    @currentBuilder = @builderStack[@builderStack.length - 1]
    return if isNative then element else $(element)

  @content: ->
    @div ""

  isOnDom: ->
    @element.closest('body') == document.body
