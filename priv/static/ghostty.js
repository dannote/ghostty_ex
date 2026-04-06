const GhosttyTerminal = {
  mounted() {
    this.cols = parseInt(this.el.dataset.cols)
    this.rows = parseInt(this.el.dataset.rows)
    this.fit = this.el.dataset.fit === "true"
    this.autofocus = this.el.dataset.autofocus === "true"
    this.rowsData = []
    this.cursor = null
    this.mouse = { tracking: false, x10: false, normal: false, button: false, any: false, sgr: false }
    this.focused = false
    this.composing = false
    this.cursorBlinkVisible = true
    this.cursorBlinkTimer = null
    this.target = this.el.getAttribute("phx-target")
    this.resizeObserver = null
    this.pendingFitTimer = null
    this.lastFitCols = null
    this.lastFitRows = null
    this.selectionAnchor = null
    this.selectionFocus = null
    this.selecting = false
    this.pointerActive = false
    this.autofocusTimers = []
    this.readySent = false
    this.autofocusPending = this.autofocus

    this.el.tabIndex = 0
    this.el.style.position = "relative"
    this.el.style.outline = "none"

    this.input = this.el.querySelector("textarea[data-ghostty-input='true']") || document.createElement("textarea")

    for (const child of Array.from(this.el.children)) {
      if (child !== this.input) {
        child.remove()
      }
    }

    this.screen = document.createElement("div")
    this.screen.style.position = "relative"
    this.screen.style.display = "block"
    this.screen.style.width = "100%"
    this.el.appendChild(this.screen)

    this.pre = document.createElement("pre")
    this.pre.style.margin = "0"
    this.pre.style.padding = "8px"
    this.pre.style.backgroundColor = "#1e1e2e"
    this.pre.style.color = "#cdd6f4"
    this.pre.style.overflow = "hidden"
    this.pre.style.position = "relative"
    this.pre.style.width = "100%"
    this.pre.style.boxSizing = "border-box"
    this.pre.style.userSelect = "none"
    this.pre.style.webkitUserSelect = "none"
    this.pre.style.cursor = "text"
    this.screen.appendChild(this.pre)

    this.selectionLayer = document.createElement("div")
    this.selectionLayer.setAttribute("aria-hidden", "true")
    this.selectionLayer.setAttribute("data-ghostty-selection-layer", "true")
    this.selectionLayer.style.position = "absolute"
    this.selectionLayer.style.inset = "0"
    this.selectionLayer.style.pointerEvents = "none"
    this.selectionLayer.style.zIndex = "0"
    this.screen.appendChild(this.selectionLayer)

    this.measure = document.createElement("span")
    this.measure.textContent = "MMMMMMMMMM"
    this.measure.setAttribute("aria-hidden", "true")
    this.measure.style.position = "absolute"
    this.measure.style.visibility = "hidden"
    this.measure.style.pointerEvents = "none"
    this.measure.style.whiteSpace = "pre"
    this.measure.style.font = "inherit"
    this.measure.style.lineHeight = "inherit"
    this.screen.appendChild(this.measure)

    this.input.setAttribute("data-ghostty-input", "true")
    this.input.setAttribute("aria-label", "Terminal input")
    this.input.setAttribute("autocapitalize", "off")
    this.input.setAttribute("autocomplete", "off")
    this.input.setAttribute("autocorrect", "off")
    this.input.setAttribute("spellcheck", "false")
    this.input.style.position = "absolute"
    this.input.style.left = "0"
    this.input.style.top = "0"
    this.input.style.width = "1px"
    this.input.style.height = "1em"
    this.input.style.padding = "0"
    this.input.style.margin = "0"
    this.input.style.border = "0"
    this.input.style.outline = "none"
    this.input.style.opacity = "0"
    this.input.style.resize = "none"
    this.input.style.overflow = "hidden"
    this.input.style.background = "transparent"
    this.input.style.color = "transparent"
    this.input.style.caretColor = "transparent"
    this.input.style.whiteSpace = "pre"
    this.input.style.pointerEvents = "none"
    this.input.style.zIndex = "2"
    this.screen.appendChild(this.input)

    this.cursorEl = document.createElement("div")
    this.cursorEl.setAttribute("aria-hidden", "true")
    this.cursorEl.style.position = "absolute"
    this.cursorEl.style.display = "none"
    this.cursorEl.style.pointerEvents = "none"
    this.cursorEl.style.boxSizing = "border-box"
    this.cursorEl.style.whiteSpace = "pre"
    this.cursorEl.style.zIndex = "1"

    this.cursorText = document.createElement("span")
    this.cursorText.style.display = "block"
    this.cursorText.style.width = "100%"
    this.cursorText.style.height = "100%"
    this.cursorText.style.font = "inherit"
    this.cursorText.style.lineHeight = "inherit"
    this.cursorEl.appendChild(this.cursorText)
    this.screen.appendChild(this.cursorEl)

    this.onContainerFocus = () => {
      this.focused = true
      this.cursorBlinkVisible = true
      this.syncCursorBlink()
      this.renderCursor()
      this.focusInput(true)
    }
    this.onContainerBlur = () => {
      window.setTimeout(() => {
        if (document.activeElement !== this.el && document.activeElement !== this.input) {
          this.focused = false
          this.cursorBlinkVisible = true
          this.syncCursorBlink()
          this.renderCursor()
        }
      }, 0)
    }
    this.onPointerDown = (e) => this.handlePointerDown(e)
    this.onPointerMove = (e) => this.handlePointerMove(e)
    this.onPointerUp = (e) => this.handlePointerUp(e)
    this.onDocumentPointerDown = (e) => {
      if (!this.isInsideTerminal(e.target)) {
        this.disableAutofocus()
        this.blurTerminal()
      }
    }
    this.onDocumentFocusIn = (e) => {
      if (!this.isInsideTerminal(e.target)) {
        this.disableAutofocus()
      }
    }
    this.onContextMenu = (e) => {
      if (this.selecting) {
        e.preventDefault()
      }
    }
    this.onWindowResize = () => {
      this.scheduleFit()
      this.renderSelection()
      this.renderCursor()
    }

    this.onKeydown = (e) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return
      }

      if (this.composing) {
        return
      }

      if (this.isCopyShortcut(e) && this.hasSelection()) {
        e.preventDefault()
        this.copySelection()
        return
      }

      if (this.isPasteShortcut(e)) {
        return
      }

      e.preventDefault()
      this.pushHookEvent("key", {
        key: e.key,
        shiftKey: e.shiftKey,
        ctrlKey: e.ctrlKey,
        altKey: e.altKey,
        metaKey: e.metaKey,
      })
      this.clearInput()
    }

    this.onPaste = (e) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return
      }

      const text = e.clipboardData?.getData("text") || ""
      if (text === "") {
        return
      }

      e.preventDefault()
      this.clearSelection()
      this.pushHookEvent("text", { data: text })
      this.clearInput()
    }

    this.onCopy = (e) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return
      }

      if (!this.hasSelection()) {
        return
      }

      e.preventDefault()
      this.writeClipboard(e.clipboardData, this.selectedText())
    }

    this.onCompositionStart = () => {
      this.composing = true
    }

    this.onCompositionEnd = (e) => {
      this.composing = false
      if (e.data) {
        this.clearSelection()
        this.pushHookEvent("text", { data: e.data })
      }
      this.clearInput()
    }

    this.onInputFocus = () => {
      this.focused = true
      this.cursorBlinkVisible = true
      this.autofocusPending = false
      this.stopAutofocus()
      this.pushHookEvent("focus", { focused: true })
      this.syncCursorBlink()
      this.renderCursor()
    }

    this.onInputBlur = () => {
      this.focused = false
      this.cursorBlinkVisible = true
      if (!this.isInsideTerminal(document.activeElement)) {
        this.autofocusPending = false
        this.stopAutofocus()
      }
      this.pushHookEvent("focus", { focused: false })
      this.syncCursorBlink()
      this.renderCursor()
    }

    this.el.addEventListener("focus", this.onContainerFocus)
    this.el.addEventListener("blur", this.onContainerBlur)
    this.el.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("paste", this.onPaste)
    this.el.addEventListener("copy", this.onCopy)
    this.el.addEventListener("mousedown", this.onPointerDown)
    window.addEventListener("mousemove", this.onPointerMove)
    window.addEventListener("mouseup", this.onPointerUp)
    document.addEventListener("mousedown", this.onDocumentPointerDown, true)
    document.addEventListener("focusin", this.onDocumentFocusIn, true)
    this.el.addEventListener("contextmenu", this.onContextMenu)
    window.addEventListener("resize", this.onWindowResize)
    window.addEventListener("scroll", this.onWindowResize, true)
    this.input.addEventListener("keydown", this.onKeydown)
    this.input.addEventListener("paste", this.onPaste)
    this.input.addEventListener("copy", this.onCopy)
    this.input.addEventListener("compositionstart", this.onCompositionStart)
    this.input.addEventListener("compositionend", this.onCompositionEnd)
    this.input.addEventListener("focus", this.onInputFocus)
    this.input.addEventListener("blur", this.onInputBlur)

    if (this.fit && typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(() => this.scheduleFit())
      this.resizeObserver.observe(this.el)
    }

    this.handleEvent("ghostty:render", ({ id, cells, cursor, mouse }) => {
      if (id !== this.el.id) return
      this.rowsData = cells
      this.cursor = cursor
      this.cols = cells[0]?.length || this.cols
      this.rows = cells.length || this.rows
      this.mouse = mouse || { tracking: false, x10: false, normal: false, button: false, any: false, sgr: false }
      if (this.mouseModeActive()) {
        this.clearSelection()
      }
      this.renderCells(cells)
      this.renderSelection()
      this.syncCursorBlink()
      this.renderCursor()
      this.scheduleFit()
      this.sendReady()
    })

    if (this.target) {
      this.pushEventTo(this.target, "refresh", {})
    }

    window.addEventListener("pageshow", this.onWindowResize)
    window.requestAnimationFrame(() => this.sendReady())
    window.setTimeout(() => this.sendReady(), 50)
    this.scheduleAutofocus()
  },

  destroyed() {
    this.stopCursorBlink()
    this.stopAutofocus()
    if (this.pendingFitTimer) {
      window.clearTimeout(this.pendingFitTimer)
      this.pendingFitTimer = null
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    }
    window.removeEventListener("mousemove", this.onPointerMove)
    window.removeEventListener("mouseup", this.onPointerUp)
    document.removeEventListener("mousedown", this.onDocumentPointerDown, true)
    document.removeEventListener("focusin", this.onDocumentFocusIn, true)
    window.removeEventListener("resize", this.onWindowResize)
    window.removeEventListener("scroll", this.onWindowResize, true)
    window.removeEventListener("pageshow", this.onWindowResize)
  },

  renderCells(rows) {
    let html = ""
    for (const row of rows) {
      for (const [char, fg, bg, flags] of row) {
        const styles = this.cellStyles(fg, bg, flags)
        const ch = char || " "
        if (styles.length > 0) {
          html += `<span style="${styles.join(";")}">${esc(ch)}</span>`
        } else {
          html += esc(ch)
        }
      }
      html += "\n"
    }
    this.pre.innerHTML = html
  },

  renderSelection() {
    this.selectionLayer.innerHTML = ""

    if (this.mouseModeActive()) {
      return
    }

    const selection = this.normalizedSelection()
    if (!selection) {
      return
    }

    const metrics = this.measureCellMetrics()

    for (let row = selection.start.row; row <= selection.end.row; row += 1) {
      const startCol = row === selection.start.row ? selection.start.col : 0
      const endCol = row === selection.end.row ? selection.end.col : this.cols - 1
      const rect = document.createElement("div")
      rect.style.position = "absolute"
      rect.style.left = `${metrics.paddingLeft + startCol * metrics.width}px`
      rect.style.top = `${metrics.paddingTop + row * metrics.height}px`
      rect.style.width = `${Math.max(1, endCol - startCol + 1) * metrics.width}px`
      rect.style.height = `${metrics.height}px`
      rect.style.background = "rgba(137, 180, 250, 0.35)"
      rect.style.borderRadius = "2px"
      this.selectionLayer.appendChild(rect)
    }
  },

  renderCursor() {
    if (!this.cursorVisible()) {
      this.cursorEl.style.display = "none"
      this.syncInputPosition(null)
      return
    }

    const metrics = this.measureCellMetrics()
    const cursor = this.cursor
    let leftCol = cursor.x
    let widthCols = 1

    if (cursor.wide_tail && cursor.x > 0) {
      leftCol -= 1
      widthCols = 2
    }

    const left = metrics.paddingLeft + leftCol * metrics.width
    const top = metrics.paddingTop + cursor.y * metrics.height
    const width = metrics.width * widthCols
    const height = metrics.height
    const style = this.cursorDisplayStyle(cursor.style)
    const color = this.cursorColor()

    this.syncInputPosition({ left, top, height })

    this.cursorEl.style.display = "block"
    this.cursorEl.style.left = `${left}px`
    this.cursorEl.style.top = `${top}px`
    this.cursorEl.style.width = `${width}px`
    this.cursorEl.style.height = `${height}px`
    this.cursorEl.style.opacity = this.focused ? "1" : "0.85"

    this.cursorText.textContent = ""
    this.cursorText.style.color = ""
    this.cursorText.style.backgroundColor = "transparent"
    this.cursorText.style.fontWeight = ""
    this.cursorText.style.fontStyle = ""
    this.cursorText.style.opacity = "1"
    this.cursorText.style.textDecoration = "none"

    this.cursorEl.style.backgroundColor = "transparent"
    this.cursorEl.style.border = "none"
    this.cursorEl.style.borderBottom = "none"
    this.cursorEl.style.borderLeft = "none"

    if (style === "block") {
      const cell = this.cursorCell()
      this.cursorEl.style.backgroundColor = color
      this.cursorText.textContent = this.cursorChar(cell)
      this.cursorText.style.color = this.cursorTextColor(cell)
      this.applyCellTextStyles(this.cursorText, cell)
      return
    }

    if (style === "underline") {
      this.cursorEl.style.borderBottom = `2px solid ${color}`
      return
    }

    if (style === "bar") {
      const barWidth = Math.max(2, Math.round(metrics.width * 0.15))
      this.cursorEl.style.width = `${barWidth}px`
      this.cursorEl.style.backgroundColor = color
      return
    }

    this.cursorEl.style.border = `1px solid ${color}`
  },

  handlePointerDown(e) {
    if (!this.pointerTargetsTerminal(e.target)) {
      return
    }

    const point = this.cellPointFromEvent(e)
    if (!point) {
      return
    }

    this.pointerActive = true
    this.focusInput(true)

    if (!this.mouseModeActive() && e.button === 0 && !this.hasMouseModifiers(e)) {
      this.selecting = true
      this.selectionAnchor = point
      this.selectionFocus = point
      this.renderSelection()
      e.preventDefault()
    }

    this.pushMouseEvent("press", e, point)
  },

  handlePointerMove(e) {
    if (!this.pointerActive) {
      return
    }

    const point = this.cellPointFromEvent(e)
    if (!point) {
      return
    }

    if (this.selecting && !this.mouseModeActive()) {
      this.selectionFocus = point
      this.renderSelection()
      e.preventDefault()
    }

    if (e.buttons !== 0) {
      this.pushMouseEvent("motion", e, point)
    }
  },

  handlePointerUp(e) {
    if (!this.pointerActive) {
      return
    }

    this.pointerActive = false
    const point = this.cellPointFromEvent(e)

    if (this.selecting && point && !this.mouseModeActive()) {
      this.selectionFocus = point
      this.selecting = false
      if (this.selectionCollapsed()) {
        this.clearSelection()
        this.focusInput(true)
      } else {
        this.renderSelection()
      }
    } else if (!this.hasSelection()) {
      this.focusInput(true)
    }

    if (point) {
      this.pushMouseEvent("release", e, point)
    }
  },

  pointerTargetsTerminal(target) {
    return target === this.el || target === this.pre || this.pre.contains(target)
  },

  pushMouseEvent(action, e, point) {
    this.pushHookEvent("mouse", {
      action,
      button: this.mouseButtonName(action === "motion" ? this.primaryPressedButton(e) : e.button),
      x: point.encodeX,
      y: point.encodeY,
      shiftKey: e.shiftKey,
      ctrlKey: e.ctrlKey,
      altKey: e.altKey,
      metaKey: e.metaKey,
    })
  },

  mouseButtonName(button) {
    switch (button) {
      case 0:
        return "left"
      case 1:
        return "middle"
      case 2:
        return "right"
      case 3:
        return "four"
      case 4:
        return "five"
      default:
        return null
    }
  },

  primaryPressedButton(e) {
    if (e.buttons & 1) return 0
    if (e.buttons & 4) return 1
    if (e.buttons & 2) return 2
    if (e.buttons & 8) return 3
    if (e.buttons & 16) return 4
    return -1
  },

  hasMouseModifiers(e) {
    return e.shiftKey || e.ctrlKey || e.altKey || e.metaKey
  },

  cellPointFromEvent(e) {
    const metrics = this.measureCellMetrics()
    const rect = this.pre.getBoundingClientRect()
    const x = e.clientX - rect.left - metrics.paddingLeft
    const y = e.clientY - rect.top - metrics.paddingTop

    if (x < 0 || y < 0) {
      return null
    }

    const col = clamp(Math.floor(x / metrics.width), 0, this.cols - 1)
    const row = clamp(Math.floor(y / metrics.height), 0, this.rows - 1)

    return {
      col,
      row,
      encodeX: col * 10 + 5,
      encodeY: row * 20 + 10,
    }
  },

  hasSelection() {
    return !this.mouseModeActive() && Boolean(this.normalizedSelection())
  },

  selectionCollapsed() {
    return Boolean(
      this.selectionAnchor &&
        this.selectionFocus &&
        this.selectionAnchor.col === this.selectionFocus.col &&
        this.selectionAnchor.row === this.selectionFocus.row,
    )
  },

  clearSelection() {
    this.selectionAnchor = null
    this.selectionFocus = null
    this.selecting = false
    this.selectionLayer.innerHTML = ""
  },

  mouseModeActive() {
    return Boolean(this.mouse?.tracking)
  },

  normalizedSelection() {
    if (!this.selectionAnchor || !this.selectionFocus) {
      return null
    }

    const start = { ...this.selectionAnchor }
    const end = { ...this.selectionFocus }

    if (end.row < start.row || (end.row === start.row && end.col < start.col)) {
      return { start: end, end: start }
    }

    if (start.row === end.row && start.col === end.col) {
      return null
    }

    return { start, end }
  },

  selectedText() {
    const selection = this.normalizedSelection()
    if (!selection) {
      return ""
    }

    const lines = []

    for (let row = selection.start.row; row <= selection.end.row; row += 1) {
      const sourceRow = this.rowsData[row] || []
      const startCol = row === selection.start.row ? selection.start.col : 0
      const endCol = row === selection.end.row ? selection.end.col : this.cols - 1
      let text = ""

      for (let col = startCol; col <= endCol; col += 1) {
        const cell = sourceRow[col]
        text += cell?.[0] || " "
      }

      lines.push(text)
    }

    return lines.join("\n")
  },

  async copySelection() {
    const text = this.selectedText()
    if (text === "") {
      return
    }

    if (navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(text)
        return
      } catch (_error) {}
    }

    this.input.value = text
    this.input.select()
    document.execCommand("copy")
    this.clearInput()
    this.focusInput()
  },

  writeClipboard(clipboardData, text) {
    if (clipboardData?.setData) {
      clipboardData.setData("text/plain", text)
    }
  },

  cursorVisible() {
    return Boolean(
      this.cursor &&
        this.cursor.visible &&
        this.cursor.x != null &&
        this.cursor.y != null &&
        this.cursorBlinkVisible,
    )
  },

  cursorDisplayStyle(style) {
    if (!this.focused && style === "block") {
      return "block_hollow"
    }

    return style
  },

  cursorCell() {
    if (!this.cursor || this.cursor.y == null || this.cursor.x == null) return null

    const row = this.rowsData[this.cursor.y]
    if (!row) return null

    if (this.cursor.wide_tail && this.cursor.x > 0) {
      return row[this.cursor.x - 1] || null
    }

    return row[this.cursor.x] || null
  },

  cursorChar(cell) {
    return cell?.[0] || " "
  },

  cursorColor() {
    if (this.cursor?.color) {
      return rgb(this.cursor.color)
    }

    return window.getComputedStyle(this.pre).color || "#cdd6f4"
  },

  cursorTextColor(cell) {
    if (cell?.[2]) {
      return rgb(cell[2])
    }

    return window.getComputedStyle(this.pre).backgroundColor || "#1e1e2e"
  },

  syncCursorBlink() {
    this.stopCursorBlink()

    if (this.cursor?.visible && this.cursor?.blinking && this.focused) {
      this.cursorBlinkTimer = window.setInterval(() => {
        this.cursorBlinkVisible = !this.cursorBlinkVisible
        this.renderCursor()
      }, 600)
      return
    }

    this.cursorBlinkVisible = true
  },

  stopCursorBlink() {
    if (this.cursorBlinkTimer) {
      window.clearInterval(this.cursorBlinkTimer)
      this.cursorBlinkTimer = null
    }
  },

  focusInput(force = false) {
    if (!force && !this.shouldAutofocus()) {
      return
    }

    if (document.activeElement !== this.el) {
      this.el.focus({ preventScroll: true })
    }

    if (document.activeElement !== this.input) {
      this.input.focus({ preventScroll: true })
    }
  },

  blurTerminal() {
    this.pointerActive = false

    if (document.activeElement === this.input) {
      this.input.blur()
    }

    if (document.activeElement === this.el) {
      this.el.blur()
    }

    this.focused = false
    this.cursorBlinkVisible = true
    this.syncCursorBlink()
    this.renderCursor()
  },

  disableAutofocus() {
    this.autofocusPending = false
    this.stopAutofocus()
  },

  shouldAutofocus() {
    const active = document.activeElement

    if (!active || active === document.body || active === document.documentElement) {
      return true
    }

    return this.isInsideTerminal(active)
  },

  isInsideTerminal(node) {
    return Boolean(node && (node === this.el || node === this.input || this.el.contains(node)))
  },

  scheduleAutofocus() {
    if (!this.autofocusPending) {
      return
    }

    if (document.activeElement === this.input) {
      this.disableAutofocus()
      return
    }

    this.stopAutofocus()

    for (const delay of [0, 50, 150, 300, 600, 1000]) {
      const timer = window.setTimeout(() => {
        if (!this.el.isConnected || document.activeElement === this.input) {
          return
        }

        if (!this.shouldAutofocus()) {
          this.disableAutofocus()
          return
        }

        this.focusInput()
      }, delay)

      this.autofocusTimers.push(timer)
    }
  },

  stopAutofocus() {
    for (const timer of this.autofocusTimers) {
      window.clearTimeout(timer)
    }

    this.autofocusTimers = []
  },

  clearInput() {
    this.input.value = ""
  },

  syncInputPosition(position) {
    if (!position) {
      this.input.style.left = "0"
      this.input.style.top = "0"
      return
    }

    this.input.style.left = `${position.left}px`
    this.input.style.top = `${position.top}px`
    this.input.style.height = `${position.height}px`
  },

  pushHookEvent(name, payload) {
    if (this.target) {
      this.pushEventTo(this.target, name, payload)
    } else {
      this.pushEvent(name, payload)
    }
  },

  scheduleFit() {
    if (!this.fit) {
      return
    }

    if (this.pendingFitTimer) {
      window.clearTimeout(this.pendingFitTimer)
    }

    this.pendingFitTimer = window.setTimeout(() => {
      this.pendingFitTimer = null
      this.fitToContainer()
    }, 75)
  },

  sendReady() {
    if (this.readySent) {
      return
    }

    const size = this.fit ? this.currentFitSize() : { cols: this.cols, rows: this.rows }

    if (!size) {
      return
    }

    this.lastFitCols = size.cols
    this.lastFitRows = size.rows
    this.pushHookEvent("ready", size)
    this.readySent = true
  },

  fitToContainer() {
    const size = this.currentFitSize()

    if (!size) {
      return
    }

    const { cols, rows } = size

    if (cols === this.lastFitCols && rows === this.lastFitRows) {
      return
    }

    this.lastFitCols = cols
    this.lastFitRows = rows
    this.pushHookEvent("resize", { cols, rows })
  },

  currentFitSize() {
    const metrics = this.measureCellMetrics()
    const rect = this.el.getBoundingClientRect()
    const preRect = this.pre.getBoundingClientRect()

    const availableWidth = Math.max(0, rect.width - metrics.paddingLeft - metrics.paddingRight)
    const availableHeight = Math.max(0, preRect.height - metrics.paddingTop - metrics.paddingBottom)

    if (availableWidth < metrics.width * 20 || availableHeight < metrics.height * 5) {
      return null
    }

    return {
      cols: Math.max(2, Math.floor(availableWidth / metrics.width)),
      rows: Math.max(2, Math.floor(availableHeight / metrics.height)),
    }
  },

  isCopyShortcut(e) {
    return (e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === "c"
  },

  isPasteShortcut(e) {
    return (e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === "v"
  },

  measureCellMetrics() {
    const styles = window.getComputedStyle(this.pre)

    this.measure.style.fontFamily = styles.fontFamily
    this.measure.style.fontSize = styles.fontSize
    this.measure.style.fontWeight = styles.fontWeight
    this.measure.style.fontStyle = styles.fontStyle
    this.measure.style.lineHeight = styles.lineHeight

    this.input.style.fontFamily = styles.fontFamily
    this.input.style.fontSize = styles.fontSize
    this.input.style.lineHeight = styles.lineHeight
    this.cursorEl.style.fontFamily = styles.fontFamily
    this.cursorEl.style.fontSize = styles.fontSize
    this.cursorEl.style.lineHeight = styles.lineHeight

    const measureRect = this.measure.getBoundingClientRect()
    const fontSize = parseFloat(styles.fontSize) || 16
    const lineHeight = parseFloat(styles.lineHeight) || fontSize * 1.2
    const width = measureRect.width > 0 ? measureRect.width / 10 : fontSize * 0.6

    return {
      width,
      height: lineHeight,
      paddingLeft: parseFloat(styles.paddingLeft) || 0,
      paddingRight: parseFloat(styles.paddingRight) || 0,
      paddingTop: parseFloat(styles.paddingTop) || 0,
      paddingBottom: parseFloat(styles.paddingBottom) || 0,
    }
  },

  cellStyles(fg, bg, flags) {
    const styles = []
    const decorations = []

    if (fg) styles.push(`color:${rgb(fg)}`)
    if (bg) styles.push(`background:${rgb(bg)}`)
    if (flags & 1) styles.push("font-weight:bold")
    if (flags & 2) styles.push("font-style:italic")
    if (flags & 4) styles.push("opacity:0.5")
    if (flags & 8) decorations.push("underline")
    if (flags & 16) decorations.push("line-through")
    if (flags & 128) decorations.push("overline")
    if (decorations.length > 0) styles.push(`text-decoration:${decorations.join(" ")}`)

    return styles
  },

  applyCellTextStyles(el, cell) {
    if (!cell) return

    const [, , , flags] = cell
    const decorations = []

    el.style.fontWeight = flags & 1 ? "bold" : ""
    el.style.fontStyle = flags & 2 ? "italic" : ""
    el.style.opacity = flags & 4 ? "0.5" : "1"
    if (flags & 8) decorations.push("underline")
    if (flags & 16) decorations.push("line-through")
    if (flags & 128) decorations.push("overline")
    el.style.textDecoration = decorations.length > 0 ? decorations.join(" ") : "none"
  },
}

function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function rgb(color) {
  return `rgb(${color[0]},${color[1]},${color[2]})`
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

export {GhosttyTerminal}
