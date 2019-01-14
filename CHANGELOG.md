## 1.0.1 - SHH pt2
  * Add the ability to change ssh port.
  * Remove timeout in ssh.

## 1.0.0 - SHH
  * Array api for mysql #50
  * SSH support for mysql #49
  * Edit multiple lines cell.

## 0.15.0 - Edit next cell
  * Use <kbd>tab</kbd> to edit next cell.
  * Fix dump loader layout
  * Fix cancel editing in atom >= 1.27.0
  * Drop support for atom < 1.27

## 0.14.0 - Dump Loader
  * Dump loader allows to execute dump files
  * Splits sentences and executes one by one
  * Shows the progress in realtime
  * Can load from filesystem or from cloud
  * Uncompress GZ if is needed
  * Select database from contextual menu in browser
  * Automatically handle *.sql.gz*, *.mysql*, *.mysql.gz* extensions.

## 0.13.0 - Global Storage
 * Store connections globally
 * Import/Export connections

## 0.12.5 - Prepare for atom 1.27
 * Set text with bypass readonly.
 * Remove duplicated suggestions.

## 0.12.4 - Prepare for atom 1.25
 * Remove call to deprecated function *showSaveDialogSync*.
 * Add Compatibility with City Lights theme.
 * Add Toggle Database Browser to View menu.

## 0.12.3 - Reconnect
* Add an option to force reconnect  #37 #51

## 0.12.2 - Bugfixes
* Fix #48
* More cursor improvements.

## 0.12.1 - Browser View Update
* Remove dependency on tree-view
* Move browser selection and toggle items with the keyboard.
* Now horizontal scroll bar is visible in Browser
* Fix horizontal scroll bar in result view when there are no results.

## 0.12.0 - Quick ~~Query~~ ...Edition
* No more negative margins.
* A button to apply changes. (#20)
* Now tables have a cursor. Press:
  * <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> or <kbd>↓</kbd> to move the cursor

  * <kbd>enter</kbd> to edit the current cell

  * <kbd>backspace</kbd> to set the current cell in *NULL*

  * <kbd>del</kbd> to mark the record to delete.

  * <kbd>ctrl</kbd> + <kbd>c</kbd> to copy the current cell's text

  * <kbd>ctrl</kbd> + <kbd>v</kbd> to paste the clipboard's content into the current cell

  * <kbd>ctrl</kbd> + <kbd>z</kbd> to undo cell's changes

  * <kbd>ctrl</kbd> + <kbd>s</kbd> to apply the changes

  * <kbd>ctrl</kbd> + <kbd>shift</kbd> + <kbd>s</kbd> to save the results as CSV

## 0.11.2 - Bugfixe
* Make horizontal scroll visible in One theme (#45)

## 0.11.1 - Bugfixes
* Add a config to hide browser buttons
* Fix refreshing tree view after table create
* Fix "add record" when the table is empty
* Press delete over an element in browser to drop it
* Render JSON fields properly (#43)
* Treat UUID fields as strings (#42)

## 0.11.0 - Loading huge tables
* Get tabindex working in atom 1.19
* Removing a LOT of jQuery has reduced table loading time in almost 70%
* Add the ability to cancel result loading if it's taking too long.
* Fix an odd behavior in spinner modal overlay

## 0.10.2 - Connect view update
* Allow to fill default database in connect view #39
* HACK to get tabindex working in atom 1.19
* Fix open file dialog in atom 1.18 #40

## 0.10.1 - The invisible update
* Show a ghost character to indicate where the breaklines are
* Don't collapse multiple spaces in cells(nowrap)
* Using monospace font family in result table.

## 0.10.0 - Prepare for atom 1.17
* Open browser in a dock
* Remove dependency on git.less #26
* Drop support for older versions of atom

## 0.9.2 - Improve for hight latency connections
* Add spinner to browser
* Increase mysql timeout to 40s #35
* Fix deprecated line #36

## 0.9.1 - Bugfixes
* Show suggestions from others databases #32
* Close result tab when config changes #31
* Add semicolon at the end of SELECT #33

## 0.9.0 - New year's update
* Autocomplete integration
* Remove all views after deactivate
* Toggle result view
* Show row count in the status bar

## 0.8.8 - Patch
* Fix open file dialog

## 0.8.7 - Patch
* Prepare for coffeescript 1.11

## 0.8.6 - Patch
* Fix missing foreign keys.

## 0.8.5 - Fixes for 1.10
* Fix bootstrap grid classes.

## 0.8.4 - June Update
* Connect event
* Select last connection when the default is deleted

## 0.8.3 - June Update
* Using atom notifications instead modals to show warnings and info
* Fix a bug with modals in Atom One theme.

## 0.8.2 - Anniversary update :tada: :tada: :tada:
* Remember browser width

## 0.8.1 - April Update Pt2
* Browser on left side

## 0.8.0 - April Update
* Array API + postgres implementation
* Execute multiple INSERT, UPDATE or DELETE statements in mysql

## 0.7.2 - March Update
* Copy errors to clipboard
* Fix a bug with foreign keys in postgres

## 0.7.1 - February Update
* Sort databases and tables
* Update node-mysql to version 2.10.2
* Store default database in session

## 0.7.0 - January Update
* Exposing browser as a service

## 0.6.2 - January Update
* Fix issue #14

## 0.6.1 - December Update
* Query spinner

## 0.6.0 - November Update
* Exposing connectView as a service

## 0.5.2 - Tuesday Update
* Fix connect view tabIndex

## 0.5.1 - Monday Update
* Copy All

## 0.5.0 - Monday Update
* Find table to select

## 0.4.2 - Bugfixes
* Fix issue 9 - Failed to load package in isotope-ui

## 0.4.1 - Bugfixes
* Fix restore session
* Fix close connection

## 0.4.0 - Monday Update
* Data editor

## 0.3.1 - Monday Update
* Close button in modal message

## 0.3.0 - Monday Update
* Postgres support
* Save as CSV

## 0.2.2 - Monday Update
* Fix vertical scrollbar position

## 0.2.1 - Bugfixes
* Solve issue 4

## 0.2.0 - Tuesday Update
* Results are only displayed in their respective tabs

## 0.1.2 - Monday Update
* Set default database
* Copy a cell in the clipboard

## 0.1.1 - Little Update
* Show Results in a tab

## 0.1.0 - First Release
* Every feature added
* Every bug fixed
