View = require './view'
exports.$ = require 'jquery'
exports.$$ = (fn) -> View.render.call(View, fn, null)
exports.$$_ = (fn) -> View.render.call(View, fn, null, true)
exports.View = View
exports.SelectListView = require './select-list'
