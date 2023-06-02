{View, $} = require './space-pen'
GridView = require './grid'

{ parse } = require 'csv-parse'
path = require('path')

module.exports =
class CsvEditorView extends View

  constructor: ({filepath, text}) ->
    super
    @filepath = filepath;
    # this.text = "";

    records = [];
    parser = parse({
      delimiter: ','
    });
    parser.on 'readable', () =>
      while (record = parser.read()) != null
        records.push(record)
    parser.on 'error', (err) =>
      console.error(err.message);
    parser.on 'end', =>
      fields = @getFields(records)
      @grid.showRows records, fields, true
      setTimeout((=> @grid.fixSizes()), 50)
    parser.write(text)
    parser.end();

  @content: ->
    @div =>
      @subview 'grid', new GridView()

  getFields: (records)->
    records[0].map (r, i)->
      b26 = i.toString(26)
      array = for j in [0..b26.length-1]
        c = b26.charCodeAt(j)
        s = if j == b26.length-1 then 0 else -1;
        if c > 57 then c - 22 + s else c + 17 + s
      name: String.fromCharCode(array...)

  getTitle: ->
    if @filepath then path.basename(@filepath) else 'untitled';

  getPath: ->
    @filepath

  getDirectoryPath: ->
    fullPath = @getPath()
    if (fullPath) then path.dirname(fullPath)

  getFileName: ->
    fullPath = @getPath()
    if (fullPath) then path.basename(fullPath)

  getURI: ->
    @filepath
