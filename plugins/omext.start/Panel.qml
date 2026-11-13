import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
// Omarchy's own menu model: the same parsing, merging and guards as its menu.
import "file:///usr/share/omarchy/shell/plugins/menu/MenuModel.js" as MenuModel

// Start (omext start, from omarchy-extended): a start menu on the bar.
// Everything in the Omarchy menu, laid out on one page: its sections on the
// left, the chosen one in the middle (a submenu as a heading with its rows; one
// deeper opens in place, with a way back), and on the right every open window,
// by workspace: a click goes to it. The System entries are the buttons along
// the bottom. Search covers the menu, the installed apps and the open windows.
// The menu comes from Omarchy's files (default/omarchy/omarchy-menu.jsonc, and
// your ~/.config/omarchy/extensions/omarchy-menu.jsonc), read with Omarchy's own
// MenuModel.js, so it is always the same menu. The lists Omarchy fills in
// itself (fonts, kernels, languages, power profiles) are filled in here the same
// way. Its keyboard shortcut (Settings, the gear) is hypr/start.lua's, read
// from ~/.config/omext/start.json.
Panel {
  id: root
  moduleName: "omext.start"
  manageIpc: false  // its own, below: open at a section, or with a search

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  readonly property string userMenuPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/extensions/omarchy-menu.jsonc"
  readonly property string languagePath: Quickshell.env("OMARCHY_LANGUAGE_FILE") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/language")
  readonly property string dockTool: Quickshell.env("HOME") + "/.local/bin/omext-dock"
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omext"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  // Off (Omarchy menu › Setup › Omarchy Extended › Start, Settings, `omarchy-shell omext.start off`): no bar
  // button, no shortcut (Super + Space is Omarchy's again), until turned on.
  readonly property string offFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omext/start/disabled"
  property bool off: false
  FileView {
    path: root.offFile
    printErrors: false
    onLoaded: root.off = true
    onLoadFailed: root.off = false
  }
  // Omarchy's dock, off while Start is on (the same switch as Setup › Omarchy
  // Extended › Omarchy Dock): Super + Alt + Space opens Start's apps then. A
  // choice omext core keeps and acts on (it turns the dock off and on, and
  // has it off while omext taskbar is on, in its place).
  readonly property bool omarchyDockOff: shared.omarchyDockOff === true
  readonly property bool taskbarOn: addonOn("taskbar")
  function setOmarchyDock(on) {
    if (taskbarOn) return
    setShared({ omarchyDockOff: !on })
  }
  // In the place of Omarchy's own menu button on the bar (menu-button.sh puts
  // Start's button where that one is, and takes that one off; and back).
  // Omarchy's menu is still there: its keys, and a right click on Start's button.
  readonly property bool tookMenuButton: config.replaceMenuButton === true
  readonly property string menuButtonTool: Qt.resolvedUrl("menu-button.sh").toString().replace(/^file:\/\//, "")
  function takeMenuButton(on) {
    saveConfig({ replaceMenuButton: on })
    Quickshell.execDetached([menuButtonTool, on ? "take" : "give"])
  }
  function setOff(v) {
    Quickshell.execDetached(["bash", "-c",
      (v ? 'mkdir -p "$(dirname "$0")" && touch "$0"' : 'rm -f "$0"')
      + (root.tookMenuButton ? ' ; "$1" ' + (v ? "give" : "take") : "") + ' ; hyprctl reload >/dev/null', root.offFile, root.menuButtonTool])
  }

  readonly property color text: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Commons.Util.alpha(text, 0.5)
  readonly property string fontFamily: Style.font.family
  readonly property string iconFont: Style.font.menuFamily || Style.font.family

  // --- the menu -------------------------------------------------------------

  property var defaultItems: []
  property var userItems: []
  property var catalog: ({})
  property string language: "en"
  property var items: ({})
  property var itemOrder: []
  property var whenResults: ({})
  property var checkedResults: ({})
  property var disabledResults: ({})

  function rebuild() {
    var merged = MenuModel.mergeMenuSources(MenuModel.applyTranslations(defaultItems, catalog), userItems,
                                            catalog.root && catalog.root.label)
    items = merged.items
    itemOrder = merged.itemOrder
    evaluateGuards()
  }

  function entry(id) { return MenuModel.item(items, id) }
  function isShown(e) { return MenuModel.isVisible(items, itemOrder, whenResults, e) }
  function disabled(e) { return MenuModel.isDisabled(disabledResults, e) }
  function checked(e) { return !!(e && e.checked && checkedResults[e.id]) || disabled(e) }
  function children(id) {
    var out = []
    for (var i = 0; i < itemOrder.length; i++) {
      var e = items[itemOrder[i]]
      if (e && e.parent === id && isShown(e)) out.push(e)
    }
    return out
  }
  // A submenu of its own (not one Omarchy fills in, nor a link elsewhere).
  function isMenu(e) { return e && e.kind === "menu" && !e.provider }

  // The sections down the left: the root's, but System (the buttons below).
  readonly property var sections: { var _ = whenResults; return children("root").filter(e => e.id !== "system" && (isMenu(e) || e.id === "apps")) }
  // The root's own entries that are no section (About, a switch of your own, a
  // link): under the sections, run with a click.
  readonly property var rootActions: { var _ = whenResults; return children("root").filter(e => e.id !== "system" && !isMenu(e) && e.id !== "apps") }
  readonly property var powerRows: { var _ = whenResults; return children("system").filter(e => e.kind === "action") }
  // Along the bottom: Lock, and Power, whose click shows the rest beside them.
  property bool powerOpen: false
  property string powerHint: ""   // the option pointed at (shown when they're icons alone)
  readonly property var powerLock: powerRows.filter(e => e.id === "system.lock")
  readonly property var powerRest: powerRows.filter(e => e.id !== "system.lock")

  property string section: "apps"
  property string path: "apps"       // the menu shown in the middle (the section, or one inside it)
  readonly property var trail: {     // from the section down to it, for the way back
    var out = [], id = path
    while (id && id !== "root") { var e = entry(id); if (!e) break; out.unshift(e); id = e.parent }
    return out
  }

  // The middle: [{head}|{entry, sub}] — rows first, then each submenu as a
  // heading with its rows (a submenu in there: one row that opens it).
  readonly property var pageRows: {
    var _ = whenResults
    if (query) return searchRows
    if (specialPage === "favorites") return favoriteRows
    if (specialPage === "recent") return recentRows
    if (specialPage === "windows") return windowRows
    if (path === "apps") return appRows
    var here = entry(path)
    if (here && here.provider) return (providerRows[path] || []).map(e => ({ entry: e }))
    var rows = [], heads = []
    for (var e of children(path)) {
      if (isMenu(e) && children(e.id).length > 0 && trail.length < 2) heads.push(e)
      else rows.push({ entry: e })
    }
    for (var h of heads) {
      rows.push({ head: h.title || h.label, icon: h.icon })
      for (var c of children(h.id)) rows.push({ entry: c })
    }
    return rows
  }

  // --- guards: `when`, `checked` and `disabled` (bash, once per load) --------

  property bool guardsPending: false
  function evaluateGuards() {
    if (guardProc.running) { guardsPending = true; return }
    guardsPending = false
    var script = MenuModel.guardScript(items)
    if (!script) { whenResults = ({}); checkedResults = ({}); disabledResults = ({}); return }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser { onRead: function(data) { guardProc.collected += data + "\n" } }
    onExited: function(code, status) {
      if (code === 0 && status === 0) {
        var w = ({}), c = ({}), d = ({})
        for (var line of guardProc.collected.split("\n")) {
          line = line.trim()
          var colon = line.lastIndexOf(":")
          if (colon < 0) continue
          var rest = line.substring(0, colon), tagAt = rest.lastIndexOf(":")
          if (tagAt < 0) continue
          var id = rest.substring(0, tagAt), tag = rest.substring(tagAt + 1), on = line.substring(colon + 1) === "1"
          if (tag === "w") w[id] = on
          else if (tag === "c") c[id] = on
          else if (tag === "d") d[id] = on
        }
        root.whenResults = w; root.checkedResults = c; root.disabledResults = d
      }
      if (root.guardsPending) Qt.callLater(root.evaluateGuards)
    }
  }

  FileView {
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultItems = MenuModel.keepMenuRows(root.defaultItems, text(), true); root.rebuild() }
    onFileChanged: reload()
  }
  FileView {
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userItems = MenuModel.keepMenuRows(root.userItems, text(), false); root.rebuild() }
    onLoadFailed: { root.userItems = []; root.rebuild() }
    onFileChanged: reload()
  }
  FileView {
    path: root.languagePath
    watchChanges: true
    printErrors: false
    onLoaded: root.language = text().trim() || "en"
    onLoadFailed: root.language = "en"
    onFileChanged: reload()
  }
  FileView {
    path: root.omarchyPath + "/default/i18n/" + root.language + "/menu.json"
    watchChanges: true
    printErrors: false
    onLoaded: { try { root.catalog = JSON.parse(text()) || ({}) } catch (e) { root.catalog = ({}) } root.rebuild() }
    onLoadFailed: { root.catalog = ({}); root.rebuild() }
    onFileChanged: reload()
  }

  // --- apps -------------------------------------------------------------------

  // Left out, as Omarchy's own launcher leaves them out: its list
  // (default/omarchy/launcher.hides), and entries hidden for this desktop.
  property var hiddenIds: ({})
  property var hiddenListed: ({})
  function idsOf(text) {
    var out = ({})
    for (var l of String(text || "").split("\n")) { l = l.trim().replace(/\.desktop$/, ""); if (l) out[l] = true }
    return out
  }
  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.hiddenListed = root.idsOf(text())
    onFileChanged: reload()
  }
  Process {
    id: hiddenScan
    running: true
    // Not a login shell: a profile that touches ~/.local/share would set the
    // desktop entries rescanning (as Omarchy's launcher notes).
    command: ["bash", "-c", '"$0" "$1"', root.omarchyPath + "/shell/services/hidden-entries.sh",
              [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(v => !!v).join(":")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.hiddenIds = root.idsOf(text) }
  }
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { if (!hiddenScan.running) hiddenScan.running = true }
  }

  readonly property var apps: {
    var list = (DesktopEntries.applications ? DesktopEntries.applications.values : [])
      .filter(a => !a.noDisplay && !root.hiddenIds[a.id] && !root.hiddenListed[a.id])
    return list.slice().sort((x, y) => x.name.localeCompare(y.name))
  }
  readonly property var appRows: apps.map(a => ({ app: a }))
  function iconFor(icon) {
    if (!icon) return Quickshell.iconPath("application-x-executable", true)
    if (icon.charAt(0) === "/") return "file://" + icon
    return Quickshell.iconPath(icon, true) || Quickshell.iconPath("application-x-executable", true)
  }
  // The apps used lately, the latest first: started from here, or any other
  // way (an app counts when its window opens or gets the focus, by the window's
  // class; using one again puts it back on top). Kept in
  // ~/.local/state/omext/start/recent.json, the same for every screen's Start).
  readonly property string recentPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omext/start/recent.json"
  // [{id, t}]: each app once, with when it was last used; the latest first.
  property var recent: []
  readonly property int recentKept: 100   // the latest this many; older ones drop off
  readonly property bool recentOn: config.recentOff !== true
  // What's in the file and what's known here, as one: each app at its latest
  // use. (Saves that land out of turn, or another screen's Start, can't put an
  // older use over a newer one.)
  function recentMerged(a, b) {
    var at = ({})
    for (var list of [a, b]) for (var i = 0; i < list.length; i++) {
      var r = list[i], id = typeof r === "string" ? r : r && r.id, t = typeof r === "string" ? -i : Number(r && r.t || 0)
      if (id && (at[id] === undefined || t > at[id])) at[id] = t
    }
    return Object.keys(at).map(id => ({ id: id, t: at[id] })).sort((x, y) => y.t - x.t).slice(0, recentKept)
  }
  FileView {
    id: recentFile
    path: root.recentPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var v = []
      try { v = JSON.parse(text()); if (!Array.isArray(v)) v = [] } catch (e) { v = [] }
      var m = root.recentMerged(v, root.recent)
      if (JSON.stringify(m) !== JSON.stringify(root.recent)) root.recent = m
      if (JSON.stringify(m) !== JSON.stringify(v)) recentSave.restart()   // it knew less than we do
    }
    onLoadFailed: if (root.recent.length) recentSave.restart()
  }
  Timer {  // one save for a burst of uses
    id: recentSave
    interval: 400
    onTriggered: Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$0")" && printf "%s\n" "$1" > "$0.tmp" && mv "$0.tmp" "$0"', root.recentPath, JSON.stringify(root.recent)])
  }
  Connections {
    target: Hyprland
    enabled: root.recentOn
    function onRawEvent(event) {
      // An app is used when its window opens ("address,workspace,class,title")
      // and whenever one of its windows gets the focus ("class,title").
      var name = String(event.name), parts = String(event.data).split(",")
      var cls = name === "openwindow" ? (parts[2] || "") : name === "activewindow" ? (parts[0] || "") : ""
      var e = root.appOfClass(cls)
      if (e && root.apps.some(a => a.id === e.id)) root.noteRecent(e)
    }
  }
  // omext core: what the omext addons share (which app a window is, going to
  // a window). Its files, by their path.
  readonly property string coreDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/omext.core"
  Loader { id: coreApps; source: "file://" + root.coreDir + "/Apps.qml" }
  Loader { id: coreWindows; source: "file://" + root.coreDir + "/Windows.qml" }
  Loader { id: coreAddons; source: "file://" + root.coreDir + "/Addons.qml" }
  Loader { id: coreShared; Component.onCompleted: setSource("file://" + root.coreDir + "/Settings.qml", { name: "omext" }) }
  // The choices that cross addons (~/.config/omext/omext.json, omext core's).
  readonly property var shared: coreShared.item ? coreShared.item.values : ({})
  function setShared(patch) { if (coreShared.item) coreShared.item.set(patch) }
  function addonOn(name) { return !!coreAddons.item && coreAddons.item.on(name) }
  // The app a window is, by its class (omext core's rule: a web app is itself,
  // not its browser; an app run in a terminal is the entry that starts it so).
  function appOfClass(cls) {
    return coreApps.item ? coreApps.item.ofClass(cls) : DesktopEntries.heuristicLookup(String(cls || ""))
  }
  function noteRecent(app) {
    if (!app || !app.id) return
    if (recent.length && recent[0].id === app.id && Date.now() - recent[0].t < 60000) return   // still the one in use
    recent = recentMerged([{ id: app.id, t: Date.now() }], recent)
    recentSave.restart()
  }
  // (But the ones with a window open now: those are in front of you, or on
  // the taskbar.)
  readonly property var openAppIds: {
    var ids = ({})
    for (var c of clients) {
      if (!c || !c.mapped) continue
      var e = appOfClass(c.class) || appOfClass(c.initialClass)
      if (e) ids[e.id] = true
    }
    return ids
  }
  readonly property var recentRows: {
    var out = []
    for (var r of recent) {
      if (openAppIds[r.id]) continue
      var a = apps.find(x => x.id === r.id)
      if (a) out.push({ app: a })
    }
    return out
  }
  function launch(app) {
    root.close()
    noteRecent(app)
    if (app.runInTerminal) {
      var cmd = (app.command || []).filter(w => !/^%[a-zA-Z]$/.test(String(w)))
      Util.execDetached("omarchy-launch-tui " + cmd.map(w => Util.shellQuote(w)).join(" "))
    } else Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(app.id + ".desktop"))
  }

  // --- open windows, by workspace --------------------------------------------

  property var clients: []
  property var workspaces: []
  property var docked: ({})   // window address -> {dock, app, edge}: in an omext dock
  property string activeAddress: ""

  // [{title, sub, windows}] — workspaces in order, then each dock's windows,
  // then the rest (the scratchpad, ...).
  readonly property var windowGroups: {
    var byWs = {}, groups = [], monitors = {}
    for (var w of workspaces) monitors[w.monitor] = true
    var many = Object.keys(monitors).length > 1
    var needle = query.toLowerCase()
    for (var c of clients) {
      if (!c.mapped || c.hidden && !docked[c.address]) continue
      if (needle && (c.title + " " + c.class).toLowerCase().indexOf(needle) < 0) continue
      var d = docked[c.address]
      var key, title, order, sub = ""
      if (d) { key = "dock:" + d.dock; title = "Dock (" + d.edge + ")"; order = 100000 }
      else if (c.workspace.id > 0) {
        key = "ws:" + c.workspace.id; title = "Workspace " + c.workspace.name; order = c.workspace.id
        if (many) sub = c.monitor >= 0 ? monitorName(c.monitor) : ""
      } else { key = "special:" + c.workspace.name; title = specialName(c.workspace.name); order = 200000 }
      if (!byWs[key]) { byWs[key] = { title: title, sub: sub, order: order, windows: [] }; groups.push(byWs[key]) }
      byWs[key].windows.push(c)
    }
    groups.sort((a, b) => a.order - b.order || a.title.localeCompare(b.title))
    for (var g of groups) g.windows.sort((a, b) => (a.at[0] - b.at[0]) || (a.at[1] - b.at[1]))
    return groups
  }
  readonly property int windowCount: { var n = 0; for (var g of windowGroups) n += g.windows.length; return n }
  function monitorName(id) {
    for (var w of workspaces) if (w.monitorID === id) return w.monitor
    return ""
  }
  function specialName(name) {
    var n = String(name || "").replace(/^special:?/, "")
    if (!n || n === "special") return "Scratchpad"
    return n.charAt(0).toUpperCase() + n.slice(1)
  }
  function windowIcon(c) {
    var e = appOfClass(c.class) || appOfClass(c.initialClass)
    return iconFor(e ? e.icon : "")
  }
  function windowName(c) {
    var e = appOfClass(c.class)
    return e ? e.name : c.class
  }
  // Goes to it (omext core's way: one in a dock, the dock opens on it; a
  // minimized one comes back onto the workspace in front of you first).
  function goTo(c) {
    root.close()
    if (coreWindows.item) coreWindows.item.goTo(c, docked[c.address] || null, null)
  }
  function closeWindow(c) {
    if (coreWindows.item) coreWindows.item.close(c)
    refreshSoon.restart()
  }

  function refreshWindows() {
    if (!clientsProc.running) clientsProc.running = true
    if (!dockProc.running) dockProc.running = true
  }
  Process {
    id: clientsProc
    command: ["bash", "-c", "printf '{\"clients\":%s,\"workspaces\":%s,\"active\":%s}' \"$(hyprctl clients -j)\" \"$(hyprctl workspaces -j)\" \"$(hyprctl activewindow -j)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var all = JSON.parse(text)
          root.clients = all.clients || []
          root.workspaces = all.workspaces || []
          root.activeAddress = all.active && all.active.address || ""
        } catch (e) {}
      }
    }
  }
  Process {
    id: dockProc
    command: ["bash", "-c", '[ -x "$0" ] && "$0" list || echo "{}"', root.dockTool]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = ({})
        try {
          for (var d of (JSON.parse(text).docks || []))
            for (var a of d.apps)
              if (a.address) out[a.address] = { dock: d.id, app: a.id, edge: d.edge }
        } catch (e) {}
        root.docked = out
      }
    }
  }
  Timer { id: refreshSoon; interval: 150; onTriggered: root.refreshWindows() }
  Connections {
    target: Hyprland
    enabled: root.opened
    function onRawEvent(event) {
      if (/^(openwindow|closewindow|movewindow|windowtitle|activewindow|workspace|createworkspace|destroyworkspace)/.test(event.name))
        refreshSoon.restart()
    }
  }

  // --- lists Omarchy fills in itself --------------------------------------------
  //
  // As in Omarchy's menu (shell/plugins/menu/Menu.qml, its providers): a script
  // lists `label\tvalue\tcurrent[\tenglish name]`, one row each; picking one
  // runs actionFor(value). Read again each time the list is opened.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "\uf031",
      actionFor: function(v) { return "omarchy-font-set " + Util.shellQuote(v) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      labelFor: function(v) { return ({ "power-saver": "Power Saver", "balanced": "Balanced", "performance": "Performance" })[v] || v },
      actionFor: function(v) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(v) }
    },
    "kernels": {
      script: "current=$(omarchy-kernel get 2>/dev/null); omarchy-kernel list 2>/dev/null | while read -r k; do [[ -z $k ]] && continue; printf '%s\\t%s\\t%s\\n' \"$k\" \"$k\" \"$current\"; done",
      icon: "\uf17c",
      actionFor: function(v) { return "omarchy-kernel set " + Util.shellQuote(v) }
    },
    "languages": {
      script: "current=$(omarchy-language 2>/dev/null); omarchy-language list 2>/dev/null | while IFS=$'\\t' read -r name code english; do [[ -z $code ]] && continue; printf '%s\\t%s\\t%s\\t%s\\n' \"$name\" \"$code\" \"$current\" \"$english\"; done",
      icon: "\uf1ab",
      actionFor: function(v) { return "omarchy-language " + Util.shellQuote(v) }
    }
  })
  property var providerRows: ({})   // menu id -> its rows (entries of our own)
  property string providerFor: ""    // the list being read
  function loadProvider(e) {
    var spec = providers[e.provider]
    if (!spec) return
    providerProc.running = false
    providerFor = e.id
    providerProc.spec = spec
    providerProc.command = ["bash", "-c", spec.script]
    providerProc.running = true
  }
  Process {
    id: providerProc
    property var spec: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var spec = providerProc.spec, id = root.providerFor, rows = [], n = 0
        if (!spec || !id) return
        for (var line of text.split("\n")) {
          if (!line.trim()) continue
          var parts = line.split("\t"), raw = parts[0] || "", value = parts[1] || raw, current = parts[2] || ""
          var label = spec.labelFor ? spec.labelFor(raw) : raw
          rows.push({ id: id + ".~" + (n++), parent: id, kind: "action", icon: spec.icon || "", iconFont: "",
                      label: label + (value === current ? " \u2713" : ""), title: "", target: "", description: parts[3] && parts[3] !== label ? parts[3] : "",
                      action: spec.actionFor(value), provider: "", aliases: [], searchTerms: [], when: "", checked: "", disabled: "" })
        }
        var next = Object.assign({}, root.providerRows)
        next[id] = rows
        root.providerRows = next
        root.providerFor = ""
      }
    }
  }

  // --- search -----------------------------------------------------------------

  property string query: ""
  readonly property var searchRows: {
    var q = query.trim()
    if (!q) return []
    var hits = []
    for (var id of itemOrder) {
      var e = items[id]
      if (!e || id === "root" || e.parent === "" || id === "apps") continue
      var shown = isShown(e) && !disabled(e)
      if (!shown || !MenuModel.matchesQuery(e, q, shown)) continue
      hits.push({ entry: e, score: MenuModel.searchScore(items, e, q), sub: [e.description, placeOf(e)].filter(t => !!t).join("  \u00b7  ") })
    }
    hits.sort((a, b) => a.score - b.score)  // Omarchy's order: lower is a better match
    // Apps first (what a search is most often for), the best names on top: one
    // that starts with what you typed, then one with a word that does, then the rest.
    var out = []
    var lq = q.toLowerCase()
    var found = apps.filter(a => (a.name + " " + (a.genericName || "") + " " + (a.keywords || []).join(" ")).toLowerCase().indexOf(lq) >= 0)
    function rank(a) {
      var n = a.name.toLowerCase()
      return n.indexOf(lq) === 0 ? 0 : n.split(/[\s\-_.]+/).some(w => w.indexOf(lq) === 0) ? 1 : n.indexOf(lq) >= 0 ? 2 : 3
    }
    found = found.map((a, i) => ({ a: a, r: rank(a), i: i })).sort((x, y) => x.r - y.r || x.i - y.i).map(x => x.a)
    if (found.length) {
      out.push({ head: "Apps" })
      out = out.concat(found.slice(0, 20).map(a => ({ app: a })))
    }
    if (hits.length) out.push({ head: "Menu" })
    out = out.concat(hits.slice(0, 40))
    if (windowsPlace === "left" && windowCount > 0) {  // no column of their own: here
      out.push({ head: "Open windows" })
      for (var g of windowGroups) for (var c of g.windows) out.push({ win: c })
    }
    return out
  }
  function placeOf(e) {  // where an entry is: "Appearance › Menu Bar"
    var names = [], id = e.parent
    while (id && id !== "root") { var p = entry(id); if (!p) break; names.unshift(p.label); id = p.parent }
    return names.join("  ›  ")
  }

  // --- doing things -----------------------------------------------------------

  function open_(id) {  // a section, or a submenu in it
    if (id === "notifications") { if (bellThere && notesPlace === "left") { settingsOpen = false; specialPage = ""; notesOpen = true }; return }
    var e = entry(id)
    if (!e) return
    specialPage = ""
    settingsOpen = false
    notesOpen = false
    if (e.provider && id !== "apps") loadProvider(e)
    path = id
    var top = id
    while (entry(top) && entry(top).parent !== "root") top = entry(top).parent
    section = top
    cursor = -1
    pageFlick.contentY = 0
  }
  function back() {
    if (trail.length > 1) open_(trail[trail.length - 2].id)
  }
  function activate(row) {
    if (!row) return
    if (row.win) { goTo(row.win); return }
    if (row.app) { launch(row.app); return }
    var e = row.entry
    if (!e || disabled(e)) return
    query = ""
    if (e.kind === "link") { open_(e.target); return }
    if (e.provider && !providers[e.provider]) {  // a list we can't fill in: Omarchy's menu, there
      root.close()
      Quickshell.execDetached(["omarchy-menu", "summon", e.id])
      return
    }
    if (e.kind === "menu") { open_(e.id); return }
    if (toggleOf(e)) {  // a switch: flipped in place, the menu stays open
      Util.execDetached(e.action)
      toggleRecheck.restart()
      return
    }
    root.close()
    Util.execDetached(e.action)
  }

  // Switches. Omarchy writes an on/off setting as two entries, one shown at a
  // time ("Hide Bar" / "Show Bar", "Window Gaps Off" / "On"): one row here, the
  // setting's name and a switch. The omarchy-extended on/off entries (with a
  // `checked` guard) are switches too.
  readonly property var toggleWords: /\s*\b(On|Off|Show|Hide|Enable|Disable)\b\s*/
  function toggleOf(e) {
    if (!e || e.kind !== "action" || !e.action) return null
    if (/^setup\.omext\./.test(e.id) && e.checked) return { name: e.label, on: checked(e) }
    var w = String(e.when || "").trim()
    if (!w || !toggleWords.test(e.label)) return null
    var other = w.indexOf("!") === 0 ? w.slice(1).trim() : "! " + w
    for (var id of itemOrder) {
      var o = items[id]
      if (!o || o === e || o.parent !== e.parent || o.action !== e.action) continue
      if (String(o.when || "").trim().replace(/^!\s*/, "! ") !== other.replace(/^!\s*/, "! ")) continue
      var m = e.label.match(toggleWords)
      var name = e.label.replace(toggleWords, " ").replace(/\s+/g, " ").trim()
      // The entry shown says what it would do: "Off"/"Hide" while the setting is on.
      return { name: name, on: /^(Off|Hide|Disable)$/.test(m[1]) }
    }
    return null
  }
  Timer { id: toggleRecheck; interval: 600; onTriggered: root.evaluateGuards() }

  // The keyboard: Up/Down through the middle's rows, Enter runs one.
  property int cursor: -1

  // --- the keyboard, beyond the left list -------------------------------------
  // Tab goes from area to area: the left list, each pane at the right
  // (favorites, open windows), the row at the foot (the gear, Lock, Power).
  // The arrows move within the area and Enter runs what's chosen. Typing is
  // always the search's, and takes the keyboard back to the list.
  property string kbArea: "list"
  property int kbIndex: 0
  // (The settings, open, are over the list and the panes: they are the area then.)
  readonly property int kbNotes: notesInView && notesRight.item ? notesRight.item.count : 0
  readonly property var kbAreas: (settingsOpen ? ["settings"] : ["list"].concat(rightItems.filter(k => k !== "notifications" || kbNotes > 0 || foldOf(k) || settingsFor === k))).concat(["foot"])
  // A pane's own settings open (its gear, or Ctrl + , there): the keyboard is
  // on their rows, as in the menu's settings.
  readonly property bool kbPaneSet: kbArea !== "" && settingsFor === kbArea
  onSettingsForChanged: { kbRow = null; kbRowAt = -1 }
  function kbRowRoot() { return settingsOpen ? settingsCol : kbArea === "favorites" ? favPane : kbArea === "windows" ? winPane : notePane }
  readonly property var kbFavs: favoriteRows.filter(r => !r.groupKey)
  readonly property var kbWins: { var o = []; for (var g of windowGroups) for (var w of g.windows) o.push(w); return o }
  // (root.powerRest: the name alone is an item's id further down.)
  readonly property var kbFoot: [{ kind: "gear" }].concat(root.powerLock.map(e => ({ kind: "power", entry: e })))
                                 .concat(root.powerOpen ? root.powerRest.map(e => ({ kind: "power", entry: e })) : []).concat([{ kind: "toggle" }])
  readonly property var kbList: kbArea === "favorites" ? kbFavs : kbArea === "windows" ? kbWins : kbArea === "foot" ? kbFoot
                              : kbArea === "notifications" ? Array.from({ length: kbNotes }, (x, i) => ({ note: i })) : []
  readonly property var kbCur: kbList.length ? kbList[Math.max(0, Math.min(kbList.length - 1, kbIndex))] : null
  readonly property string kbFavKey: kbArea === "favorites" && kbCur ? favKey(kbCur) : ""
  readonly property string kbWinAddr: kbArea === "windows" && kbCur ? String(kbCur.address || "") : ""
  readonly property string kbFootKind: kbArea === "foot" && kbCur ? String(kbCur.kind || "") : ""
  readonly property string kbFootId: kbArea === "foot" && kbCur && kbCur.entry ? kbCur.entry.id : ""
  onKbAreasChanged: if (kbAreas.indexOf(kbArea) < 0) kbArea = kbAreas[0]
  onSettingsOpenChanged: { kbRow = null; kbRowAt = -1; kbArea = settingsOpen ? "settings" : "list" }

  // The settings: their rows (every MenuRow showing there), a column after the
  // other, top to bottom. Up and Down step through them, Left and Right go to
  // the row beside in the other column, Enter is a click on the one chosen.
  property var kbRow: null
  property int kbRowAt: -1
  function kbRows() {
    var out = [], top = kbRowRoot()
    function walk(item) {
      for (var i = 0; i < item.children.length; i++) {
        var c = item.children[i]
        if (!c.visible) continue
        if (c.isMenuRow === true && c.height > 0) { var p = c.mapToItem(top, 0, 0); out.push({ item: c, x: p.x, y: p.y }) }
        else walk(c)
      }
    }
    walk(top)
    out.sort((a, b) => (Math.round(a.x / 40) - Math.round(b.x / 40)) || (a.y - b.y))
    return out
  }
  function kbRowPick(rows, at) {
    kbRowAt = Math.max(0, Math.min(rows.length - 1, at))
    kbRow = rows.length ? rows[kbRowAt].item : null
    if (!kbRow || !settingsOpen) return
    var y = rows[kbRowAt].y
    if (y < settingsFlick.contentY) settingsFlick.contentY = Math.max(0, y - 8)
    else if (y + kbRow.height > settingsFlick.contentY + settingsFlick.height) settingsFlick.contentY = y + kbRow.height - settingsFlick.height + 8
  }
  function kbRowMove(dx, dy) {
    var rows = kbRows()
    if (!rows.length) return
    if (kbRowAt < 0 || kbRowAt >= rows.length) { kbRowPick(rows, dy < 0 ? rows.length - 1 : 0); return }
    if (dy) { kbRowPick(rows, kbRowAt + dy); return }
    // The other column: the row nearest in height.
    var me = rows[kbRowAt], best = -1
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if ((dx > 0 ? r.x > me.x + 40 : r.x < me.x - 40) && (best < 0 || Math.abs(r.y - me.y) < Math.abs(rows[best].y - me.y))) best = i
    }
    if (best >= 0) kbRowPick(rows, best)
  }
  function kbRowClick() {
    if (!kbRow) return
    var at = kbRowAt
    kbRow.clicked()
    // (A setting changed can make its rows anew: the one at that place, then.)
    Qt.callLater(function() { if (root.settingsOpen && root.kbArea === "settings" || root.kbPaneSet) root.kbRowPick(root.kbRows(), at) })
  }
  // Something chosen with the keyboard, into view in the list it is in.
  function kbReveal(item, flick) {
    var y = item.mapToItem(flick.contentItem, 0, 0).y
    if (y < flick.contentY) flick.contentY = y
    else if (y + item.height > flick.contentY + flick.height) flick.contentY = y + item.height - flick.height
  }
  onKbFootIdChanged: powerHint = kbCur && kbCur.entry ? kbCur.entry.label : ""
  function kbGo(area) {
    kbIndex = 0
    kbArea = area
    // A pane folded away in a shared column: it opens.
    if (area !== "list" && area !== "foot" && area !== "settings" && foldOf(area) && rightOpenKey !== area) saveConfig({ rightOpen: area })
    kbShow()
  }
  function kbNextArea(d) {
    var a = kbAreas, i = Math.max(0, a.indexOf(kbArea))
    kbGo(a[(i + d + a.length) % a.length])
  }
  function kbMove(dx, dy) {
    if (kbArea === "settings" || kbPaneSet) { kbRowMove(dx, dy); return }
    var n = kbList.length
    if (!n) return
    var step
    if (kbArea === "foot") step = dx || dy
    else if (kbArea === "favorites" && favTiles) step = dx + dy * favFlow.perRow
    else if (dx < 0) { kbGo("list"); return }   // a list: Left is back to the menu
    else step = dy
    kbIndex = Math.max(0, Math.min(n - 1, Math.min(kbIndex, n - 1) + step))
    kbShow()
  }
  function kbShow() {   // what's chosen, in view
    if (kbArea !== "favorites" || !kbCur) return
    var rep = favTiles ? favTileRep : favListRep, flick = favTiles ? favTileFlick : favListFlick
    var key = kbFavKey, at = favoriteRows.findIndex(r => !r.groupKey && favKey(r) === key)
    var item = at >= 0 ? rep.itemAt(at) : null
    if (!item) return
    if (item.y < flick.contentY) flick.contentY = item.y
    else if (item.y + item.height > flick.contentY + flick.height) flick.contentY = item.y + item.height - flick.height
  }
  function kbActivate() {
    if (kbArea === "settings" || kbPaneSet) { kbRowClick(); return }
    var it = kbCur
    if (!it) return
    if (kbArea === "notifications") { if (notesRight.item) notesRight.item.activateChosen() }
    else if (kbArea === "favorites") activate(it)
    else if (kbArea === "windows") goTo(it)
    else if (it.kind === "gear") { if (settingsOpen) settingsOpen = false; else openSettings() }
    else if (it.kind === "toggle") { powerOpen = !powerOpen; kbIndex = kbFoot.length - 1 }   // (still on Power: the rest open before it)
    else activate({ entry: it.entry })
  }
  // Ctrl + D: the chosen app's star, on or off.
  function kbStar() {
    var k = kbArea === "favorites" ? kbFavKey : kbArea === "list" && cursor >= 0 ? favKey(pickable[cursor]) : ""
    if (k) toggleFav(k)
  }
  readonly property var pickable: pageRows.filter(r => !r.head)
  // A row by what it is (the rows are made anew when the guards come back).
  function rowKey(r) { return !r ? "" : r.win ? "w:" + r.win.address : r.entry ? "e:" + r.entry.id : r.app ? "a:" + r.app.id : "" }
  // What a row is as a favorite ("" : it can't be one: a window, a row of a list Omarchy fills in).
  function favKey(r) { return !r || r.win || r.head ? "" : r.app ? "a:" + r.app.id : r.entry && r.entry.id.indexOf(".~") < 0 ? "e:" + r.entry.id : "" }
  readonly property string cursorKey: cursor >= 0 && cursor < pickable.length ? rowKey(pickable[cursor]) : ""
  onQueryChanged: { cursor = query.trim() ? 0 : -1; pageFlick.contentY = 0 }
  function moveCursor(d) {
    if (!pickable.length) return
    cursor = Math.max(0, Math.min(pickable.length - 1, cursor < 0 ? (d > 0 ? 0 : pickable.length - 1) : cursor + d))
    var key = rowKey(pickable[cursor])
    var item = pageRepeater.itemAt(pageRows.findIndex(r => rowKey(r) === key))
    if (item) {
      if (item.y < pageFlick.contentY) pageFlick.contentY = item.y
      else if (item.y + item.height > pageFlick.contentY + pageFlick.height)
        pageFlick.contentY = item.y + item.height - pageFlick.height
    }
  }

  // What the next open shows: a section (or a submenu), and a search.
  property string pendingPath: ""
  property string pendingQuery: ""
  onOpenedChanged: if (!opened) { kbArea = "list"; notesOpen = false; powerOpen = false; settingsFor = ""; headHint = ""; favDragKey = ""; paneDragKey = ""; if (notesInView && bellHistory.item) bellHistory.item.markSeen() } else {
    settingsOpen = false
    removeApp = null
    var want = pendingPath === "notifications" && bellThere && notesPlace === "left" ? pendingPath
             : pendingPath && entry(pendingPath) ? pendingPath : section && entry(section) ? section : "apps"
    if (!pendingPath && (specialPage === "favorites" && favPlace === "left" || specialPage === "windows" && windowsPlace === "left" || specialPage === "recent" && recentOn)) openSpecial(specialPage)
    else open_(want)
    search.text = pendingQuery
    query = pendingQuery
    pendingPath = ""; pendingQuery = ""
    refreshWindows()
    evaluateGuards()
  }
  function openAt(where, text) {
    if (low) placeLow()
    // A page of Start's own: "favorites", "windows" (when it's in the left menu).
    if (where === "favorites" && favPlace === "left" || where === "windows" && windowsPlace === "left" || where === "recent" && recentOn) {
      specialPage = where
      if (opened) { openSpecial(where); search.text = text || "" }
      else { pendingPath = ""; pendingQuery = text || ""; open() }
      return
    }
    // A route as Omarchy's menu takes it: an id, or an alias ("power", "theme").
    var id = where ? MenuModel.resolveRoute(items, itemOrder, where) : ""
    if (id === "root") id = ""
    var e = id ? entry(id) : null
    if (e && !isMenu(e) && !e.provider) id = e.parent === "root" ? "" : (e.parent || "")  // an entry: the page it's on
    settingsOpen = false
    if (opened) { open_(id || section); search.text = text || ""; return }
    pendingPath = id; pendingQuery = text || ""
    open()
  }

  // omarchy-shell omext.start open|close|toggle|settings|on|off, page <id or alias> (a section
  // or a submenu: appearance, setup.power, power, ...), find <text>.
  // There's a Start on every screen's bar, and only one of them gets these: it
  // passes them on to all through a file, and the one on the focused screen
  // opens (an open one anywhere closes).
  ShellIpc {
    target: "omext.start"
    function open(): void { root.request("open", "") }
    function show(): void { root.request("open", "") }
    function close(): void { root.request("close", "") }
    function hide(): void { root.request("close", "") }
    function toggle(): void { root.request("toggle", "") }
    function page(id: string): void { root.request("page", id) }
    function find(text: string): void { root.request("find", text) }
    function settings(): void { root.request("settings", "") }
    // From omext taskbar's button: "<screen> <its left end> <how high it reaches> <how wide it is>".
    function taskbar(place: string): void { root.request("taskbar", place) }
    function on(): void { root.request("on", "") }
    function off(): void { root.request("off", "") }
  }
  property double lastRequest: 0
  function request(op, arg) {
    if (op === "on" || op === "off") setOff(op === "off")
    var r = { op: op, arg: arg, t: Date.now() }
    requestFile.setText(JSON.stringify(r))
    onRequest(r)
  }
  function onRequest(r) {
    if (!r || !r.t || r.t <= lastRequest || Date.now() - r.t > 3000) return
    lastRequest = r.t
    if (!opened) fromBar = false   // (asked for by the keys, a script or the taskbar's button: not the bar's)
    var win = button.QsWindow.window
    var mine = win && win.screen ? win.screen.name : ""
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : mine
    var here = mine === focused
    if (r.op === "on" || r.op === "off") { off = r.op === "off"; if (off) close(); return }
    if (off) return
    if (r.op === "taskbar") {
      var p = String(r.arg || "").split(" ")
      if (opened || p[0] !== mine) { close(); return }
      if (Number(p[1]) >= 0) lowX = Number(p[1])
      if (Number(p[2]) > 0) lowH = Number(p[2])
      if (Number(p[3]) > 0) lowW = Number(p[3])
      openAt("", "")
      return
    }
    if (r.op === "close") close()
    else if (r.op === "toggle") { if (opened) close(); else if (here) openAt("", "") }
    else if (!here) close()
    else if (r.op === "page") openAt(r.arg, "")
    else if (r.op === "find") openAt("", r.arg)
    else if (r.op === "settings") { openAt("", ""); openSettings() }
    else openAt("", "")
  }
  FileView {
    id: requestFile
    path: root.runtimeDir + "/omext-start-request.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.onRequest(JSON.parse(text())) } catch (e) {} }
  }

  // --- settings ------------------------------------------------------------------
  //
  // In ~/.config/omext/start.json, the same for every screen's Start:
  //   shortcut  hypr/start.lua binds it at every Hyprland (re)load: "SUPER + ALT + M"
  //             (the default), "SUPER + SPACE" (in place of Omarchy's menu), keys
  //             of your own, or "" (none: the bar button only)
  //   label     text after the icon on the bar, part of the button ("" none)
  //   padding   room on both sides of the button (false)
  //   size      the menu's: compact, default, large or xlarge
  //   omarchyMenu  with shortcut SUPER + SPACE: where Omarchy's menu goes
  //             ("SUPER + ALT + M", the default; keys of your own; "" none)
  //   recentOff  true: no Recent under Apps
  //   windowsOff, favoritesOff  true: not in the menu
  //   windows   where the open windows are: "right" (the default) or "left" (a
  //             page from the left menu)
  //   favorites where the favorites are: "left" (the default) or "right"
  //   favoriteList  the favorites, in order: "a:<app id>", "e:<menu id>", and
  //             "g:<name>" (a group's heading: what follows is in it)
  //   favoriteView  at the right: "tiles" (icons, the default) or "list"
  //   favoriteSort  "name": shown A to Z (no dragging); else in favoriteList's order
  //   notificationsOff  true: omext bell's notifications aren't in the menu
  //   notifications  where they are: "left" (a page, the default) or "right"
  //   replaceMenuButton  true: in the place of Omarchy's own menu button on the bar
  //   (Start on the taskbar, hiding the bar's bell and Omarchy's dock off are
  //   choices that cross addons: in omext core's ~/.config/omext/omext.json.)
  //   rightOrder  the order of those at the right: ["favorites", "windows", "notifications"]
  //   ownColumn  {favorites, windows, notifications}: true, a column of its own at
  //             the right; false, it shares one with the others that don't
  //   rightColumns  (before ownColumn) "separate": all three their own; "combined" (one column, one
  //             open at a time: rightOpen) or "separate" (a column each)
  readonly property string defaultShortcut: "SUPER + ALT + M"
  // (Read, watched and written by omext core's Settings.)
  Loader { id: coreOwn; Component.onCompleted: setSource("file://" + root.coreDir + "/Settings.qml", { name: "start" }) }
  readonly property var config: coreOwn.item ? coreOwn.item.values : ({})
  readonly property string shortcut: typeof config.shortcut === "string" ? config.shortcut : defaultShortcut
  readonly property string barLabel: typeof config.label === "string" ? config.label : setting("label", "")
  readonly property bool padded: config.padding === true
  // The menu's size (never more than the screen has room for).
  readonly property var sizes: ({
    compact: { label: "Compact", mid: 400, right: 330, height: 600 },
    default: { label: "Default", mid: 440, right: 340, height: 660 },
    large:   { label: "Large", mid: 500, right: 370, height: 740 },
    xlarge:  { label: "Extra large", mid: 580, right: 400, height: 840 }
  })
  readonly property string sizeName: sizes[config.size] ? config.size : "default"
  // Where the open windows and the favorites are (Settings): a column at the
  // menu's right ("right"), a page from the left menu ("left"), or nowhere
  // ("off"). With nothing at the right, the menu is that much narrower.
  readonly property string windowsPlace: config.windowsOff === true || config.windows === false || config.windows === "off" ? "off" : config.windows === "left" ? "left" : "right"
  readonly property string favPlace: config.favoritesOff === true || config.favorites === "off" ? "off" : config.favorites === "right" ? "right" : "left"
  readonly property int leftCols: 210   // the left menu's width
  // Notifications (with omext bell): the same three places.
  readonly property string notesPlace: config.notificationsOff === true || config.notifications === "off" ? "off" : config.notifications === "right" ? "right" : "left"
  // Their own settings, in place of the list (the gear on their heading).
  // (For each of the three: "notifications", "favorites", "windows"; "": none open.)
  property string settingsFor: ""
  // The page of Start's own in the middle, if one is: its heading has the gear too.
  readonly property string pageKind: query || settingsOpen ? "" : notesOpen ? "notifications" : specialPage === "recent" ? "" : specialPage
  function placeOf_(kind) { return kind === "notifications" ? notesPlace : kind === "favorites" ? favPlace : windowsPlace }
  function setPlace(kind, v) {
    // Its settings stay open, where it now is.
    if (v === "left") {
      if (kind === "notifications") { specialPage = ""; settingsOpen = false; notesOpen = true }
      else openSpecial(kind)
    } else if (pageKind === kind) open_(section)
    var patch = { rightOpen: v === "right" ? kind : config.rightOpen }
    patch[kind] = v
    saveConfig(patch)
  }
  onNotesPlaceChanged: if (notesOpen && notesPlace !== "left") open_(section)
  // What's at the menu's right, in order. Each in a column of its own
  // (rightColumns "separate"), or all in one (the default): then one is open
  // at a time, and a click on another's heading opens that one (rightOpen).
  // (In your order: rightOrder, changed by dragging their headings.)
  readonly property var rightOrder: {
    var all = ["favorites", "windows", "notifications"]
    var o = (Array.isArray(config.rightOrder) ? config.rightOrder : []).filter((k, i, a) => all.indexOf(k) >= 0 && a.indexOf(k) === i)
    for (var k of all) if (o.indexOf(k) < 0) o.push(k)
    return o
  }
  readonly property var rightItems: {
    var here = { favorites: favPlace === "right", windows: windowsPlace === "right", notifications: notesPlace === "right" && bellThere }
    return rightOrder.filter(k => here[k])
  }
  // A heading dragged onto another one's place takes it (the rest move along).
  property string paneDragKey: ""
  property string paneDropKey: ""
  function paneUnder(item, x, y) {   // whose pane the pointer is over, from a heading's own coordinates
    var p = item.mapToItem(body, x, y)
    for (var k of rightItems) {
      var px = body.paneX(k), py = body.paneY(k)
      if (p.x >= px && p.x < px + panel.colW && p.y >= py && p.y < py + body.paneH(k)) return k
    }
    return ""
  }
  function movePane(kind, onto) {
    if (!onto || onto === kind) return
    var o = rightOrder.slice(), b = o.indexOf(onto)
    o.splice(o.indexOf(kind), 1)
    o.splice(b, 0, kind)
    saveConfig({ rightOrder: o })
  }
  // Each one either has a column of its own or shares one with the others that
  // don't (ownColumn: {favorites, windows, notifications}; rightColumns
  // "separate", from before, is all three). The shared column shows one at a
  // time. Where the screen has no room for the columns asked for: all in one.
  function ownColumn(k) {
    var o = config.ownColumn
    return o && typeof o[k] === "boolean" ? o[k] : config.rightColumns === "separate"
  }
  // Sharing takes two: one left alone in the shared column has a column of its
  // own all the same, so the switches say so, and are kept in step.
  function ownShown(k) {
    return ownColumn(k) || rightItems.filter(x => !ownColumn(x)).length < 2
  }
  function setOwnColumn(k) {   // k: a column of its own
    var o = { favorites: ownShown("favorites"), windows: ownShown("windows"), notifications: ownShown("notifications") }
    o[k] = true
    var alone = rightItems.filter(x => !o[x])
    if (alone.length === 1) o[alone[0]] = true   // the last one sharing: its own too
    saveConfig({ ownColumn: o })
  }
  // k shares a column with `mate`: it joins the ones mate shares with, or the
  // two of them leave the rest to their own.
  function shareColumn(k, mate) {
    var o = { favorites: ownShown("favorites"), windows: ownShown("windows"), notifications: ownShown("notifications") }
    if (o[mate]) for (var x in o) o[x] = true
    o[k] = false; o[mate] = false
    saveConfig({ ownColumn: o })
  }
  function sharesWith(k, mate) { return !ownShown(k) && !ownShown(mate) && rightItems.indexOf(mate) >= 0 }
  function paneName(k) { return k === "favorites" ? "Favorites" : k === "windows" ? "Open windows" : "Notifications" }
  readonly property var wantColumns: {   // [[key, ...], ...], left to right
    var cols = [], shared = null
    for (var k of rightItems) {
      if (ownColumn(k)) cols.push([k])
      else if (shared) shared.push(k)
      else { shared = [k]; cols.push(shared) }
    }
    return cols
  }
  readonly property var rightColumns: wantColumns.length > 1 && !panel.roomForEach ? [rightItems] : wantColumns
  readonly property int rightCols: rightColumns.length
  function colOf(k) { for (var i = 0; i < rightColumns.length; i++) if (rightColumns[i].indexOf(k) >= 0) return i; return -1 }
  function groupOf(k) { var i = colOf(k); return i < 0 ? [] : rightColumns[i] }
  function foldOf(k) { return groupOf(k).length > 1 }   // shares its column: a heading to click
  // The one open in the shared column.
  readonly property string rightOpenKey: {
    for (var g of rightColumns) if (g.length > 1) return g.indexOf(config.rightOpen) >= 0 ? config.rightOpen : g[0]
    return ""
  }
  function openOf(k) { return !foldOf(k) || rightOpenKey === k }
  readonly property bool notesInView: rightItems.indexOf("notifications") >= 0 && openOf("notifications")
  onWindowsPlaceChanged: if (specialPage === "windows" && windowsPlace !== "left") open_(section)
  onFavPlaceChanged: if (specialPage === "favorites" && favPlace !== "left") open_(section)

  // Favorites, in your order: "a:<app id>" (an app) or "e:<menu id>" (a menu
  // entry). A row's star adds or removes one.
  readonly property var favorites: Array.isArray(config.favoriteList) ? config.favoriteList : []
  function isFav(key) { return !!key && favorites.indexOf(key) >= 0 }
  function toggleFav(key) {
    if (!key) return
    var f = favorites.slice(), i = f.indexOf(key)
    if (i >= 0) f.splice(i, 1)
    else {
      // A new one is in no group: after the others that aren't, before the
      // first group's heading (at the end, it would be in the last group).
      var g = f.findIndex(k => String(k).indexOf("g:") === 0)
      if (g < 0) f.push(key); else f.splice(g, 0, key)
    }
    saveConfig({ favoriteList: f })
  }
  // Dragged: the favorite in hand, and the one it would land before ("": last).
  property string favDragKey: ""
  property string favDropBefore: ""
  property real favDropY: 0   // in the favorites' page: where the line is
  function moveFavBefore(key, before) {
    var f = favorites.slice(), i = f.indexOf(key)
    if (i < 0 || key === before) return
    f.splice(i, 1)
    var j = before ? f.indexOf(before) : -1
    if (j < 0) f.push(key); else f.splice(j, 0, key)
    if (f.join("\n") !== favorites.join("\n")) saveConfig({ favoriteList: f })
  }
  function moveFav(key, d) {
    var f = favorites.slice(), i = f.indexOf(key), j = i + d
    if (i < 0 || j < 0 || j >= f.length) return
    f.splice(i, 1); f.splice(j, 0, key)
    saveConfig({ favoriteList: f })
  }
  // [{head, groupKey} | {app|entry, fav}]: a "g:<name>" in the list is a group's
  // heading, and what follows it (up to the next) is in that group.
  readonly property var favoriteRows: {
    var _ = whenResults, out = [], part = []
    function nameOf(x) { return x.app ? x.app.name : x.entry.label }
    function flush() {
      if (favByName) part.sort((x, y) => nameOf(x).localeCompare(nameOf(y)))
      out = out.concat(part); part = []
    }
    for (var k of favorites) {
      var id = String(k).slice(2)
      if (String(k).indexOf("g:") === 0) { flush(); out.push({ head: id, groupKey: k }) }
      else if (String(k).indexOf("a:") === 0) { var a = apps.find(x => x.id === id); if (a) part.push({ app: a, fav: true }) }
      else { var e = entry(id); if (e && isShown(e)) part.push({ entry: e, fav: true, sub: placeOf(e) }) }
    }
    flush()
    return out
  }
  // A favorites' row by what it's kept as: a group's "g:<name>", or the favorite's key.
  function favRowKey(r) { return !r ? "" : r.groupKey || favKey(r) }
  function addGroup(name) {
    name = String(name || "").trim().slice(0, 40)
    if (!name || favorites.indexOf("g:" + name) >= 0) return
    saveConfig({ favoriteList: favorites.concat(["g:" + name]) })
  }
  function removeGroup(key) { saveConfig({ favoriteList: favorites.filter(k => k !== key) }) }
  function renameGroup(key, name) {
    name = String(name || "").trim().slice(0, 40)
    if (!name || "g:" + name === key || favorites.indexOf("g:" + name) >= 0) return
    saveConfig({ favoriteList: favorites.map(k => k === key ? "g:" + name : k) })
  }
  // Dragging over the favorites: which row the one in hand would land before,
  // from where the pointer is among a Repeater's items (tiles: in reading order).
  // (A group's heading in hand: only the headings show, and it lands before
  // another group or after the last, with all that's in it.)
  readonly property bool favGroupDrag: favDragKey.indexOf("g:") === 0
  function moveGroupBefore(key, before) {
    var f = favorites.slice(), i = f.indexOf(key)
    if (i < 0 || key === before) return
    var j = i + 1
    while (j < f.length && String(f[j]).indexOf("g:") !== 0) j++
    var part = f.splice(i, j - i)
    var at = before ? f.indexOf(before) : -1
    if (at < 0) at = f.length
    f = f.slice(0, at).concat(part, f.slice(at))
    if (f.join("\n") !== favorites.join("\n")) saveConfig({ favoriteList: f })
  }
  // Near the top or the bottom of what's in view, the list moves along under
  // the one in hand.
  property var favDragLast: null
  property int favDragScroll: 0
  Timer {
    interval: 16
    repeat: true
    running: root.favDragKey !== "" && root.favDragScroll !== 0 && root.favDragLast !== null
    onTriggered: {
      var a = root.favDragLast, f = a.flick
      var to = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), f.contentY + root.favDragScroll * 9))
      var by = to - f.contentY
      if (by === 0) return
      f.contentY = to
      root.favDragTo(a.key, a.rep, a.px, a.py + by, a.tiles, f)   // what's under the pointer now
    }
  }
  function favDragTo(key, rep, px, py, tiles, flick) {
    favDragLast = flick ? { key: key, rep: rep, px: px, py: py, tiles: tiles, flick: flick } : null
    var inView = flick ? py - flick.contentY : 0
    favDragScroll = !flick ? 0 : inView < 30 ? -1 : inView > flick.height - 30 ? 1 : 0
    var rows = favoriteRows, before = "", line = 0, group = String(key).indexOf("g:") === 0
    for (var i = 0; i < rows.length; i++) {
      var it = rep.itemAt(i)
      if (!it || group && !rows[i].groupKey) continue
      if (group) tiles = false   // headings alone: one under the other
      line = it.y + it.height
      if (tiles ? py < it.y + it.height && (py < it.y || px < it.x + it.width / 2) : py < it.y + it.height / 2) {
        before = favRowKey(rows[i]); line = it.y
        break
      }
    }
    favDragKey = key; favDropBefore = before; favDropY = line
  }
  function favDrop() {
    var k = favDragKey, b = favDropBefore
    favDragKey = ""
    favDragScroll = 0; favDragLast = null
    if (!k) return
    if (String(k).indexOf("g:") === 0) moveGroupBefore(k, b)
    else moveFavBefore(k, b)
  }
  readonly property bool favTiles: config.favoriteView !== "list"   // at the right: icons, or a list
  // A to Z (favoriteSort "name"), or in your own order, dragged (the default).
  readonly property bool favByName: config.favoriteSort === "name"
  // The open windows as rows (the left menu's page): [{head}|{win}].
  readonly property var windowRows: {
    var out = []
    for (var g of windowGroups) {
      out.push({ head: g.title + (g.sub ? "  \u00b7  " + g.sub : "") })
      for (var c of g.windows) out.push({ win: c })
    }
    return out
  }
  // A page of Start's own, from the left menu: "favorites", "windows" ("": none).
  property string specialPage: ""
  property string headHint: ""
  property var headHintFrom: null
  property real headHintX: 0   // in the menu's body: the name's right edge, and its top
  property real headHintY: 0
  function showHint(item, text) {
    if (!text) { if (headHintFrom === item) { headHint = ""; headHintFrom = null }; return }
    var p = item.mapToItem(body, item.width, item.height)
    headHintX = p.x; headHintY = p.y + 6
    headHintFrom = item
    headHint = text
  }
  function refocus() { search.forceActiveFocus() }   // typing goes on searching (for the components above the menu, which can't see it)
  function openSpecial(which) {
    settingsOpen = false; notesOpen = false
    specialPage = which
    path = section && entry(section) ? section : "apps"
    cursor = -1
    pageFlick.contentY = 0
  }
  // With Start on Super + Space, Omarchy's menu moves: to Start's own default
  // keys (a swap, the default), keys of your own, or none ("": right click only).
  readonly property bool tookSpace: shortcut === "SUPER + SPACE"
  readonly property string menuKeys: typeof config.omarchyMenu === "string" ? config.omarchyMenu : defaultShortcut
  property bool settingsOpen: false

  // Notifications, with omext bell installed: its history, as on its bar
  // button (its own History and NotificationList, loaded from where it is).
  readonly property string bellDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/omext.bell"
  property bool bellThere: false
  property bool notesOpen: false
  onNotesOpenChanged: if (!notesOpen && bellHistory.item) bellHistory.item.markSeen()
  FileView {
    path: root.bellDir + "/NotificationList.qml"
    watchChanges: true
    printErrors: false
    onLoaded: root.bellThere = true
    onLoadFailed: root.bellThere = false
    onFileChanged: reload()
  }
  Loader {
    id: bellHistory
    active: root.bellThere
    source: active ? "file://" + root.bellDir + "/History.qml" : ""
  }
  readonly property int bellUnread: bellHistory.item ? bellHistory.item.unread : 0

  // With omext taskbar installed, Start can sit at the taskbar's left end in
  // place of its bar button (Settings › Bar button › On the taskbar). The menu
  // then opens above the taskbar, centred on the screen, as high as the taskbar
  // says it reaches when its button is clicked (or did last time, for the keys).
  readonly property bool taskbarThere: taskbarOn
  readonly property bool onTaskbar: taskbarOn && shared.startOnTaskbar === true
  // On the bar: not on the taskbar, or there too, in the place of Omarchy's
  // own menu button (a button in both places then).
  readonly property bool onBar: !onTaskbar || tookMenuButton
  // This opening of the menu: from the bar's button (under it), or not (the
  // taskbar's button, the keys: above the taskbar, when Start is on it).
  property bool fromBar: false
  readonly property bool low: onTaskbar && !fromBar
  // Whether they're shown here, for omext bell (it leaves the bar only then).
  readonly property bool notesHere: notesPlace !== "off" && bellThere
  onNotesHereChanged: tellShared.restart()
  Connections { target: coreShared.item; function onReadyChanged() { tellShared.restart() } }
  Timer { id: tellShared; interval: 500; onTriggered: if (coreShared.item && coreShared.item.ready && root.shared.notificationsInStart !== root.notesHere) root.setShared({ notificationsInStart: root.notesHere }) }
  property real lowX: Style.space(12)   // the taskbar's left end, on this screen
  property real lowH: Style.space(64)   // and how far up from the bottom edge it reaches (with a gap above it)
  property real lowW: 0                 // and how wide it is: the menu leaves it to take its own clicks
  property real buttonX: 0              // the bar button's place, which the menu is reckoned from
  function placeLow() {
    var w = button.QsWindow.window
    buttonX = w && w.contentItem ? button.mapToItem(w.contentItem, 0, 0).x : 0
  }
  // The menu hangs off a bar; on the taskbar, this one: at the bottom, as tall
  // as the taskbar reaches. Opening and closing still go through the real one.
  QtObject {
    id: lowBar
    readonly property string position: "bottom"
    readonly property real barSize: root.lowH
    readonly property var activePopout: root.bar ? root.bar.activePopout : null
    readonly property var clickTargets: []
    function requestPopout(key) { if (root.bar) root.bar.requestPopout(key) }
    function releasePopout(key) { if (root.bar) root.bar.releasePopout(key) }
  }
  // The taskbar stays up under the open menu.
  readonly property bool holdTaskbar: opened && low
  onHoldTaskbarChanged: {
    var w = button.QsWindow.window
    Quickshell.execDetached(["omarchy-shell", "-q", "omext.taskbar", "hold", holdTaskbar && w && w.screen ? w.screen.name : ""])
  }
  property var binds: []  // Hyprland's, to tell what keys of your own would replace
  function normKeys(k) {
    return String(k || "").toUpperCase().split("+").map(x => x.trim()).filter(x => !!x).join(" + ")
  }
  function prettyKeys(k) {
    return normKeys(k).split(" + ").map(x => x.length > 1 ? x.charAt(0) + x.slice(1).toLowerCase() : x).join(" + ")
  }
  function setMenuKeys(k) { saveConfig({ omarchyMenu: normKeys(k) }) }
  Timer { id: bindsAgain; interval: 1200; onTriggered: if (!bindsProc.running) bindsProc.running = true }
  // A setting changed. Applied once whatever asked has finished: a change
  // can make the very row that was clicked anew, and the rest of its click
  // (the focus back to the search) would then have nothing to run in.
  property var pendingConfig: null
  function saveConfig(patch) {
    pendingConfig = Object.assign(pendingConfig || {}, patch)
    Qt.callLater(applyConfig)
  }
  function applyConfig() {
    var patch = pendingConfig
    if (!patch) return
    pendingConfig = null
    var keys = patch.shortcut !== undefined || patch.omarchyMenu !== undefined
    if (keys) bindsAgain.restart()  // after Hyprland's reload
    if (coreOwn.item) coreOwn.item.set(patch, keys ? "hyprctl reload >/dev/null" : "")
  }
  function setShortcut(k) { saveConfig({ shortcut: normKeys(k) }) }
  // What a key combination does now, other than Start: "" if nothing.
  function bindOf(k) {
    var mods = { SHIFT: 1, CAPS: 2, CTRL: 4, CONTROL: 4, ALT: 8, MOD2: 16, MOD3: 32, SUPER: 64, WIN: 64, LOGO: 64, MOD4: 64, MOD5: 128 }
    var parts = normKeys(k).split(" + "), mask = 0, key = ""
    for (var x of parts) { if (mods[x] !== undefined) mask |= mods[x]; else key = x }
    if (!key) return ""
    for (var b of binds)
      if (b.modmask === mask && String(b.key).toUpperCase() === key && b.description !== "Start menu"
          && !(b.description === "Omarchy menu" && root.tookSpace))
        return b.description || b.arg || b.dispatcher
    return ""
  }
  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.binds = JSON.parse(text) } catch (e) { root.binds = [] } } }
  }
  // --- what starts at login -----------------------------------------------------
  // One list (omext core's omext-startup): your own autostart entries, the
  // system's, and the omext docks' apps that start with their dock. A row's
  // switch turns one on or off; an app is added by its name.
  readonly property string startupTool: Quickshell.env("HOME") + "/.local/bin/omext-startup"
  property var startupItems: []
  property string startupQuery: ""
  readonly property var startupMatches: {
    var q = startupQuery.trim().toLowerCase()
    if (!q) return []
    var have = startupItems.map(e => e.id)
    return apps.filter(a => String(a.name).toLowerCase().indexOf(q) >= 0 && have.indexOf("user:" + a.id + ".desktop") < 0).slice(0, 5)
  }
  // Which app opens what (omext core's omext-defaults): a row per kind of
  // thing, the app that opens it now under its name; a click lists the apps
  // that can, and choosing one makes it the default. A file type of your own
  // choosing (.pdf) the same way.
  readonly property string defaultsTool: Quickshell.env("HOME") + "/.local/bin/omext-defaults"
  property var defaultKinds: []
  property string defaultOpen: ""     // the kind whose apps are listed
  property var defaultType: null      // the file type asked about
  function defaultsLoad() { defaultsProc.running = false; defaultsProc.running = true }
  function defaultsAsk(word) {
    defaultsTypeProc.running = false
    if (!word.trim()) { defaultType = null; return }
    defaultsTypeProc.command = [defaultsTool, "type", word.trim()]
    defaultsTypeProc.running = true
  }
  function defaultsSet(what, app) {
    Quickshell.execDetached([defaultsTool, "set", what, app])
    defaultsLater.restart()
  }
  function defaultsIcon(icon) {
    return !icon ? "" : icon.charAt(0) === "/" ? "file://" + icon : Quickshell.iconPath(icon, true)
  }
  Timer { id: defaultsLater; interval: 900; onTriggered: { root.defaultsLoad(); if (root.defaultType) root.defaultsAsk(defaultTypeInput.text) } }
  Timer { id: defaultsTypeLater; interval: 250; onTriggered: root.defaultsAsk(defaultTypeInput.text) }
  Process {
    id: defaultsProc
    command: [root.defaultsTool, "list"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.defaultKinds = JSON.parse(text) } catch (e) { root.defaultKinds = [] } }
    }
  }
  Process {
    id: defaultsTypeProc
    stdout: StdioCollector {
      onStreamFinished: { try { root.defaultType = JSON.parse(text) } catch (e) { root.defaultType = null } }
    }
  }
  function startupLoad() { startupProc.running = false; startupProc.running = true }
  function startupRun(args) {
    Quickshell.execDetached([startupTool].concat(args))
    startupLater.restart()
  }
  Timer { id: startupLater; interval: 900; onTriggered: root.startupLoad() }
  Process {
    id: startupProc
    command: [root.startupTool, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.startupItems = JSON.parse(text) } catch (e) { root.startupItems = [] } }
    }
  }

  function openSettings() {
    notesOpen = false
    settingsOpen = true
    startupQuery = ""
    startupLoad()
    defaultOpen = ""
    defaultsLoad()
    search.text = ""
    labelInput.text = barLabel
    menuOwnKeys.text = menuKeys && menuKeys !== defaultShortcut ? prettyKeys(menuKeys) : ""
    ownKeys.text = shortcut !== defaultShortcut && shortcut !== "SUPER + SPACE" && shortcut ? prettyKeys(shortcut) : ""
    if (!bindsProc.running) bindsProc.running = true
  }

  // Uninstalling an app (Delete on it, as in Omarchy's menu): asked first.
  property var removeApp: null
  property bool removeYes: false
  function askRemove(app) { removeApp = app; removeYes = false }
  function doRemove() {
    var a = removeApp
    removeApp = null
    if (!a) return
    root.close()
    Util.execDetached(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(a.id) + " " + Util.shellQuote(a.name))
  }

  Component.onCompleted: refreshWindows()

  // --- bar button ---------------------------------------------------------------

  implicitWidth: off || !onBar ? 0 : button.implicitWidth
  implicitHeight: off || !onBar ? 0 : button.implicitHeight
  visible: !off

  WidgetButton {
    id: button
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    visible: root.onBar
    bar: root.bar
    text: root.setting("icon", String.fromCodePoint(0xF0570)) + (root.barLabel ? "  " + root.barLabel : "")
    // Room on both sides, if asked for (Settings): wider, and all of it the button.
    readonly property real pad: root.padded && !vertical ? Style.spaceReal(10) : 0
    horizontalMargin: 8.5 + (root.padded ? 10 : 0)
    fixedWidth: pad > 0 && iconLabel ? Style.bar.iconSlot + pad * 2 : -1
    tooltipText: root.shortcut ? "Start (" + root.prettyKeys(root.shortcut) + ")" : "Start"
    onPressed: function(b) {
      if (b === Qt.RightButton) Util.execDetached("omarchy-menu")
      else { if (!root.opened) root.fromBar = true; root.toggle() }
    }
  }

  // --- the menu -------------------------------------------------------------------

  component Caption: Text {
    width: parent ? parent.width : 0
    leftPadding: 10
    topPadding: 10
    bottomPadding: 4
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
    elide: Text.ElideRight
  }

  // A row: an icon (a glyph, or an app's picture), a name, maybe a line under
  // it, and a › when it opens more.
  // One of the System entries along the bottom (Lock, Suspend, ...).
  component PowerButton: Rectangle {
    id: pb
    property var entry: null
    property bool compact: false   // the icon alone (its name shows beside the gear, pointed at)
    width: compact ? 36 : pbRow.implicitWidth + 22
    height: 32
    radius: 6
    readonly property bool chosen: !!entry && root.kbFootId === entry.id   // by the keyboard
    color: pbHit.containsMouse || chosen ? Commons.Util.alpha(/shutdown|reboot/.test(entry ? entry.id : "") ? Commons.Color.urgent : root.accent, 0.25) : "transparent"
    Row {
      id: pbRow
      anchors.centerIn: parent
      spacing: 7
      Text { anchors.verticalCenter: parent.verticalCenter; text: pb.entry ? pb.entry.icon : ""; color: root.text; font.family: pb.entry && pb.entry.iconFont || root.iconFont; font.pixelSize: 15 }
      Text { visible: !pb.compact; anchors.verticalCenter: parent.verticalCenter; text: pb.entry ? pb.entry.label : ""; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }
    MouseArea {
      id: pbHit; anchors.fill: parent; hoverEnabled: true
      onContainsMouseChanged: { var l = pb.entry ? pb.entry.label : ""; if (containsMouse) root.powerHint = l; else if (root.powerHint === l) root.powerHint = "" }
      onClicked: root.activate({ entry: pb.entry })
    }
  }

  // A pane's heading at the menu's right. Sharing one column, it's a button:
  // a click opens this pane (and so closes the one that was open).
  component PaneHead: Item {
    id: ph
    property string key: ""
    property string title: ""
    property string badge: ""
    z: 3                         // (their names show under it, over the pane's body)
    HoverHandler { id: phHov }
    readonly property bool fold: root.foldOf(key)
    readonly property bool isOpen: root.openOf(key)
    width: parent ? parent.width : 0
    height: 36
    Rectangle {
      visible: ph.fold
      anchors { fill: parent; bottomMargin: 4 }
      radius: 6
      color: phHit.containsMouse ? Commons.Util.alpha(root.text, 0.12) : ph.isOpen ? Commons.Util.alpha(root.accent, 0.14) : Commons.Util.alpha(root.text, 0.05)
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    Text {
      x: 10
      anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
      text: ph.title
      color: root.text
      font.family: root.fontFamily
      font.pixelSize: ph.fold ? Style.font.body : Style.font.title
      font.bold: true
    }
    Row {
      id: phRight
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
      spacing: 8
      Rectangle {
        visible: ph.badge !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(20, phBadge.implicitWidth + 10); height: 18; radius: 9
        color: Commons.Util.alpha(root.text, 0.1)
        Text { id: phBadge; anchors.centerIn: parent; text: ph.badge; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      }
      Text {
        visible: ph.fold
        anchors.verticalCenter: parent.verticalCenter
        text: ph.isOpen ? "\u{F0140}" : "\u{F0142}"
        color: root.dim
        font.family: root.iconFont
        font.pixelSize: 14
      }
    }
    opacity: root.paneDragKey === key ? 0.5 : 1
    Rectangle {  // another heading, dragged, would take this one's place
      visible: root.paneDragKey !== "" && root.paneDragKey !== ph.key && root.paneDropKey === ph.key
      anchors { fill: parent; bottomMargin: 4 }
      radius: 6
      color: "transparent"
      border.color: root.accent
      border.width: 2
    }
    MouseArea {  // a click opens it (sharing a column); a drag moves it among the others
      id: phHit
      anchors.fill: parent
      readonly property bool sortable: root.rightItems.length > 1
      enabled: ph.fold || sortable
      hoverEnabled: true
      cursorShape: ph.fold ? Qt.PointingHandCursor : Qt.ArrowCursor
      property real x0: 0
      property real y0: 0
      property bool drag: false
      onPressed: function(m) { x0 = m.x; y0 = m.y; drag = false }
      onPositionChanged: function(m) {
        if (!sortable || !pressed) return
        if (!drag && Math.abs(m.x - x0) + Math.abs(m.y - y0) <= 8) return
        drag = true
        root.paneDragKey = ph.key
        root.paneDropKey = root.paneUnder(ph, m.x, m.y)
      }
      onReleased: if (drag) { var k = ph.key, onto = root.paneDropKey; root.paneDragKey = ""; root.paneDropKey = ""; root.movePane(k, onto) }
      onCanceled: { drag = false; root.paneDragKey = ""; root.paneDropKey = "" }
      onClicked: { if (drag) { drag = false; return } if (ph.fold) root.saveConfig({ rightOpen: ph.key }); root.refocus() }
    }
    HeadTools {
      kind: ph.key
      shown: phHov.hovered
      anchors { right: phRight.left; rightMargin: 6; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
    }
  }

  // Notifications' heading, pointed at: Do Not Disturb, and clear them all.
  component HeadTools: Item {
    id: nt
    property string kind: ""   // whose heading: notifications', favorites', the windows'
    property bool shown: false
    readonly property var h: bellHistory.item
    property string hint: ""
    width: ntRow.implicitWidth
    height: ntRow.implicitHeight
    opacity: kind !== "" && (shown || kind === "notifications" && h && h.dnd || root.settingsFor === kind) ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
    // The one pointed at is named under the buttons: by the menu, over all of
    // it (here, the next heading in a shared column would lie over the name).
    onHintChanged: root.showHint(nt, hint)
    onVisibleChanged: if (!visible) root.showHint(nt, "")
    Row {
    id: ntRow
    spacing: 2
    Repeater {
      model: (nt.kind === "notifications" ? [
        { id: "dnd", glyph: "\u{F009B}", tip: nt.h && nt.h.dnd ? "Do Not Disturb is on" : "Do Not Disturb" },
        { id: "clear", glyph: "\u{F05E9}", tip: "Clear all" }
      ] : []).concat([{ id: "settings", glyph: "\u{F0493}", tip: nt.kind === "notifications" ? "Notification settings" : nt.kind === "favorites" ? "Favorites settings" : "Open windows settings" }])
      Rectangle {
        id: tb
        required property var modelData
        readonly property bool on: modelData.id === "dnd" ? !!nt.h && nt.h.dnd : modelData.id === "settings" && root.settingsFor === nt.kind
        visible: nt.shown || on
        width: 18; height: 18; radius: 5
        color: tbHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : on ? Commons.Util.alpha(root.accent, 0.18) : "transparent"
        Text { anchors.centerIn: parent; text: tb.modelData.glyph; color: tb.on ? root.accent : root.text; font.family: root.iconFont; font.pixelSize: 9 }
        MouseArea {
          id: tbHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: { if (containsMouse) nt.hint = tb.modelData.tip; else if (nt.hint === tb.modelData.tip) nt.hint = "" }
          onClicked: {
            if (tb.modelData.id === "settings") {
              var open = root.settingsFor !== nt.kind
              root.settingsFor = open ? nt.kind : ""
              // Closed in a shared column: opened, so its settings show.
              if (open && root.foldOf(nt.kind) && root.rightOpenKey !== nt.kind) root.saveConfig({ rightOpen: nt.kind })
            }
            else if (!nt.h) return
            else if (tb.modelData.id === "dnd") nt.h.toggleDnd()
            else nt.h.clearAll()
            root.refocus()
          }
        }
      }
    }
    }
  }

  // The notifications' own settings: where they are, and the bar's bell.
  component PaneSettings: Flickable {
    id: ps
    property string kind: ""
    readonly property var others: root.placeOf_(kind) === "right" ? root.rightItems.filter(k => k !== kind) : []
    contentHeight: nsCol.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    Column {
      id: nsCol
      width: parent.width - 10
      spacing: 2
      SetHead { first: true; text: "Where" }
      Repeater {
        model: [
          { v: "left", label: "In the left menu", sub: "A page" },
          { v: "right", label: "At the right", sub: ps.kind === "favorites" ? "As icons" : "Always in view" }
        ]
        MenuRow {
          required property var modelData
          readonly property bool on: root.placeOf_(ps.kind) === modelData.v
          glyph: on ? "\u25c9" : "\u25cb"
          glyphFont: root.fontFamily
          label: modelData.label
          sub: modelData.sub
          current: on
          onClicked: { root.setPlace(ps.kind, modelData.v); root.refocus() }
        }
      }
      SetHead { visible: ps.kind === "favorites" && root.favPlace === "right"; text: "Shown as" }
      Repeater {
        model: ps.kind !== "favorites" || root.favPlace !== "right" ? [] : [
          { v: "tiles", label: "Icons" },
          { v: "list", label: "A list" }
        ]
        MenuRow {
          required property var modelData
          readonly property bool on: root.favTiles === (modelData.v === "tiles")
          glyph: on ? "\u25c9" : "\u25cb"
          glyphFont: root.fontFamily
          label: modelData.label
          current: on
          onClicked: { root.saveConfig({ favoriteView: modelData.v }); root.refocus() }
        }
      }
      SetHead { visible: ps.kind === "favorites"; text: "Groups" }
      Row {
        visible: ps.kind === "favorites"
        x: 10
        spacing: 6
        Rectangle {
          width: Math.max(80, Math.min(220, nsCol.width - 10 - 66 - 12)); height: 30; radius: 6
          color: Commons.Util.alpha(root.text, 0.06)
          border.color: Commons.Util.alpha(root.accent, groupInput.activeFocus ? 0.8 : 0.3)
          TextInput {
            id: groupInput
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            color: root.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            clip: true
            maximumLength: 40
            Keys.onReturnPressed: { root.addGroup(text); text = ""; root.refocus() }
            Keys.onEnterPressed: { root.addGroup(text); text = ""; root.refocus() }
            Keys.onEscapePressed: { text = ""; root.refocus() }
            Text { visible: !groupInput.text; text: "A new group's name"; color: root.dim; font: groupInput.font; anchors.verticalCenter: parent.verticalCenter }
          }
        }
        Rectangle {
          width: 60; height: 30; radius: 6
          color: addHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : Commons.Util.alpha(root.text, 0.08)
          Text { anchors.centerIn: parent; text: "Add"; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          MouseArea { id: addHit; anchors.fill: parent; hoverEnabled: true; onClicked: { root.addGroup(groupInput.text); groupInput.text = ""; root.refocus() } }
        }
      }
      Text {
        visible: ps.kind === "favorites"
        x: 10
        width: nsCol.width - 20
        topPadding: 4
        wrapMode: Text.WordWrap
        text: "A group is a heading among the favorites. Drag favorites under it; drag the heading to move the whole group. Double click renames it."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      SetHead { visible: ps.kind === "favorites"; text: "Order" }
      Repeater {
        model: ps.kind !== "favorites" ? [] : [
          { v: "own", label: "Your own", sub: "Drag them where you want them" },
          { v: "name", label: "A to Z", sub: "By name, in each group" }
        ]
        MenuRow {
          required property var modelData
          readonly property bool on: root.favByName === (modelData.v === "name")
          glyph: on ? "\u25c9" : "\u25cb"
          glyphFont: root.fontFamily
          label: modelData.label
          sub: modelData.sub
          current: on
          onClicked: { root.saveConfig({ favoriteSort: modelData.v }); root.refocus() }
        }
      }
      // At the right, with others there: a column of its own, or one shared with
      // the one you pick (one open at a time).
      SetHead { visible: ps.others.length > 0; text: "Column" }
      MenuRow {
        visible: ps.others.length > 0
        height: visible ? rowHeight : 0
        glyph: root.ownShown(ps.kind) ? "\u25c9" : "\u25cb"
        glyphFont: root.fontFamily
        label: "Its own"
        current: root.ownShown(ps.kind)
        onClicked: { root.setOwnColumn(ps.kind); root.refocus() }
      }
      Repeater {
        model: ps.others
        MenuRow {
          required property string modelData
          readonly property bool on: root.sharesWith(ps.kind, modelData)
          glyph: on ? "\u25c9" : "\u25cb"
          glyphFont: root.fontFamily
          label: "With " + root.paneName(modelData)
          current: on
          onClicked: { root.shareColumn(ps.kind, modelData); root.refocus() }
        }
      }
      SetHead { visible: ps.kind === "notifications"; text: "On the bar" }
      MenuRow {
        visible: ps.kind === "notifications"
        height: visible ? 44 : 0
        glyph: "\u{F009B}"
        toggle: root.shared.hideBell === true ? 1 : 0
        label: "Hide the bar's bell"
        sub: "Only here"
        current: root.shared.hideBell === true
        onClicked: { root.setShared({ hideBell: root.shared.hideBell !== true }); root.refocus() }
      }
      MenuRow {
        glyph: "\u{F0156}"
        label: "Done"
        dimmed: true
        onClicked: { root.settingsFor = ""; root.refocus() }
      }
    }
  }

  // A group's heading among the favorites: dragged to where the group starts,
  // renamed with a double click (or its pencil), removed with its ✕ (what was in
  // it joins the group above).
  component GroupHead: Item {
    id: gh
    property string key: ""
    readonly property string name: key.slice(2)
    readonly property bool sortable: !root.favByName && !root.query
    property bool editing: false
    signal dragAt(real x, real y)
    signal dropped()
    width: parent ? parent.width : 0
    height: 30
    opacity: root.favDragKey === key ? 0.4 : 1
    HoverHandler { id: ghHov }
    Rectangle {
      anchors { left: ghName.right; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: ghName.verticalCenter }
      height: 1
      color: Commons.Util.alpha(root.text, 0.1)
    }
    Text {
      id: ghName
      visible: !gh.editing
      x: 10
      anchors { bottom: parent.bottom; bottomMargin: 5 }
      width: Math.min(implicitWidth, gh.width - 70)
      elide: Text.ElideRight
      text: gh.name
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.6
    }
    MouseArea {
      anchors.fill: parent
      enabled: !gh.editing
      preventStealing: gh.sortable
      property real x0: 0
      property real y0: 0
      property bool drag: false
      onPressed: function(m) { x0 = m.x; y0 = m.y; drag = false }
      onPositionChanged: function(m) {
        if (!gh.sortable || !pressed) return
        if (!drag && Math.abs(m.x - x0) + Math.abs(m.y - y0) <= 8) return
        drag = true
        gh.dragAt(m.x, m.y)
      }
      onReleased: if (drag) gh.dropped()
      onCanceled: if (drag) { drag = false; gh.dropped() }
      onDoubleClicked: gh.edit()
    }
    function edit() { editing = true; ghEdit.text = name; ghEdit.forceActiveFocus(); ghEdit.selectAll() }
    Rectangle {
      visible: gh.editing
      x: 6; width: parent.width - 12; height: 26; radius: 6
      anchors.bottom: parent.bottom
      color: Commons.Color.popups.background
      border.color: Commons.Util.alpha(root.accent, 0.8)
      TextInput {
        id: ghEdit
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        verticalAlignment: TextInput.AlignVCenter
        color: root.text
        selectionColor: Commons.Util.alpha(root.accent, 0.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        clip: true
        maximumLength: 40
        Keys.onReturnPressed: { var k = gh.key, t = text; gh.editing = false; root.refocus(); root.renameGroup(k, t) }
        Keys.onEnterPressed: { var k = gh.key, t = text; gh.editing = false; root.refocus(); root.renameGroup(k, t) }
        Keys.onEscapePressed: { gh.editing = false; root.refocus() }
        onActiveFocusChanged: if (!activeFocus) gh.editing = false
      }
    }
    Row {
      visible: ghHov.hovered && !gh.editing && root.favDragKey === ""
      anchors { right: parent.right; rightMargin: 6; bottom: parent.bottom; bottomMargin: 2 }
      Repeater {
        model: [{ id: "rename", g: "\u{F03EB}" }, { id: "remove", g: "\u{F0156}" }]
        Rectangle {
          id: gb
          required property var modelData
          width: 20; height: 18; radius: 5
          color: gbHit.containsMouse ? Commons.Util.alpha(gb.modelData.id === "remove" ? Commons.Color.urgent : root.accent, 0.4) : Commons.Color.popups.background
          Text { anchors.centerIn: parent; text: gb.modelData.g; color: root.text; font.family: root.iconFont; font.pixelSize: 10 }
          MouseArea {
            id: gbHit
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { if (gb.modelData.id === "rename") gh.edit(); else { var k = gh.key; root.refocus(); root.removeGroup(k) } }
          }
        }
      }
    }
  }

  // A group's heading in the settings: set apart from the group above by room
  // and a line.
  component SetHead: Item {
    id: sh
    property string text: ""
    property bool first: false   // the first in its column: nothing above to set it apart from
    width: parent ? parent.width : 0
    height: shText.implicitHeight + (first ? 4 : 22)
    Rectangle {
      visible: !sh.first
      x: 10; y: 9
      width: parent.width - 20; height: 1
      color: Commons.Util.alpha(root.text, 0.14)
    }
    Text {
      id: shText
      anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
      leftPadding: 10
      bottomPadding: 5
      text: sh.text
      color: Commons.Util.alpha(root.text, 0.8)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.8
      elide: Text.ElideRight
    }
  }

  component MenuRow: Rectangle {
    id: r
    property string glyph: ""
    property string glyphFont: ""
    property url image: ""
    property string label: ""
    property string sub: ""
    property bool more: false
    property int toggle: -1  // a switch: 0 off, 1 on (-1: not one)
    property bool current: false
    property bool selected: false
    readonly property bool isMenuRow: true          // (for the keyboard in the settings: see kbRows)
    readonly property bool kbChosen: root.kbRow === r
    property bool dimmed: false
    property bool closable: false
    property string badge: ""      // a count, at the row's right
    property int star: -1          // a favorite's star: 0 not one, 1 one (-1: no star)
    property bool movable: false   // up and down, beside the star (the favorites' page)
    signal clicked()
    signal closeClicked()
    signal starClicked()
    signal moved(int by)
    property bool draggable: false   // picked up and dragged up or down (a favorite)
    signal dragAt(real y)            // being dragged: the pointer, in the row
    signal dropped()
    HoverHandler { id: hov }
    property int rowHeight: 34
    width: parent ? parent.width : 0
    height: sub ? 44 : rowHeight
    radius: 6
    color: selected || kbChosen ? Commons.Util.alpha(root.accent, 0.22)
         : hit.containsMouse ? Commons.Util.alpha(root.text, 0.08)
         : current ? Commons.Util.alpha(root.text, 0.05) : "transparent"
    Rectangle {  // the current one: a bar at its left, as in Windows' lists
      visible: r.selected || r.current && !hit.containsMouse
      x: 0; width: 3; radius: 2
      height: parent.height * 0.5
      anchors.verticalCenter: parent.verticalCenter
      color: root.accent
    }
    Item {
      id: ic
      x: 10; width: 22; height: 22
      anchors.verticalCenter: parent.verticalCenter
      Image {
        anchors.fill: parent
        visible: r.image != ""
        source: r.image
        sourceSize: Qt.size(44, 44)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }
      Text {
        anchors.centerIn: parent
        visible: r.image == ""
        text: r.glyph
        color: r.selected || r.current ? root.accent : root.text
        opacity: r.dimmed ? 0.45 : 1
        font.family: r.glyphFont || root.iconFont
        font.pixelSize: 16
      }
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      x: ic.x + ic.width + 10
      width: r.width - x - (r.toggle >= 0 ? 50 + (r.badge ? badgeBox.width + 6 : r.closable ? 26 : 0) : r.more || r.closable ? 30 : r.badge ? badgeBox.width + 16 : 10)
      Text {
        width: parent.width
        text: r.label
        elide: Text.ElideRight
        color: r.selected ? root.accent : root.text
        opacity: r.dimmed ? 0.45 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        visible: !!r.sub
        width: parent.width
        text: r.sub
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    Rectangle {  // the switch
      visible: r.toggle >= 0
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
      width: 30; height: 16; radius: 8
      color: r.toggle === 1 ? Commons.Util.alpha(root.accent, 0.85) : Commons.Util.alpha(root.text, 0.18)
      Behavior on color { ColorAnimation { duration: 120 } }
      Rectangle {
        width: 12; height: 12; radius: 6
        anchors.verticalCenter: parent.verticalCenter
        x: r.toggle === 1 ? parent.width - width - 2 : 2
        Behavior on x { NumberAnimation { duration: 120 } }
        color: r.toggle === 1 ? Commons.Color.popups.background : root.text
      }
    }
    Rectangle {
      id: badgeBox
      visible: r.badge !== ""
      anchors { right: parent.right; rightMargin: r.toggle >= 0 ? 48 : 8; verticalCenter: parent.verticalCenter }
      width: Math.max(20, badgeText.implicitWidth + 10); height: 18; radius: 9
      color: Commons.Util.alpha(root.text, 0.1)
      Text { id: badgeText; anchors.centerIn: parent; text: r.badge; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    }
    Text {
      visible: r.more && !r.closable && r.toggle < 0
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
      text: "›"
      color: root.dim
      font.pixelSize: 18
    }
    MouseArea {
      id: hit; anchors.fill: parent; hoverEnabled: true
      acceptedButtons: Qt.LeftButton | (r.star >= 0 ? Qt.RightButton : 0)
      property real y0: 0
      property bool drag: false
      preventStealing: r.draggable
      onPressed: function(m) { y0 = m.y; drag = false }
      onPositionChanged: function(m) {
        if (!r.draggable || !pressed || !(pressedButtons & Qt.LeftButton)) return
        if (drag || Math.abs(m.y - y0) > 6) { drag = true; r.dragAt(m.y) }
      }
      onReleased: if (drag) r.dropped()
      onCanceled: if (drag) { drag = false; r.dropped() }
      onClicked: function(m) { if (drag) { drag = false; return } if (m.button === Qt.RightButton) r.starClicked(); else r.clicked() }
    }
    Text {  // a favorite, not pointed at: a small star
      visible: r.star === 1 && !hov.hovered && !r.movable
      anchors { right: parent.right; rightMargin: r.toggle >= 0 ? 50 : r.more ? 28 : 10; verticalCenter: parent.verticalCenter }
      text: "\u{F04CE}"
      color: Commons.Util.alpha(root.text, 0.3)
      font.family: root.iconFont
      font.pixelSize: 12
    }
    Rectangle {  // pointed at: the star (and, in the favorites, up and down)
      visible: r.star >= 0 && hov.hovered
      anchors { right: parent.right; rightMargin: r.toggle >= 0 ? 46 : r.more ? 24 : 6; verticalCenter: parent.verticalCenter }
      width: toolRow.implicitWidth + 4; height: 24; radius: 6
      color: Commons.Color.popups.background
      Row {
        id: toolRow
        anchors.centerIn: parent
        Repeater {
          model: [{ g: "", by: 0 }]
          Rectangle {
            id: tool
            required property var modelData
            width: 24; height: 22; radius: 5
            color: toolHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : "transparent"
            Text {
              anchors.centerIn: parent
              text: tool.modelData.by !== 0 ? tool.modelData.g : r.star === 1 ? "\u{F04CE}" : "\u{F04D2}"
              color: tool.modelData.by === 0 && r.star === 1 ? root.accent : root.text
              font.family: root.iconFont
              font.pixelSize: 14
            }
            MouseArea { id: toolHit; anchors.fill: parent; hoverEnabled: true; onClicked: { if (tool.modelData.by !== 0) r.moved(tool.modelData.by); else r.starClicked() } }
          }
        }
      }
    }
    Rectangle {  // closes the window (shown on hover)
      visible: r.closable && (hit.containsMouse || xHit.containsMouse)
      anchors { right: parent.right; rightMargin: r.toggle >= 0 ? 46 : 6; verticalCenter: parent.verticalCenter }
      width: 22; height: 22; radius: 5
      color: xHit.containsMouse ? Commons.Util.alpha(Commons.Color.urgent, 0.35) : Commons.Util.alpha(root.text, 0.08)
      Text { anchors.centerIn: parent; text: "✕"; color: root.text; font.pixelSize: 11 }
      MouseArea { id: xHit; anchors.fill: parent; hoverEnabled: true; onClicked: r.closeClicked() }
    }
  }

  // On the taskbar: what the menu is placed by, at the taskbar's left end
  // (the menu's middle is reckoned from it, its left edge lands there).
  Item {
    id: lowAnchor
    parent: button
    x: root.lowX + panel.contentWidth / 2 - root.buttonX
    width: 0; height: 0
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.low ? lowAnchor : button
    owner: root
    bar: root.low ? lowBar : root.bar
    centerOnBar: root.low   // from the taskbar: centred on the screen, above it
    // The whole screen takes the clicks that close it, but for the taskbar
    // (on it): its clicks are its own.
    mask: Region {
      width: panel.screenW
      height: panel.screenH
      Region {
        intersection: Intersection.Subtract
        x: root.lowX
        y: panel.screenH - root.lowH
        width: root.low ? root.lowW : 0
        height: root.lowH
      }
    }
    open: root.opened
    focusTarget: search
    readonly property var dims: root.sizes[root.sizeName] || root.sizes.default
    readonly property real leftW: Style.space(root.leftCols)
    readonly property real midW: Style.space(dims.mid)
    // A column at the right: as wide as the size has it, or, on a screen with
    // no room for that beside the list (a small one, or a large scale), what
    // room there is (never over the list).
    readonly property real colWide: Style.space(dims.right)
    readonly property real fitW: panel.fittedContentWidth(100000)
    readonly property real colW: Math.min(colWide, Math.max(Style.space(120), (fitW - 2 * Style.space(14) - leftW - Style.space(200)) / Math.max(1, root.rightCols)))
    readonly property real wideW: leftW + midW + colWide * root.wantColumns.length + 2 * Style.space(14)
    readonly property bool roomForEach: panel.fittedContentWidth(wideW) >= wideW - 1
    readonly property real rightW: colW * root.rightCols
    contentWidth: panel.fittedContentWidth(leftW + midW + rightW + 2 * Style.space(14))
    contentHeight: panel.fittedContentHeight(Style.space(dims.height))

    Item {
      anchors.fill: parent

      // Search: the menu, apps and open windows.
      Rectangle {
        id: searchBox
        width: parent.width
        height: 38
        radius: 8
        color: Commons.Util.alpha(root.text, 0.06)
        border.color: Commons.Util.alpha(root.accent, search.activeFocus ? 0.8 : 0.3)
        Text {
          id: glass
          x: 12
          anchors.verticalCenter: parent.verticalCenter
          text: String.fromCodePoint(0xF0349)
          color: root.dim
          font.family: root.iconFont
          font.pixelSize: 16
        }
        TextInput {
          id: search
          anchors { left: glass.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
          color: root.text
          selectionColor: Commons.Util.alpha(root.accent, 0.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          clip: true
          onTextChanged: { root.query = text; if (text) root.kbArea = "list" }
          Text {
            visible: !search.text
            text: root.windowsPlace !== "off" ? "Search the menu, apps and open windows" : "Search the menu and apps"
            color: root.dim
            font: search.font
          }
          // As Omarchy's menu: Up/Down (PageUp/PageDown: six), Enter or Right
          // runs or opens, Left or Backspace goes back, Delete uninstalls an
          // app, Esc clears the search, then goes back, then closes. Tab goes
          // to the next area (see kbArea), Ctrl + Tab to the next section, and
          // Ctrl + D stars the chosen app.
          Keys.onPressed: function(event) {
            var key = Util.readingKey(event)
            if (root.removeApp) {  // the question: Left/Right/Tab between its buttons
              if (key === Qt.Key_Left || key === Qt.Key_Right || key === Qt.Key_Tab || key === Qt.Key_Backtab) root.removeYes = !root.removeYes
              else if (key === Qt.Key_Return || key === Qt.Key_Enter) { if (root.removeYes) root.doRemove(); else root.removeApp = null }
              else if (key === Qt.Key_Escape) root.removeApp = null
              event.accepted = true
              return
            }
            var ctrl = !!(event.modifiers & Qt.ControlModifier)
            if (ctrl && key === Qt.Key_D) { root.kbStar(); event.accepted = true; return }
            if (ctrl && key === Qt.Key_Comma) {  // settings: the pane's the keyboard is in, else the menu's
              if (root.rightItems.indexOf(root.kbArea) >= 0) root.settingsFor = root.settingsFor === root.kbArea ? "" : root.kbArea
              else if (root.settingsOpen) root.settingsOpen = false
              else root.openSettings()
              event.accepted = true
              return
            }
            if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
              var back = key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier)
              if (ctrl) {  // the next section (Tab alone: the next area)
                var si = root.sections.findIndex(s => s.id === root.section)
                var sn = root.sections[(si + (back ? -1 : 1) + root.sections.length) % root.sections.length]
                if (sn) { search.text = ""; root.kbArea = "list"; root.open_(sn.id) }
              } else root.kbNextArea(back ? -1 : 1)
              event.accepted = true
              return
            }
            if (root.kbArea !== "list") {  // in a pane at the right, or at the foot
              if (key === Qt.Key_Down) root.kbMove(0, 1)
              else if (key === Qt.Key_Up) root.kbMove(0, -1)
              else if (key === Qt.Key_Left) root.kbMove(-1, 0)
              else if (key === Qt.Key_Right) root.kbMove(1, 0)
              else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.kbActivate()
              else if (key === Qt.Key_Delete && root.kbArea === "notifications") { if (notesRight.item) notesRight.item.hideChosen() }
              else if (root.kbArea === "settings" && (key === Qt.Key_Escape || key === Qt.Key_Backspace && !search.text)) root.settingsOpen = false
              else if (key === Qt.Key_Escape && root.kbPaneSet) root.settingsFor = ""
              else if (key === Qt.Key_Escape) root.kbArea = "list"
              else return  // a letter: the search's (which takes the keyboard back to the list)
              event.accepted = true
              return
            }
            var row = root.cursor >= 0 ? root.pickable[root.cursor] : null
            if (key === Qt.Key_Down) { root.moveCursor(1); event.accepted = true }
            else if (key === Qt.Key_Up) { root.moveCursor(-1); event.accepted = true }
            else if (key === Qt.Key_PageDown) { root.moveCursor(6); event.accepted = true }
            else if (key === Qt.Key_PageUp) { root.moveCursor(-6); event.accepted = true }
            else if (key === Qt.Key_Delete && row && row.app) { root.askRemove(row.app); event.accepted = true }
            else if (key === Qt.Key_Return || key === Qt.Key_Enter
                     || key === Qt.Key_Right && row && search.cursorPosition === search.text.length) {
              if (row) root.activate(row)
              else root.moveCursor(1)
              event.accepted = true
            } else if (key === Qt.Key_Escape) {
              if (search.text) search.text = ""
              else if (root.settingsOpen) root.settingsOpen = false
              else if (root.notesOpen) root.open_(root.section)
              else if (!root.specialPage && root.trail.length > 1) root.back()
              else root.close()
              event.accepted = true
            } else if ((key === Qt.Key_Backspace || key === Qt.Key_Left) && !search.text && (!root.specialPage && root.trail.length > 1 || root.settingsOpen || root.notesOpen)) {
              if (root.settingsOpen) root.settingsOpen = false
              else if (root.notesOpen) root.open_(root.section)
              else root.back()
              event.accepted = true
            }
          }
        }
      }

      // The sections, the page, the windows.
      Item {
        id: body
        // Where a pane at the right is: its own column, or its place in the one
        // they share (a heading each, and the open one's body).
        readonly property real headH: 36
        function paneX(k) { return width - panel.rightW + Math.max(0, root.colOf(k)) * panel.colW }
        function paneW(k) { return panel.colW - (root.colOf(k) < root.rightCols - 1 ? Style.space(14) : 0) }
        function paneY(k) {
          if (!root.foldOf(k)) return 0
          var g = root.groupOf(k), i = g.indexOf(k), o = g.indexOf(root.rightOpenKey)
          return i * headH + (o < i ? height - g.length * headH : 0)
        }
        function paneH(k) { return !root.foldOf(k) ? height : k === root.rightOpenKey ? height - (root.groupOf(k).length - 1) * headH : headH }
        anchors { top: searchBox.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; bottom: power.top; bottomMargin: Style.space(10) }

        // The sections: the Omarchy menu's root.
        Flickable {
          id: secFlick
          width: panel.leftW
          height: parent.height
          contentHeight: secCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          Column {
            id: secCol
            width: parent.width
            spacing: 2
            MenuRow {  // Favorites, as a page (Settings: or a column at the right)
              visible: root.favPlace === "left"
              height: visible ? 30 : 0
              rowHeight: 30
              glyph: "\u{F04CE}"
              label: "Favorites"
              current: !root.query && !root.settingsOpen && !root.notesOpen && root.specialPage === "favorites"
              onClicked: { search.text = ""; root.openSpecial("favorites"); search.forceActiveFocus() }
            }
            MenuRow {  // the open windows, as a page
              visible: root.windowsPlace === "left"
              height: visible ? 30 : 0
              rowHeight: 30
              glyph: "\u{F05AF}"
              label: "Open windows"
              badge: root.windowCount ? String(root.windowCount) : ""
              current: !root.query && !root.settingsOpen && !root.notesOpen && root.specialPage === "windows"
              onClicked: { search.text = ""; root.openSpecial("windows"); search.forceActiveFocus() }
            }
            Repeater {
              model: root.sections
              Column {
                id: sec
                required property var modelData
                width: secCol.width
                spacing: 2
                MenuRow {
                  rowHeight: 30
                  glyph: sec.modelData.icon
                  glyphFont: sec.modelData.iconFont
                  label: sec.modelData.label
                  current: !root.query && !root.settingsOpen && !root.notesOpen && !root.specialPage && root.section === sec.modelData.id
                  onClicked: { search.text = ""; root.open_(sec.modelData.id); search.forceActiveFocus() }
                }
                MenuRow {  // under Apps: the ones started lately
                  visible: sec.modelData.id === "apps" && root.recentOn
                  rowHeight: 30
                  glyph: "\u{F02DA}"
                  label: "Recent"
                  current: !root.query && !root.settingsOpen && !root.notesOpen && root.specialPage === "recent"
                  onClicked: { search.text = ""; root.openSpecial("recent"); search.forceActiveFocus() }
                }
              }
            }
            MenuRow {  // with omext bell: its notifications
              visible: root.bellThere && root.notesPlace === "left"
              height: visible ? 30 : 0
              rowHeight: 30
              glyph: root.bellUnread ? "\u{F116B}" : "\u{F009A}"
              label: "Notifications"
              badge: root.bellUnread ? String(root.bellUnread) : ""
              current: !root.query && root.notesOpen
              onClicked: { search.text = ""; root.open_("notifications"); search.forceActiveFocus() }
            }
            Rectangle {
              visible: root.rootActions.length > 0
              x: 10; width: parent.width - 20; height: 1
              color: Commons.Util.alpha(root.text, 0.1)
            }
            Item { visible: root.rootActions.length > 0; width: 1; height: 2 }
            Repeater {
              model: root.rootActions
              MenuRow {
                required property var modelData
                glyph: modelData.icon
                glyphFont: modelData.iconFont
                rowHeight: 30
                label: MenuModel.labelFor(modelData, root.checkedResults, root.disabledResults)
                more: modelData.kind === "link" || !!modelData.provider
                dimmed: root.disabled(modelData)
                onClicked: root.activate({ entry: modelData })
              }
            }
          }
        }

        Rectangle {
          x: panel.leftW + Style.space(6)
          width: 1; height: parent.height
          color: Commons.Util.alpha(root.text, 0.1)
        }

        // The page: the section's rows (or, searching, what matches).
        Item {
          id: page
          x: panel.leftW + Style.space(14)
          width: parent.width - x - (root.settingsOpen ? 0 : panel.rightW + (root.rightShown ? Style.space(14) : 0))
          height: parent.height

          MenuRow {  // the way back, inside a submenu
            id: backRow
            visible: !root.query && !root.settingsOpen && !root.notesOpen && !root.specialPage && root.trail.length > 1
            height: visible ? 30 : 0
            glyph: "‹"
            label: root.trail.slice(0, -1).map(e => e.label).join("  ›  ")
            dimmed: true
            onClicked: { root.back(); search.forceActiveFocus() }
          }
          Text {
            id: pageTitle
            z: 3
            anchors.top: backRow.bottom
            width: parent.width
            leftPadding: 10
            bottomPadding: 6
            text: root.settingsOpen ? "Settings"
                 : root.notesOpen && !root.query ? "Notifications"
                 : root.query ? (root.pickable.length ? "Results" : "Nothing matches “" + root.query + "”")
                 : root.specialPage === "favorites" ? "Favorites" : root.specialPage === "recent" ? "Recent" : root.specialPage === "windows" ? "Open windows"
                 : root.providerFor === root.path && !(root.providerRows[root.path] || []).length ? "Loading…"
                 : root.path === "apps" ? "All apps" : (root.trail.length ? (root.trail[root.trail.length - 1].title || root.trail[root.trail.length - 1].label) : "")
            color: root.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            HoverHandler { id: titleHov }
            HeadTools {
              kind: root.pageKind
              shown: titleHov.hovered
              anchors { right: parent.right; rightMargin: 6; top: parent.top }
            }
          }
          Flickable {
            id: pageFlick
            visible: !root.settingsOpen && !(root.notesOpen && !root.query) && !(root.pageKind !== "" && root.settingsFor === root.pageKind)
            anchors { top: pageTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            contentHeight: pageCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Rectangle {  // a favorite being dragged: where it would land
              visible: root.favDragKey !== "" && root.specialPage === "favorites" && !root.query
              x: 6; y: Math.max(0, root.favDropY - 2)   // (not above the list's top, where it would be cut off: before the first)
              z: 2
              width: pageCol.width - 12; height: 2; radius: 1
              color: root.accent
            }
            Column {
              id: pageCol
              width: parent.width
              spacing: 2
              Repeater {
                id: pageRepeater
                model: root.pageRows
                Item {
                  id: cell
                  required property var modelData
                  required property int index
                  width: pageCol.width
                  visible: !(root.favGroupDrag && !!modelData.fav)
                  height: !visible ? 0 : modelData.groupKey ? gcap.height : modelData.head ? cap.implicitHeight : row.height
                  Caption {
                    id: cap
                    visible: !!cell.modelData.head && !cell.modelData.groupKey
                    text: cell.modelData.head || ""
                  }
                  GroupHead {  // among the favorites: a group's heading
                    id: gcap
                    visible: !!cell.modelData.groupKey
                    key: cell.modelData.groupKey || ""
                    onDragAt: function(x, y) { root.favDragTo(key, pageRepeater, x, cell.y + y, false, pageFlick) }
                    onDropped: root.favDrop()
                  }
                  MenuRow {
                    id: row
                    visible: !cell.modelData.head
                    readonly property var e: cell.modelData.entry || null
                    readonly property var a: cell.modelData.app || null
                    readonly property var w: cell.modelData.win || null
                    readonly property string fk: root.favKey(cell.modelData)
                    star: fk && root.favPlace !== "off" ? (root.isFav(fk) ? 1 : 0) : -1
                    movable: !!cell.modelData.fav && !root.query && !root.favByName
                    draggable: movable
                    opacity: root.favDragKey !== "" && root.favDragKey === fk && movable ? 0.4 : 1
                    onDragAt: function(y) { root.favDragTo(fk, pageRepeater, 0, cell.y + y, false, pageFlick) }
                    onDropped: root.favDrop()
                    onStarClicked: root.toggleFav(fk)
                    onMoved: function(by) { root.moveFav(fk, by) }
                    closable: !!w
                    current: !!w && w.address === root.activeAddress
                    onCloseClicked: root.closeWindow(w)
                    readonly property var sw: { var _ = root.whenResults; var __ = root.checkedResults; return root.toggleOf(e) }
                    toggle: sw ? (sw.on ? 1 : 0) : -1
                    glyph: e ? e.icon : ""
                    glyphFont: e ? e.iconFont : ""
                    image: a ? root.iconFor(a.icon) : w ? root.windowIcon(w) : ""
                    label: w ? (w.title || root.windowName(w)) : sw ? sw.name : e ? MenuModel.labelFor(e, root.checkedResults, root.disabledResults) : a ? a.name : ""
                    sub: w ? root.windowName(w) : cell.modelData.sub || (e ? e.description : a && root.query ? (a.genericName || "") : "")
                    more: !!e && (e.kind === "menu" || e.kind === "link" || !!e.provider)
                    dimmed: !!e && root.disabled(e)
                    selected: root.cursorKey !== "" && root.rowKey(cell.modelData) === root.cursorKey
                    onClicked: { root.activate(cell.modelData); search.forceActiveFocus() }
                  }
                }
              }
            }
          }

          Text {  // a page of Start's own, with nothing on it yet
            visible: pageFlick.visible && !root.query && root.specialPage !== "" && root.pageRows.length === 0
            anchors.top: pageTitle.bottom
            width: parent.width
            leftPadding: 10
            wrapMode: Text.WordWrap
            text: root.specialPage === "favorites" ? "Nothing here yet. Point at an app or a menu entry and click its star (or right click it)." : root.specialPage === "recent" ? "Nothing here now. The apps you used lately show here once they're closed, the latest first." : "No open windows"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Notifications (omext bell's list; typing searches everything, as anywhere).
          Loader {
            id: notesList
            visible: root.notesOpen && !root.query && !root.settingsOpen && root.settingsFor !== "notifications"
            active: root.bellThere && bellHistory.status === Loader.Ready
            anchors { top: pageTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            onActiveChanged: if (active) setSource("file://" + root.bellDir + "/NotificationList.qml",
                                                  { history: bellHistory.item, fontFamily: root.fontFamily, sizeScale: 1 })
            Connections {
              target: notesList.item
              ignoreUnknownSignals: true
              function onActed() { root.close() }
            }
          }

          PaneSettings {
            kind: root.pageKind
            visible: root.pageKind !== "" && root.settingsFor === root.pageKind
            anchors { top: pageTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
          }

          // Settings: the keyboard shortcut, the bar button.
          Flickable {
            id: settingsFlick
            visible: root.settingsOpen
            anchors { top: pageTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            contentHeight: settingsCol.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          // With room (they take the columns at the right too): side by side.
          Flow {
            id: settingsCol
            width: settingsFlick.width - 10
            spacing: Style.space(20)
            readonly property bool two: width > Style.space(620)
            readonly property real colW: two ? Math.floor((width - spacing) / 2) : width
          Column {
            width: settingsCol.colW
            spacing: 2
            SetHead { first: true; text: "Keyboard shortcut" }
            Repeater {
              model: [
                { keys: root.defaultShortcut, label: root.prettyKeys(root.defaultShortcut), sub: "Its own keys (the default)" },
                { keys: "SUPER + SPACE", label: "Super + Space", sub: "In place of Omarchy's menu" },
                { keys: "", label: "None", sub: "Only the bar button" }
              ]
              MenuRow {
                required property var modelData
                glyph: root.shortcut === modelData.keys ? "\u25c9" : "\u25cb"
                glyphFont: root.fontFamily
                label: modelData.label
                sub: modelData.sub
                current: root.shortcut === modelData.keys
                onClicked: { root.setShortcut(modelData.keys); ownKeys.text = ""; search.forceActiveFocus() }
              }
            }
            MenuRow {
              readonly property bool own: root.shortcut !== "" && root.shortcut !== root.defaultShortcut && root.shortcut !== "SUPER + SPACE"
              glyph: own ? "\u25c9" : "\u25cb"
              glyphFont: root.fontFamily
              label: own ? "Your own: " + root.prettyKeys(root.shortcut) : "Your own"
              sub: "Keys as Hyprland writes them, e.g. Super + Ctrl + M"
              current: own
              onClicked: ownKeys.forceActiveFocus()
            }
            Row {
              x: 42
              spacing: 6
              Rectangle {
                width: Math.max(80, Math.min(220, parent.parent.width - 42 - 66 - 12)); height: 30; radius: 6   // with Set beside it, in the column
                color: Commons.Util.alpha(root.text, 0.06)
                border.color: Commons.Util.alpha(root.accent, ownKeys.activeFocus ? 0.8 : 0.3)
                TextInput {
                  id: ownKeys
                  anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  clip: true
                  Keys.onReturnPressed: if (text.trim()) { root.setShortcut(text); search.forceActiveFocus() }
                  Keys.onEscapePressed: search.forceActiveFocus()
                  Text { visible: !ownKeys.text; text: "Super + Ctrl + M"; color: root.dim; font: ownKeys.font; anchors.verticalCenter: parent.verticalCenter }
                }
              }
              Rectangle {
                width: 60; height: 30; radius: 6
                color: setHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : Commons.Util.alpha(root.text, 0.08)
                opacity: ownKeys.text.trim() ? 1 : 0.4
                Text { anchors.centerIn: parent; text: "Set"; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                MouseArea { id: setHit; anchors.fill: parent; hoverEnabled: true; onClicked: if (ownKeys.text.trim()) { root.setShortcut(ownKeys.text); search.forceActiveFocus() } }
              }
            }
            Text {  // what the keys do now: replaced by Start
              readonly property string taken: root.bindOf(ownKeys.text.trim() ? ownKeys.text : root.shortcut)
              visible: !!taken
              x: 42
              width: parent.width - 52
              topPadding: 4
              wrapMode: Text.WordWrap
              text: (ownKeys.text.trim() ? root.prettyKeys(ownKeys.text) : root.prettyKeys(root.shortcut)) + " is " + taken + " now: Start takes its place."
              color: Commons.Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Start on Super + Space: where Omarchy's menu goes instead.
            SetHead { visible: root.tookSpace; text: "Omarchy's menu moves to" }
            MenuRow {
              visible: root.tookSpace
              glyph: root.menuKeys === root.defaultShortcut ? "\u25c9" : "\u25cb"
              glyphFont: root.fontFamily
              label: root.prettyKeys(root.defaultShortcut)
              sub: "Swapped with Start (the default)"
              current: root.menuKeys === root.defaultShortcut
              onClicked: { root.setMenuKeys(root.defaultShortcut); menuOwnKeys.text = ""; search.forceActiveFocus() }
            }
            MenuRow {
              readonly property bool own: root.menuKeys !== "" && root.menuKeys !== root.defaultShortcut
              visible: root.tookSpace
              glyph: own ? "\u25c9" : "\u25cb"
              glyphFont: root.fontFamily
              label: own ? "Your own: " + root.prettyKeys(root.menuKeys) : "Your own"
              sub: "e.g. Super + Ctrl + M"
              current: own
              onClicked: menuOwnKeys.forceActiveFocus()
            }
            Row {
              visible: root.tookSpace
              x: 42
              spacing: 6
              Rectangle {
                width: Math.max(80, Math.min(220, parent.parent.width - 42 - 66 - 12)); height: 30; radius: 6   // with Set beside it, in the column
                color: Commons.Util.alpha(root.text, 0.06)
                border.color: Commons.Util.alpha(root.accent, menuOwnKeys.activeFocus ? 0.8 : 0.3)
                TextInput {
                  id: menuOwnKeys
                  anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  clip: true
                  Keys.onReturnPressed: if (text.trim()) { root.setMenuKeys(text); search.forceActiveFocus() }
                  Keys.onEscapePressed: search.forceActiveFocus()
                  Text { visible: !menuOwnKeys.text; text: "Super + Ctrl + M"; color: root.dim; font: menuOwnKeys.font; anchors.verticalCenter: parent.verticalCenter }
                }
              }
              Rectangle {
                width: 60; height: 30; radius: 6
                color: menuSetHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : Commons.Util.alpha(root.text, 0.08)
                opacity: menuOwnKeys.text.trim() ? 1 : 0.4
                Text { anchors.centerIn: parent; text: "Set"; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                MouseArea { id: menuSetHit; anchors.fill: parent; hoverEnabled: true; onClicked: if (menuOwnKeys.text.trim()) { root.setMenuKeys(menuOwnKeys.text); search.forceActiveFocus() } }
              }
            }
            Text {
              readonly property string taken: menuOwnKeys.text.trim() ? root.bindOf(menuOwnKeys.text) : ""
              visible: root.tookSpace && !!taken
              x: 42
              width: parent.width - 52
              topPadding: 4
              wrapMode: Text.WordWrap
              text: root.prettyKeys(menuOwnKeys.text) + " is " + taken + " now: Omarchy's menu takes its place."
              color: Commons.Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MenuRow {
              visible: root.tookSpace
              glyph: root.menuKeys === "" ? "\u25c9" : "\u25cb"
              glyphFont: root.fontFamily
              label: "None"
              sub: "Right click on Start's bar button only"
              current: root.menuKeys === ""
              onClicked: { root.setMenuKeys(""); menuOwnKeys.text = ""; search.forceActiveFocus() }
            }
            SetHead { text: "Starts at login" }
            Text {
              visible: root.startupItems.length === 0
              leftPadding: 10
              text: "Nothing listed"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: root.startupItems
              MenuRow {
                required property var modelData
                rowHeight: 32
                readonly property string found: !modelData.icon ? "" : modelData.icon.charAt(0) === "/" ? "file://" + modelData.icon : Quickshell.iconPath(modelData.icon, true)
                image: found
                glyph: found ? "" : "\uf013"
                label: modelData.name
                badge: modelData.kind === "dock" ? (modelData.where || "Dock") : modelData.kind === "system" ? "System" : ""
                toggle: modelData.on ? 1 : 0
                closable: modelData.removable === true
                onClicked: root.startupRun(["set", modelData.id, modelData.on ? "off" : "on"])
                onCloseClicked: root.startupRun(["remove", modelData.id])
              }
            }
            MenuRow {
              glyph: "\u{F0415}"
              label: "Add an app"
              sub: "Type its name below, then choose it"
              onClicked: startupInput.forceActiveFocus()
            }
            Rectangle {
              id: startupBox
              x: 42
              width: Math.max(80, Math.min(260, parent.width - 42 - 12)); height: 30; radius: 6
              color: Commons.Util.alpha(root.text, 0.06)
              border.color: Commons.Util.alpha(root.accent, startupInput.activeFocus ? 0.8 : 0.3)
              TextInput {
                id: startupInput
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                color: root.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                clip: true
                maximumLength: 40
                onTextChanged: { root.startupQuery = text; startupShow.restart() }
                onActiveFocusChanged: if (activeFocus) startupShow.restart()
                Keys.onReturnPressed: if (root.startupMatches.length) { root.startupRun(["add", root.startupMatches[0].id]); text = ""; search.forceActiveFocus() }
                Keys.onEscapePressed: { text = ""; search.forceActiveFocus() }
                Text { visible: !startupInput.text; text: "An app's name"; color: root.dim; font: startupInput.font; anchors.verticalCenter: parent.verticalCenter }
              }
            }
            Repeater {
              model: root.startupMatches
              MenuRow {
                required property var modelData
                rowHeight: 32
                image: root.iconFor(modelData.icon)
                label: modelData.name
                badge: "Add"
                onClicked: { root.startupRun(["add", modelData.id]); startupInput.text = ""; search.forceActiveFocus() }
              }
            }
            Item {  // the field's end: what the settings scroll to, the matches with it
              id: startupEnd
              width: 1; height: 1
              Timer { id: startupShow; interval: 30; onTriggered: { root.kbReveal(startupBox, settingsFlick); root.kbReveal(startupEnd, settingsFlick) } }
            }
          }
          Column {
            width: settingsCol.colW
            spacing: 2
            SetHead { first: settingsCol.two; text: "Size (at most the screen's)" }
            Repeater {
              model: ["compact", "default", "large", "xlarge"]
              MenuRow {
                required property string modelData
                readonly property var d: root.sizes[modelData]
                glyph: root.sizeName === modelData ? "\u25c9" : "\u25cb"
                glyphFont: root.fontFamily
                label: d.label
                sub: (root.leftCols + d.mid + d.right * root.rightCols + 28) + " \u00d7 " + d.height + (modelData === "default" ? " (the default)" : "")
                current: root.sizeName === modelData
                onClicked: { root.saveConfig({ size: modelData }); search.forceActiveFocus() }
              }
            }

            SetHead { text: "In the menu" }
            Text {  // where the rest of their settings are
              x: 10
              width: parent.width - 20
              bottomPadding: 4
              wrapMode: Text.WordWrap
              text: "Where each one shows, and how: the gear on its own heading."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MenuRow {
              glyph: "\u{F04CE}"
              toggle: root.favPlace !== "off" ? 1 : 0
              label: "Favorites"
              sub: "Apps and menu entries you starred"
              current: root.favPlace !== "off"
              onClicked: {
                if (root.favPlace === "off") root.saveConfig({ favoritesOff: false, favorites: root.config.favorites === "right" ? "right" : "left" })
                else root.saveConfig({ favoritesOff: true })
                search.forceActiveFocus()
              }
            }
            MenuRow {
              glyph: "\u{F02DA}"
              toggle: root.recentOn ? 1 : 0
              label: "Recent"
              sub: "Under Apps: the apps you opened lately"
              current: root.recentOn
              onClicked: { root.saveConfig({ recentOff: root.recentOn }); if (root.specialPage === "recent") root.open_(root.section); search.forceActiveFocus() }
            }
            MenuRow {
              glyph: "\u{F05AF}"
              toggle: root.windowsPlace !== "off" ? 1 : 0
              label: "Open windows"
              sub: root.taskbarThere ? "By workspace (omext taskbar shows them too)" : "By workspace"
              current: root.windowsPlace !== "off"
              onClicked: {
                if (root.windowsPlace === "off") root.saveConfig({ windowsOff: false, windows: root.config.windows === "left" ? "left" : "right" })
                else root.saveConfig({ windowsOff: true })
                search.forceActiveFocus()
              }
            }
            MenuRow {
              visible: root.bellThere
              height: visible ? 44 : 0
              glyph: "\u{F009A}"
              toggle: root.notesPlace !== "off" ? 1 : 0
              label: "Notifications"
              sub: "omext bell's history"
              current: root.notesPlace !== "off"
              onClicked: {
                if (root.notesPlace === "off") root.saveConfig({ notificationsOff: false, notifications: root.config.notifications === "right" ? "right" : "left" })
                else root.saveConfig({ notificationsOff: true })
                search.forceActiveFocus()
              }
            }

            SetHead { text: "Bar button" }
            MenuRow {
              glyph: "\u{F0570}"
              toggle: root.tookMenuButton ? 1 : 0
              label: "In place of Omarchy's menu button"
              sub: root.onTaskbar ? "Start's button on the bar too, where Omarchy's is; Omarchy's leaves the bar"
                                  : "Start's button goes where Omarchy's is, and Omarchy's leaves the bar"
              current: root.tookMenuButton
              onClicked: { root.takeMenuButton(!root.tookMenuButton); search.forceActiveFocus() }
            }
            MenuRow {
              visible: root.taskbarThere
              glyph: "\u{F10A9}"
              toggle: root.onTaskbar ? 1 : 0
              label: "On the taskbar"
              sub: "At the left end of omext taskbar, in place of the bar button"
              current: root.onTaskbar
              onClicked: { root.close(); root.setShared({ startOnTaskbar: !root.onTaskbar }) }
            }
            // (On the taskbar alone it's a round button: no room on its sides, no label.)
            MenuRow {
              visible: root.onBar
              glyph: "\uf07e"
              toggle: root.padded ? 1 : 0
              label: "Space on both sides"
              sub: "A wider button, set apart from its neighbours"
              current: root.padded
              onClicked: { root.saveConfig({ padding: !root.padded }); search.forceActiveFocus() }
            }
            MenuRow {
              visible: root.onBar
              glyph: "\uf031"
              label: root.barLabel ? "Label: " + root.barLabel : "Label"
              sub: "After the icon, and clickable (empty: none)"
              onClicked: labelInput.forceActiveFocus()
            }
            Row {
              visible: root.onBar
              x: 42
              spacing: 6
              Rectangle {
                width: Math.max(80, Math.min(220, parent.parent.width - 42 - 66 - 12)); height: 30; radius: 6   // with Set beside it, in the column
                color: Commons.Util.alpha(root.text, 0.06)
                border.color: Commons.Util.alpha(root.accent, labelInput.activeFocus ? 0.8 : 0.3)
                TextInput {
                  id: labelInput
                  anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  clip: true
                  maximumLength: 40
                  Keys.onReturnPressed: { root.saveConfig({ label: text.trim() }); search.forceActiveFocus() }
                  Keys.onEscapePressed: { text = root.barLabel; search.forceActiveFocus() }
                  Text { visible: !labelInput.text; text: "Start"; color: root.dim; font: labelInput.font; anchors.verticalCenter: parent.verticalCenter }
                }
              }
              Rectangle {
                width: 60; height: 30; radius: 6
                color: labelHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : Commons.Util.alpha(root.text, 0.08)
                opacity: labelInput.text.trim() !== root.barLabel ? 1 : 0.4
                Text { anchors.centerIn: parent; text: "Set"; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                MouseArea { id: labelHit; anchors.fill: parent; hoverEnabled: true; onClicked: { root.saveConfig({ label: labelInput.text.trim() }); search.forceActiveFocus() } }
              }
            }

            SetHead { text: "Default apps" }
            Repeater {
              model: root.defaultKinds
              Column {
                id: kindBox
                required property var modelData
                readonly property bool open: root.defaultOpen === modelData.id
                width: parent.width
                spacing: 2
                MenuRow {
                  readonly property string found: root.defaultsIcon(kindBox.modelData.current ? kindBox.modelData.current.icon : "")
                  image: found
                  glyph: found ? "" : "\uf013"
                  label: kindBox.modelData.name
                  sub: kindBox.modelData.current ? kindBox.modelData.current.name : kindBox.modelData.apps.length ? "None chosen" : "No app for it"
                  dimmed: kindBox.modelData.apps.length === 0
                  badge: kindBox.open ? "\u2212" : kindBox.modelData.apps.length > 1 ? String(kindBox.modelData.apps.length) : ""
                  onClicked: if (kindBox.modelData.apps.length) root.defaultOpen = kindBox.open ? "" : kindBox.modelData.id
                }
                Column {
                  visible: kindBox.open
                  x: 26; width: parent.width - 26
                  spacing: 2
                  Repeater {
                    model: kindBox.open ? kindBox.modelData.apps : []
                    MenuRow {
                      required property var modelData
                      readonly property string found: root.defaultsIcon(modelData.icon)
                      rowHeight: 30
                      image: found
                      glyph: found ? "" : "\uf013"
                      label: modelData.name
                      current: !!kindBox.modelData.current && kindBox.modelData.current.id === modelData.id
                      badge: current ? "Default" : ""
                      onClicked: { root.defaultsSet(kindBox.modelData.id, modelData.id); search.forceActiveFocus() }
                    }
                  }
                }
              }
            }
            MenuRow {
              glyph: "\u{F0214}"
              label: "A file type"
              sub: "Type it below (.pdf, .docx), then choose its app"
              onClicked: defaultTypeInput.forceActiveFocus()
            }
            Rectangle {
              id: defaultTypeBox
              x: 42
              width: Math.max(80, Math.min(260, parent.width - 42 - 12)); height: 30; radius: 6
              color: Commons.Util.alpha(root.text, 0.06)
              border.color: Commons.Util.alpha(root.accent, defaultTypeInput.activeFocus ? 0.8 : 0.3)
              TextInput {
                id: defaultTypeInput
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                color: root.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                clip: true
                maximumLength: 80
                onTextChanged: { defaultsTypeLater.restart(); defaultTypeShow.restart() }
                onActiveFocusChanged: if (activeFocus) defaultTypeShow.restart()
                Keys.onEscapePressed: { text = ""; search.forceActiveFocus() }
                Text { visible: !defaultTypeInput.text; text: ".pdf"; color: root.dim; font: defaultTypeInput.font; anchors.verticalCenter: parent.verticalCenter }
              }
            }
            Text {
              visible: defaultTypeInput.text.trim() !== "" && !root.defaultType && !defaultsTypeLater.running && !defaultsTypeProc.running
              leftPadding: 42
              text: "No such file type"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Column {
              visible: !!root.defaultType
              width: parent.width
              spacing: 2
              Text {
                width: parent.width
                leftPadding: 42; topPadding: 4
                text: root.defaultType ? root.defaultType.name + (root.defaultType.apps.length ? "" : ": no app says it opens it") : ""
                elide: Text.ElideRight
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Repeater {
                model: root.defaultType ? root.defaultType.apps : []
                MenuRow {
                  required property var modelData
                  readonly property string found: root.defaultsIcon(modelData.icon)
                  rowHeight: 30
                  image: found
                  glyph: found ? "" : "\uf013"
                  label: modelData.name
                  current: !!root.defaultType.current && root.defaultType.current.id === modelData.id
                  badge: current ? "Default" : ""
                  onClicked: { root.defaultsSet(root.defaultType.type, modelData.id); search.forceActiveFocus() }
                }
              }
            }
            Item {
              id: defaultTypeEnd
              width: 1; height: 1
              Timer { id: defaultTypeShow; interval: 320; onTriggered: { root.kbReveal(defaultTypeBox, settingsFlick); root.kbReveal(defaultTypeEnd, settingsFlick) } }
            }

            SetHead { text: "Omarchy's dock" }
            MenuRow {
              glyph: "\udb84\udca9"
              label: "Omarchy's dock"
              sub: root.taskbarOn ? "Off: omext taskbar is in its place"
                 : root.omarchyDockOff ? "Off: Super + Alt + Space opens Start's apps" : "Off, Start's apps take Super + Alt + Space"
              toggle: root.taskbarOn || root.omarchyDockOff ? 0 : 1
              opacity: root.taskbarOn ? 0.55 : 1
              onClicked: { root.setOmarchyDock(root.omarchyDockOff); search.forceActiveFocus() }
            }

            SetHead { text: "Turn off" }
            MenuRow {
              glyph: "\uf011"
              label: "Turn off this menu"
              sub: "Hides its bar button and shortcut. Back on: Omarchy menu \u203a Setup \u203a Omarchy Extended"
              onClicked: { root.close(); root.request("off", "") }
            }
          }
          }
          }

          // Uninstalling an app: asked first.
          Rectangle {
            visible: !!root.removeApp
            anchors.centerIn: parent
            width: Math.min(parent.width - 20, 340)
            height: askCol.implicitHeight + 28
            radius: 10
            color: Commons.Color.popups.background
            border.color: Commons.Util.alpha(Commons.Color.urgent, 0.6)
            MouseArea { anchors.fill: parent }  // nothing under it takes the clicks
            Column {
              id: askCol
              anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
              spacing: 10
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Remove " + (root.removeApp ? root.removeApp.name : "") + "?"
                color: root.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Uninstalls it (a web app or a terminal app: removes it), as Omarchy's menu does."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Row {
                anchors.right: parent.right
                spacing: 6
                Repeater {
                  model: [{ yes: true, label: "Remove" }, { yes: false, label: "Cancel" }]
                  Rectangle {
                    required property var modelData
                    width: 84; height: 30; radius: 6
                    readonly property bool on: root.removeYes === modelData.yes
                    color: on ? Commons.Util.alpha(modelData.yes ? Commons.Color.urgent : root.accent, 0.35)
                         : bHit.containsMouse ? Commons.Util.alpha(root.text, 0.12) : Commons.Util.alpha(root.text, 0.06)
                    Text { anchors.centerIn: parent; text: parent.modelData.label; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                    MouseArea { id: bHit; anchors.fill: parent; hoverEnabled: true; onClicked: { if (parent.modelData.yes) root.doRemove(); else root.removeApp = null; search.forceActiveFocus() } }
                  }
                }
              }
            }
          }
        }

        Rectangle {
          visible: root.rightShown === true && !root.settingsOpen
          x: parent.width - panel.rightW - Style.space(8)
          width: 1; height: parent.height
          color: Commons.Util.alpha(root.text, 0.1)
        }

        Rectangle {  // a heading's button, pointed at: its name
          visible: root.headHint !== ""
          z: 100
          x: Math.max(0, Math.min(body.width - width, root.headHintX - width))
          y: root.headHintY
          width: headHintText.implicitWidth + 14; height: headHintText.implicitHeight + 8; radius: 6
          color: Commons.Color.popups.background
          border.color: Commons.Util.alpha(root.text, 0.25)
          Text { id: headHintText; anchors.centerIn: parent; text: root.headHint; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        }

        Repeater {  // between the columns at the right, when each has its own
          model: root.settingsOpen ? 0 : Math.max(0, root.rightCols - 1)
          Rectangle {
            required property int index
            x: body.width - panel.rightW + (index + 1) * panel.colW - Style.space(8)
            width: 1; height: body.height
            color: Commons.Util.alpha(root.text, 0.1)
          }
        }

        // Favorites, as icons: a click runs one; pointed at, it can move or go.
        Item {
          id: favPane
          visible: root.rightItems.indexOf("favorites") >= 0 && !root.settingsOpen
          x: body.paneX("favorites"); y: body.paneY("favorites")
          width: body.paneW("favorites"); height: body.paneH("favorites")
          clip: true
          Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          PaneHead { id: favTitle; key: "favorites"; title: "Favorites" }
          Rectangle {  // the keyboard is here
            visible: root.kbArea === "favorites"
            anchors.fill: parent
            z: 3
            radius: 8
            color: "transparent"
            border.width: 1
            border.color: Commons.Util.alpha(root.accent, 0.55)
          }
          PaneSettings {
            kind: "favorites"
            visible: root.settingsFor === "favorites"
            anchors { top: favTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
          }
          Text {
            visible: root.favoriteRows.length === 0 && root.settingsFor !== "favorites"
            anchors.top: favTitle.bottom
            width: parent.width
            leftPadding: 10
            wrapMode: Text.WordWrap
            text: "Point at an app and click its star"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Flickable {  // as a list
            id: favListFlick
            visible: root.settingsFor !== "favorites" && !root.favTiles
            anchors { top: favTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            contentHeight: favListCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Rectangle {  // one being dragged: where it would land
              visible: root.favDragKey !== ""
              x: 6; y: Math.max(0, root.favDropY - 2)   // (not above the list's top, where it would be cut off: before the first)
              z: 2
              width: favListCol.width - 12; height: 2; radius: 1
              color: root.accent
            }
            Column {
              id: favListCol
              width: parent.width
              spacing: 2
              Repeater {
                id: favListRep
                model: root.favTiles ? [] : root.favoriteRows
                Item {
                  id: lcell
                  required property var modelData
                  width: favListCol.width
                  visible: !(root.favGroupDrag && !modelData.groupKey)
                  height: !visible ? 0 : modelData.groupKey ? lhead.height : lrow.height
                  GroupHead {
                    id: lhead
                    visible: !!lcell.modelData.groupKey
                    key: lcell.modelData.groupKey || ""
                    onDragAt: function(x, y) { root.favDragTo(key, favListRep, x, lcell.y + y, false, favListFlick) }
                    onDropped: root.favDrop()
                  }
                  MenuRow {
                    id: lrow
                    visible: !lcell.modelData.groupKey
                    readonly property var e: lcell.modelData.entry || null
                    readonly property var a: lcell.modelData.app || null
                    readonly property string fk: root.favKey(lcell.modelData)
                    rowHeight: 32
                    glyph: e ? e.icon : ""
                    glyphFont: e ? e.iconFont : ""
                    image: a ? root.iconFor(a.icon) : ""
                    label: a ? a.name : e ? e.label : ""
                    star: 1
                    movable: !root.favByName
                    draggable: movable
                    opacity: root.favDragKey !== "" && root.favDragKey === fk ? 0.4 : 1
                    onDragAt: function(y) { root.favDragTo(fk, favListRep, 0, lcell.y + y, false, favListFlick) }
                    onDropped: root.favDrop()
                    selected: root.kbFavKey !== "" && root.kbFavKey === fk
                    onStarClicked: root.toggleFav(fk)
                    onClicked: root.activate(lcell.modelData)
                  }
                }
              }
            }
          }
          Flickable {  // as icons
            id: favTileFlick
            visible: root.settingsFor !== "favorites" && root.favTiles
            anchors { top: favTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            contentHeight: favFlow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Rectangle {  // a group dragged past the last heading: it would go last
              visible: root.favGroupDrag && root.favDropBefore === ""
              x: 10; y: root.favDropY
              z: 2
              width: favFlow.width - 12; height: 2; radius: 1
              color: root.accent
            }
            Flow {
              id: favFlow
              x: 4
              width: parent.width - 8
              readonly property int perRow: Math.max(3, Math.floor(width / 84))
              readonly property real tileW: Math.floor(width / perRow)
              Repeater {
                id: favTileRep
                model: root.favTiles ? root.favoriteRows : []
                Item {
                  id: wrap
                  required property var modelData
                  required property int index
                  readonly property bool head: !!modelData.groupKey
                  visible: !(root.favGroupDrag && !head)
                  width: head ? favFlow.width : favFlow.tileW
                  height: head ? thead.height : 74
                  Rectangle {  // one being dragged would land before this one (a heading: above it)
                    visible: root.favDragKey !== "" && root.favDragKey !== root.favRowKey(wrap.modelData) && root.favDropBefore === root.favRowKey(wrap.modelData)
                    z: 2
                    x: wrap.head ? 6 : -1; y: wrap.head ? 0 : 8
                    width: wrap.head ? parent.width - 12 : 2; height: wrap.head ? 2 : parent.height - 16; radius: 1
                    color: root.accent
                  }
                  Rectangle {  // ... or after the last
                    visible: root.favDragKey !== "" && root.favDropBefore === "" && wrap.index === root.favoriteRows.length - 1 && root.favDragKey !== root.favRowKey(wrap.modelData)
                    z: 2
                    x: wrap.head ? 6 : parent.width - 1; y: wrap.head ? parent.height - 2 : 8
                    width: wrap.head ? parent.width - 12 : 2; height: wrap.head ? 2 : parent.height - 16; radius: 1
                    color: root.accent
                  }
                  GroupHead {
                    id: thead
                    visible: wrap.head
                    key: wrap.modelData.groupKey || ""
                    onDragAt: function(x, y) { root.favDragTo(key, favTileRep, wrap.x + x, wrap.y + y, true, favTileFlick) }
                    onDropped: root.favDrop()
                  }
                  Rectangle {
                    id: tile
                    visible: !wrap.head
                    anchors.fill: parent
                    readonly property var modelData: wrap.modelData
                    readonly property string fk: root.favKey(modelData)
                    radius: 8
                    color: root.kbFavKey !== "" && root.kbFavKey === fk ? Commons.Util.alpha(root.accent, 0.22)
                         : tileHov.hovered ? Commons.Util.alpha(root.text, 0.08) : "transparent"
                    opacity: root.favDragKey === tile.fk ? 0.4 : 1
                    HoverHandler { id: tileHov }
                    Image {
                      visible: !!tile.modelData.app
                      anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 10 }
                      width: 32; height: 32
                      source: tile.modelData.app ? root.iconFor(tile.modelData.app.icon) : ""
                      sourceSize: Qt.size(64, 64)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                    }
                    Text {
                      visible: !tile.modelData.app
                      anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                      text: tile.modelData.entry ? tile.modelData.entry.icon : ""
                      color: root.text
                      font.family: tile.modelData.entry && tile.modelData.entry.iconFont || root.iconFont
                      font.pixelSize: 26
                    }
                    Text {
                      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 4; rightMargin: 4; bottomMargin: 7 }
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                      text: tile.modelData.app ? tile.modelData.app.name : tile.modelData.entry ? tile.modelData.entry.label : ""
                      color: root.text
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      preventStealing: true
                      property real x0: 0
                      property real y0: 0
                      property bool drag: false
                      onPressed: function(m) { x0 = m.x; y0 = m.y; drag = false }
                      onPositionChanged: function(m) {
                        if (root.favByName || !pressed || !(pressedButtons & Qt.LeftButton)) return
                        if (!drag && Math.abs(m.x - x0) + Math.abs(m.y - y0) <= 8) return
                        drag = true
                        root.favDragTo(tile.fk, favTileRep, wrap.x + m.x, wrap.y + m.y, true, favTileFlick)
                      }
                      onReleased: if (drag) root.favDrop()
                      onCanceled: { drag = false; root.favDragKey = ""; root.favDragScroll = 0 }
                      onClicked: function(m) { if (drag) { drag = false; return } if (m.button === Qt.RightButton) root.toggleFav(tile.fk); else root.activate(tile.modelData) }
                    }
                    Rectangle {  // pointed at: its star, as in the list (a click takes it out of the favorites)
                      visible: tileHov.hovered
                      anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 2 }
                      width: 24; height: 22; radius: 5
                      color: ttHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : Commons.Color.popups.background
                      Text { anchors.centerIn: parent; text: "\u{F04CE}"; color: root.accent; font.family: root.iconFont; font.pixelSize: 14 }
                      MouseArea { id: ttHit; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleFav(tile.fk) }
                    }
                  }
                }
              }
            }
          }
        }

        // Notifications (omext bell's list), at the menu's size.
        Item {
          id: notePane
          visible: root.rightItems.indexOf("notifications") >= 0 && !root.settingsOpen
          x: body.paneX("notifications"); y: body.paneY("notifications")
          width: body.paneW("notifications"); height: body.paneH("notifications")
          clip: true
          Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          PaneHead { id: noteTitle; key: "notifications"; title: "Notifications"; badge: root.bellUnread ? String(root.bellUnread) : "" }
          Rectangle {  // the keyboard is here
            visible: root.kbArea === "notifications"
            anchors.fill: parent
            z: 3
            radius: 8
            color: "transparent"
            border.width: 1
            border.color: Commons.Util.alpha(root.accent, 0.55)
          }
          Binding { target: notesRight.item; property: "chosen"; value: root.kbArea === "notifications" ? Math.min(root.kbIndex, root.kbNotes - 1) : -1; when: !!notesRight.item }
          Loader {
            id: notesRight
            anchors { top: noteTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            clip: true
            visible: root.settingsFor !== "notifications"
            active: root.notesPlace === "right" && root.bellThere && bellHistory.status === Loader.Ready
            onActiveChanged: if (active) setSource("file://" + root.bellDir + "/NotificationList.qml",
                                                  { history: bellHistory.item, fontFamily: root.fontFamily, sizeScale: 0.9 })
            Connections {
              target: notesRight.item
              ignoreUnknownSignals: true
              function onActed() { root.close() }
            }
          }
          PaneSettings {
            kind: "notifications"
            visible: root.settingsFor === "notifications"
            anchors { top: noteTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
          }
        }

        // Open windows, by workspace: a click goes there.
        Item {
          id: winPane
          visible: root.rightItems.indexOf("windows") >= 0 && !root.settingsOpen
          x: body.paneX("windows"); y: body.paneY("windows")
          width: body.paneW("windows"); height: body.paneH("windows")
          clip: true
          Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Rectangle {  // the keyboard is here
            visible: root.kbArea === "windows"
            anchors.fill: parent
            z: 3
            radius: 8
            color: "transparent"
            border.width: 1
            border.color: Commons.Util.alpha(root.accent, 0.55)
          }
          PaneHead { id: winTitle; key: "windows"; title: "Open windows"; badge: root.foldOf("windows") && root.windowCount ? String(root.windowCount) : "" }
          PaneSettings {
            kind: "windows"
            visible: root.settingsFor === "windows"
            anchors { top: winTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
          }
          Text {
            visible: root.windowCount === 0 && root.settingsFor !== "windows"
            anchors.top: winTitle.bottom
            leftPadding: 10
            text: root.query ? "No open window matches" : "No open windows"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Flickable {
            id: winFlick
            visible: root.settingsFor !== "windows"
            anchors { top: winTitle.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            contentHeight: winCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
              id: winCol
              width: parent.width
              spacing: 2
              Repeater {
                model: root.windowGroups
                Column {
                  id: grp
                  required property var modelData
                  width: winCol.width
                  spacing: 2
                  Caption { text: grp.modelData.title + (grp.modelData.sub ? "  ·  " + grp.modelData.sub : "") }
                  Repeater {
                    model: grp.modelData.windows
                    MenuRow {
                      required property var modelData
                      image: root.windowIcon(modelData)
                      label: modelData.title || root.windowName(modelData)
                      sub: root.windowName(modelData)
                      current: modelData.address === root.activeAddress
                      selected: root.kbWinAddr !== "" && root.kbWinAddr === modelData.address
                      onSelectedChanged: if (selected) root.kbReveal(this, winFlick)
                      closable: true
                      onClicked: root.goTo(modelData)
                      onCloseClicked: root.closeWindow(modelData)
                    }
                  }
                }
              }
            }
          }
        }
      }

      // The System entries: lock, suspend, log out, restart, shut down.
      Rectangle {
        id: power
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 44
        radius: 8
        color: Commons.Util.alpha(root.text, 0.04)
        border.width: root.kbArea === "foot" ? 1 : 0
        border.color: Commons.Util.alpha(root.accent, 0.55)
        HoverHandler { id: powerHov }
        Rectangle {  // Settings: the gear, there while the row is pointed at (or they're open)
          id: gear
          opacity: powerHov.hovered || root.settingsOpen || root.kbArea === "foot" ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 120 } }
          anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
          width: 34
          height: 32
          radius: 6
          color: gearHit.containsMouse || root.settingsOpen || root.kbFootKind === "gear" ? Commons.Util.alpha(root.accent, 0.25) : "transparent"
          Text { anchors.centerIn: parent; text: "\uf013"; color: root.text; font.family: root.iconFont; font.pixelSize: 15 }
          MouseArea { id: gearHit; anchors.fill: parent; hoverEnabled: true; onClicked: { if (root.settingsOpen) root.settingsOpen = false; else root.openSettings(); search.forceActiveFocus() } }
        }
        // At the right end: Lock, and Power. Power's click opens the rest
        // (Screensaver, Suspend, ..., Shutdown) between them, pushing Lock to
        // the left; again, closes them.
        Item {
          id: powerRoom
          anchors { left: gear.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 4; rightMargin: 6 }
          clip: true
          // The rest with their names, to see whether they fit (never shown).
          Row {
            id: restNamed
            opacity: 0
            enabled: false
            spacing: 4
            Repeater {
              model: root.powerRest
              PowerButton { required property var modelData; entry: modelData }
            }
          }
          readonly property bool namesFit: lockRow.implicitWidth + 4 + restNamed.implicitWidth + 4 + powerToggle.width <= width
          Text {
            visible: !powerRoom.namesFit && root.powerOpen && root.powerHint !== ""
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            text: root.powerHint
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            Row {
              id: lockRow
              spacing: 4
              Repeater {
                model: root.powerLock
                PowerButton { required property var modelData; entry: modelData }
              }
            }
            Item {  // the rest: opens to its width, closes to nothing
              id: powerRest
              width: root.powerOpen ? restRow.implicitWidth : 0
              height: 32
              clip: true
              Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
              Row {
                id: restRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                opacity: root.powerOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Repeater {
                  model: root.powerRest
                  // No room for their names (the narrow menu): icons, and the
                  // one pointed at named at the row's left.
                  PowerButton { required property var modelData; entry: modelData; compact: !powerRoom.namesFit }
                }
              }
            }
            Rectangle {  // Power
              id: powerToggle
              width: ptRow.implicitWidth + 22
              height: 32
              radius: 6
              color: root.powerOpen || root.kbFootKind === "toggle" ? Commons.Util.alpha(root.accent, 0.3) : ptHit.containsMouse ? Commons.Util.alpha(root.accent, 0.2) : Commons.Util.alpha(root.text, 0.06)
              Behavior on color { ColorAnimation { duration: 120 } }
              Row {
                id: ptRow
                anchors.centerIn: parent
                spacing: 7
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{F0425}"; color: root.text; font.family: root.iconFont; font.pixelSize: 15 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Power"; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                Text { anchors.verticalCenter: parent.verticalCenter; text: root.powerOpen ? "›" : "‹"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
              }
              MouseArea { id: ptHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.powerOpen = !root.powerOpen; search.forceActiveFocus() } }
            }
          }
        }
      }
    }
  }
}
