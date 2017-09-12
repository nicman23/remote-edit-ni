{$, $$, View} = require 'atom-space-pen-views'
{CompositeDisposable, Emitter} = require 'atom'
Path = require 'path'


module.exports =
  class MiniTreeView extends View
    initialize: () ->
      # Reduced tree (the one we display)
      @tree = {root: {children:{}, parent: null, name: "root"}}
      @disposables = new CompositeDisposable
      @rightClickNode = null
      @listenForEvents()

    destroy: ->
      @disposables.dispose()

    setFilesView: (filesView) ->
      @filesView = filesView

    @content: ->
      @div class: 'remote-edit-opened-tree', =>
        #@div class: 'remote-edit-treeview-header', =>
        @span class: 'remote-edit-treeview-header inline-block', 'Open Files'
        @div class: 'remote-edit-file-scroller',  =>
          @div class: 'remote-edit-treeview-list', =>
            @ol class: 'list-entries full-menu focusable-panel', tabindex: -1, outlet: 'treeUI'

    splitPathParts: (localFile) ->
      # explode paths
      pathParts = localFile.remoteFile.path.split(Path.sep)
      if pathParts[0] == ""
        pathParts.shift()

      pathParts.unshift(localFile.host.hostname)
      return pathParts

    addFile: (localFile) =>
      # Add hostname if not in already
      node = @tree.root

      # Split to path
      pathParts = @splitPathParts(localFile)

      # Build path as we go
      pathStr = ""

      count = 0
      for p in pathParts
        count++
        pathStr += Path.sep + p

        # If there move to next node and continue
        if pathStr of node.children
          node = node.children[pathStr]
          continue

        node.children[pathStr] = {children: {}, parent: node, name: p}

        if count == 2
          node.isServer = true
        else if count > 2
          node.isFolder = true

        node = node.children[pathStr]

      # Node should be pointing to the leaf
      node.meta = localFile
      delete node["isFolder"]
      node.isFile = true
      node.selected = true

      @refreshUITree()

    closeFileFromNode: (node) =>
      uri = Path.normalize(node.meta.path)
      filePane = atom.workspace.paneForURI(uri)
      filePaneItem = filePane.itemForURI(uri)
      filePane.destroyItem(filePaneItem)

    closeFolderFromNode: (node) =>
      for path of node.children
        if node.children[path].isFile
          @closeFileFromNode(node.children[path])
          continue

        # Folders and servers
        @closeFolderFromNode(node.children[path])


    removeFile: (localFile) =>
      pathParts = @splitPathParts(localFile)
      node = @tree.root

      pathStr = ""
      for p in pathParts
        pathStr += Path.sep + p
        if !(pathStr of node.children)
          break

        node = node.children[pathStr]

      # Check if we found it
      if pathParts[pathParts.length - 1] != node.name
        return

      # Delete nodes walking up
      while node.parent
        parent = node.parent
        delete parent.children[pathStr]
        length = (k for own k of parent.children).length
        if length == 0
          node = parent
          pathStr = Path.dirname(pathStr)
        else
          break

      @refreshUITree()

    #
    # UI
    #
    refreshUITree: (node=@tree.root, name="root", parentUI=null, level=0) ->
      return unless @tree?

      length = (k for own k of node.children).length

      # New root
      if level == 0
        @treeUI.empty()
        parentUI = @treeUI

      # Depth first...
      for path of node.children

        # if folder with one child which is folder, do not display - mark skipping
        child = node.children[path]
        childLength = (k for own k of child.children).length
        skippingCurrent = false

        if child.isFolder and childLength == 1
          # Ensure that the only child is actually another folder
          innerChild = null
          for i of child.children
            innerChild = child.children[i]

          if innerChild.isFolder
            skippingCurrent = true

        if skippingCurrent
          # use the same list we were given...
          olParent = parentUI
        else
          # here we either have a legit folder or a server or a file
          # Add this node to current parent and use as parent for the rest
          currentElement = @viewForItem(child)
          currentElement.data('node', child)
          currentElement.data('node-path', path)
          parentUI.append(currentElement)
          # The parent node is actually the <ol> element...
          olParent = currentElement.find('ol.list-entries').first()

        # If not a file item... recurse based on the current element set above
        if !child.isFile
          @refreshUITree(child, path, olParent, level+1)

    deselect: ->
        @treeUI.find('li.selected').removeClass('selected');

    listenForEvents: ->
      @treeUI.on 'mousedown', (e) =>
        # console.debug e
        # e.preventDefault()
        # false


      # Folder/Server Click
      @on 'mousedown', 'li.folder', (e) =>

        if e.which == 2
          return false

        uiNode = $(e.target).closest('li')

        if e.which == 1
          @deselect()

          node = uiNode.data('node')
          uiNode.addClass('selected')

          if node.isCollapsed
            node.isCollapsed = false
            uiNode.removeClass('collapsed')
          else
            node.isCollapsed = true
            uiNode.addClass('collapsed')

        else if e.which == 3
          @rightClickNode = uiNode

        e.preventDefault()
        false

      # File Click
      @on 'mousedown', 'li.file', (e) =>
        if e.which == 2
          return false

        uiNode = $(e.target).closest('li')

        if e.which == 1
          @deselect()
          node = uiNode.addClass('selected').data('node')

          # Get local path
          uri = Path.normalize(node.meta.path)
          filePane = atom.workspace.paneForURI(uri)
          filePane.activateItemForURI(uri)

        else if e.which == 3
          @rightClickNode = uiNode

        e.preventDefault()
        false

      @disposables.add atom.commands.add 'atom-workspace', 'remote-edit:close-from-tree', =>
        if not @rightClickNode
          return
        # Destroy the item (TextEditor) to trigger the onDidDestroy which also
        # cleans up the remoteEdit.json...
        node = @rightClickNode.data('node')
        if node.isFile
          @closeFileFromNode(node)
        else
          @closeFolderFromNode(node)

      @disposables.add atom.commands.add 'atom-workspace', 'remote-edit:show-in-browser', =>
        if not @rightClickNode
          return

        node = @rightClickNode.data('node')

        folder = null
        file = null
        if node.isFile
          host = node.meta.host
          folder = node.meta.remoteFile.dirName
          file = node.meta.remoteFile.path
        else

          folder = "/"
          if node.isFolder
            folder = @rightClickNode.data('node-path')
            folder = folder.substr(folder.indexOf(Path.sep, 1))


          # Walk down until you find a file - anyfile
          for k, tmpNode of node.children
            while !tmpNode.isFile
              # Get first child
              for k, tmpNode of tmpNode.children
                break

            # Break outer for
            break

          host = tmpNode.meta.host

        if folder
          @filesView.setHost(host)

          # Select the file after the connection
          @filesView.openDirectory(folder, () =>
            if file
              @filesView.selectItemByPath(file)
          )



    viewForItem: (node) ->
      icon = switch
        when node.isFolder then 'icon-file-directory'
        when node.isFile then 'icon-file-text'
        when node.isServer then 'icon-server'
        else 'icon-file-text'

      sel = if node.selected then "selected" else ""
      delete node["selected"]

      if node.isServer or node.isFolder
        $$ ->
          @li class: 'folder', =>
              @div class: 'list-item-wrap', =>
                  @span class: 'icon '+ icon, 'data-name' : node.name, title : node.name, node.name
              @ol class: 'list-entries'
      else
        $$ ->
          @li class: 'file '+ sel, =>
            @div =>
              @span class: 'icon '+ icon, 'data-name' : node.name, title : node.name, node.name
