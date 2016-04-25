QuickQuery = require '../lib/quick-query'
{View, $} = require 'atom-space-pen-views'

# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "QuickQuery", ->
  [workspaceElement, activationPromise] = []

  beforeEach ->
    workspaceElement = atom.views.getView(atom.workspace)
    activationPromise = atom.packages.activatePackage('quick-query')

  describe "when the quick-query:new-connection event is triggered", ->
    it "shows the modal panel", ->
      # Before the activation event the view is not on the DOM, and no panel
      # has been created
      expect(workspaceElement.querySelector('.quick-query-connect')).not.toExist()

      # This is an activation event, triggering it will cause the package to be
      # activated.
      atom.commands.dispatch workspaceElement, 'quick-query:new-connection'

      waitsForPromise ->
        activationPromise

      runs ->
        expect(workspaceElement.querySelector('.quick-query-connect')).toExist()

        quickQueryElement = workspaceElement.querySelector('.quick-query-connect')
        expect(quickQueryElement).toExist()

        quickQueryPanel = atom.workspace.getModalPanels()[0]

        expect(quickQueryPanel.getItem().get(0) == quickQueryElement).toBe true
        expect(quickQueryPanel.isVisible()).toBe true
        atom.commands.dispatch workspaceElement, 'core:cancel'
        expect(quickQueryPanel.isVisible()).toBe false

    it "shows the connect view", ->
      # This test shows you an integration test testing at the view level.

      # Attaching the workspaceElement to the DOM is required to allow the
      # `toBeVisible()` matchers to work. Anything testing visibility or focus
      # requires that the workspaceElement is on the DOM. Tests that attach the
      # workspaceElement to the DOM are generally slower than those off DOM.
      jasmine.attachToDOM(workspaceElement)

      expect(workspaceElement.querySelector('.quick-query-connect')).not.toExist()

      # This is an activation event, triggering it causes the package to be
      # activated.
      atom.commands.dispatch workspaceElement, 'quick-query:new-connection'

      waitsForPromise ->
        activationPromise

      runs ->
        # Now we can test for view visibility

        quickQueryElement = workspaceElement.querySelector('.quick-query-connect')

        expect(quickQueryElement).toBeVisible()
        atom.commands.dispatch workspaceElement, 'core:cancel'
        expect(quickQueryElement).not.toBeVisible()
    it "shows the browser view", ->
      jasmine.attachToDOM(workspaceElement)

      expect(workspaceElement.querySelector('.quick-query-browser')).not.toExist()

      # This is an activation event, triggering it causes the package to be
      # activated.
      atom.commands.dispatch workspaceElement, 'quick-query:toggle-browser'

      waitsForPromise ->
        activationPromise

      runs ->
        # Now we can test for view visibility

        quickQueryElement = workspaceElement.querySelector('.quick-query-browser')

        expect(quickQueryElement).toBeVisible()
        atom.commands.dispatch workspaceElement, 'quick-query:toggle-browser'
        expect(quickQueryElement).not.toBeVisible()
