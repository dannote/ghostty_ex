import { renderCursor } from './cursor'
import {
  createCursorEl,
  createMeasure,
  createPre,
  createScreen,
  createSelectionLayer,
  measureCellMetrics,
  setupInput
} from './dom'
import {
  hasMouseModifiers,
  isCopyShortcut,
  isPasteShortcut,
  mouseButtonName,
  primaryPressedButton
} from './input'
import { renderCells, renderSelection } from './render'
import { normalizeSelection, selectedText } from './selection'
import { DEFAULT_MOUSE } from './types'
import { clamp } from './util'

import type {
  Cell,
  CellMetrics,
  CellPoint,
  CursorState,
  MouseModes,
  RenderPayload,
  ScrollbarState
} from './types'

interface TerminalState {
  cols: number
  rows: number
  fit: boolean
  autofocus: boolean
  rowsData: Cell[][]
  cursor: CursorState | null
  mouse: MouseModes
  scrollbar: ScrollbarState | null
  focusReporting: boolean
  focused: boolean
  composing: boolean
  cursorBlinkVisible: boolean
  cursorBlinkTimer: ReturnType<typeof setInterval> | null
  target: string | null
  resizeObserver: ResizeObserver | null
  pendingFitTimer: ReturnType<typeof setTimeout> | null
  lastFitCols: number | null
  lastFitRows: number | null
  selectionAnchor: CellPoint | null
  selectionFocus: CellPoint | null
  selecting: boolean
  pointerActive: boolean
  autofocusTimers: ReturnType<typeof setTimeout>[]
  readySent: boolean
  autofocusPending: boolean

  screen: HTMLDivElement
  pre: HTMLPreElement
  selectionLayer: HTMLDivElement
  measure: HTMLSpanElement
  input: HTMLTextAreaElement
  cursorEl: HTMLDivElement
  cursorText: HTMLSpanElement

  onContainerFocus: () => void
  onContainerBlur: () => void
  onPointerDown: (e: MouseEvent) => void
  onPointerMove: (e: MouseEvent) => void
  onPointerUp: (e: MouseEvent) => void
  onDocumentPointerDown: (e: MouseEvent) => void
  onDocumentFocusIn: (e: FocusEvent) => void
  onContextMenu: (e: Event) => void
  onWindowResize: () => void
  onKeydown: (e: KeyboardEvent) => void
  onPaste: (e: ClipboardEvent) => void
  onCopy: (e: ClipboardEvent) => void
  onCompositionStart: () => void
  onCompositionEnd: (e: CompositionEvent) => void
  onInputFocus: () => void
  onInputBlur: () => void
}

// Phoenix LiveView hook methods
interface HookMethods {
  el: HTMLElement
  pushEvent(event: string, payload: object): void
  pushEventTo(target: string, event: string, payload: object): void
  handleEvent(event: string, callback: (payload: never) => void): void
}

type Hook = TerminalState & HookMethods

function pushHookEvent(hook: Hook, name: string, payload: object): void {
  if (hook.target) {
    hook.pushEventTo(hook.target, name, payload)
  } else {
    hook.pushEvent(name, payload)
  }
}

function metrics(hook: Hook): CellMetrics {
  return measureCellMetrics(hook.pre, hook.measure, hook.input, hook.cursorEl)
}

function isInsideTerminal(hook: Hook, node: Node | null): boolean {
  return Boolean(node && (node === hook.el || node === hook.input || hook.el.contains(node)))
}

function mouseModeActive(hook: Hook): boolean {
  return Boolean(hook.mouse?.tracking)
}

function hasSelection(hook: Hook): boolean {
  return (
    !mouseModeActive(hook) && normalizeSelection(hook.selectionAnchor, hook.selectionFocus) !== null
  )
}

function clearSelection(hook: Hook): void {
  hook.selectionAnchor = null
  hook.selectionFocus = null
  hook.selecting = false
  hook.selectionLayer.innerHTML = ''
}

function focusInput(hook: Hook, force = false): void {
  if (!force && !shouldAutofocus(hook)) {
    return
  }
  if (document.activeElement !== hook.el) {
    hook.el.focus({ preventScroll: true })
  }
  if (document.activeElement !== hook.input) {
    hook.input.focus({ preventScroll: true })
  }
}

function blurTerminal(hook: Hook): void {
  hook.pointerActive = false
  if (document.activeElement === hook.input) {
    hook.input.blur()
  }
  if (document.activeElement === hook.el) {
    hook.el.blur()
  }
  hook.focused = false
  hook.cursorBlinkVisible = true
  syncCursorBlink(hook)
  doRenderCursor(hook)
}

function disableAutofocus(hook: Hook): void {
  hook.autofocusPending = false
  stopAutofocus(hook)
}

function shouldAutofocus(hook: Hook): boolean {
  const active = document.activeElement
  if (!active || active === document.body || active === document.documentElement) {
    return true
  }
  return isInsideTerminal(hook, active)
}

function scheduleAutofocus(hook: Hook): void {
  if (!hook.autofocusPending) {
    return
  }
  if (document.activeElement === hook.input) {
    disableAutofocus(hook)
    return
  }
  stopAutofocus(hook)

  for (const delay of [0, 50, 150, 300, 600, 1000]) {
    const timer = setTimeout(() => {
      if (!hook.el.isConnected || document.activeElement === hook.input) {
        return
      }
      if (!shouldAutofocus(hook)) {
        disableAutofocus(hook)
        return
      }
      focusInput(hook)
    }, delay)
    hook.autofocusTimers.push(timer)
  }
}

function stopAutofocus(hook: Hook): void {
  for (const timer of hook.autofocusTimers) {
    clearTimeout(timer)
  }
  hook.autofocusTimers = []
}

function syncCursorBlink(hook: Hook): void {
  stopCursorBlink(hook)
  if (hook.cursor?.visible && hook.cursor?.blinking && hook.focused) {
    hook.cursorBlinkTimer = setInterval(() => {
      hook.cursorBlinkVisible = !hook.cursorBlinkVisible
      doRenderCursor(hook)
    }, 600)
    return
  }
  hook.cursorBlinkVisible = true
}

function stopCursorBlink(hook: Hook): void {
  if (hook.cursorBlinkTimer !== null) {
    clearInterval(hook.cursorBlinkTimer)
    hook.cursorBlinkTimer = null
  }
}

function doRenderCursor(hook: Hook): void {
  renderCursor(
    hook.cursorEl,
    hook.cursorText,
    hook.cursor,
    hook.rowsData,
    hook.focused,
    hook.cursorBlinkVisible,
    metrics(hook),
    hook.pre,
    hook.input
  )
}

function doRenderSelection(hook: Hook): void {
  const sel = mouseModeActive(hook)
    ? null
    : normalizeSelection(hook.selectionAnchor, hook.selectionFocus)
  renderSelection(hook.selectionLayer, sel, hook.cols, metrics(hook))
}

function cellPointFromEvent(hook: Hook, e: MouseEvent): CellPoint | null {
  const m = metrics(hook)
  const rect = hook.pre.getBoundingClientRect()
  const x = e.clientX - rect.left - m.paddingLeft
  const y = e.clientY - rect.top - m.paddingTop

  if (x < 0 || y < 0) {
    return null
  }

  const col = clamp(Math.floor(x / m.width), 0, hook.cols - 1)
  const row = clamp(Math.floor(y / m.height), 0, hook.rows - 1)

  return { col, row, encodeX: col * 10 + 5, encodeY: row * 20 + 10 }
}

function pushMouseEvent(hook: Hook, action: string, e: MouseEvent, point: CellPoint): void {
  pushHookEvent(hook, 'mouse', {
    action,
    button: mouseButtonName(action === 'motion' ? primaryPressedButton(e) : e.button),
    x: point.encodeX,
    y: point.encodeY,
    shiftKey: e.shiftKey,
    ctrlKey: e.ctrlKey,
    altKey: e.altKey,
    metaKey: e.metaKey
  })
}

function pointerTargetsTerminal(hook: Hook, target: EventTarget | null): boolean {
  return target === hook.el || target === hook.pre || hook.pre.contains(target as Node)
}

function scheduleFit(hook: Hook): void {
  if (!hook.fit) {
    return
  }
  if (hook.pendingFitTimer !== null) {
    clearTimeout(hook.pendingFitTimer)
  }
  hook.pendingFitTimer = setTimeout(() => {
    hook.pendingFitTimer = null
    fitToContainer(hook)
  }, 75)
}

function currentFitSize(hook: Hook): { cols: number; rows: number } | null {
  const m = metrics(hook)
  const rect = hook.el.getBoundingClientRect()
  const preRect = hook.pre.getBoundingClientRect()

  const availableWidth = Math.max(0, rect.width - m.paddingLeft - m.paddingRight)
  const availableHeight = Math.max(0, preRect.height - m.paddingTop - m.paddingBottom)

  if (availableWidth < m.width * 20 || availableHeight < m.height * 5) {
    return null
  }

  return {
    cols: Math.max(2, Math.floor(availableWidth / m.width)),
    rows: Math.max(2, Math.floor(availableHeight / m.height))
  }
}

function fitToContainer(hook: Hook): void {
  const size = currentFitSize(hook)
  if (!size) {
    return
  }
  if (size.cols === hook.lastFitCols && size.rows === hook.lastFitRows) {
    return
  }
  hook.lastFitCols = size.cols
  hook.lastFitRows = size.rows
  pushHookEvent(hook, 'resize', size)
}

function sendReady(hook: Hook): void {
  if (hook.readySent) {
    return
  }
  const size = hook.fit ? currentFitSize(hook) : { cols: hook.cols, rows: hook.rows }
  if (!size) {
    return
  }
  hook.lastFitCols = size.cols
  hook.lastFitRows = size.rows
  pushHookEvent(hook, 'ready', size)
  hook.readySent = true
}

async function copySelectionToClipboard(hook: Hook): Promise<void> {
  const sel = normalizeSelection(hook.selectionAnchor, hook.selectionFocus)
  const text = selectedText(sel, hook.rowsData, hook.cols)
  if (text === '') {
    return
  }

  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text)
      return
    } catch {
      // fallback below
    }
  }

  hook.input.value = text
  hook.input.select()
  document.execCommand('copy')
  hook.input.value = ''
  focusInput(hook, true)
}

const GhosttyTerminal: ViewHookObject & Record<string, unknown> = {
  mounted(this: Hook) {
    this.cols = parseInt(this.el.dataset.cols ?? '80')
    this.rows = parseInt(this.el.dataset.rows ?? '24')
    this.fit = this.el.dataset.fit === 'true'
    this.autofocus = this.el.dataset.autofocus === 'true'
    this.rowsData = []
    this.cursor = null
    this.mouse = { ...DEFAULT_MOUSE }
    this.scrollbar = null
    this.focusReporting = false
    this.focused = false
    this.composing = false
    this.cursorBlinkVisible = true
    this.cursorBlinkTimer = null
    this.target = this.el.getAttribute('phx-target')
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
    this.el.style.position = 'relative'
    this.el.style.outline = 'none'

    this.input =
      (this.el.querySelector("textarea[data-ghostty-input='true']") as HTMLTextAreaElement) ??
      document.createElement('textarea')

    for (const child of Array.from(this.el.children)) {
      if (child !== this.input) {
        child.remove()
      }
    }

    this.screen = createScreen()
    this.el.appendChild(this.screen)

    this.pre = createPre()
    this.screen.appendChild(this.pre)

    this.selectionLayer = createSelectionLayer()
    this.screen.appendChild(this.selectionLayer)

    this.measure = createMeasure()
    this.screen.appendChild(this.measure)

    setupInput(this.input)
    this.screen.appendChild(this.input)

    const { cursorEl, cursorText } = createCursorEl()
    this.cursorEl = cursorEl
    this.cursorText = cursorText
    this.screen.appendChild(this.cursorEl)

    // Event handlers

    this.onContainerFocus = () => {
      this.focused = true
      this.cursorBlinkVisible = true
      syncCursorBlink(this)
      doRenderCursor(this)
      focusInput(this, true)
    }

    this.onContainerBlur = () => {
      setTimeout(() => {
        if (document.activeElement !== this.el && document.activeElement !== this.input) {
          this.focused = false
          this.cursorBlinkVisible = true
          syncCursorBlink(this)
          doRenderCursor(this)
        }
      }, 0)
    }

    this.onPointerDown = (e: MouseEvent) => {
      if (!pointerTargetsTerminal(this, e.target)) {
        return
      }
      const point = cellPointFromEvent(this, e)
      if (!point) {
        return
      }
      this.pointerActive = true
      focusInput(this, true)
      if (!mouseModeActive(this) && e.button === 0 && !hasMouseModifiers(e)) {
        this.selecting = true
        this.selectionAnchor = point
        this.selectionFocus = point
        doRenderSelection(this)
        e.preventDefault()
      }
      pushMouseEvent(this, 'press', e, point)
    }

    this.onPointerMove = (e: MouseEvent) => {
      if (!this.pointerActive) {
        return
      }
      const point = cellPointFromEvent(this, e)
      if (!point) {
        return
      }
      if (this.selecting && !mouseModeActive(this)) {
        this.selectionFocus = point
        doRenderSelection(this)
        e.preventDefault()
      }
      if (e.buttons !== 0) {
        pushMouseEvent(this, 'motion', e, point)
      }
    }

    this.onPointerUp = (e: MouseEvent) => {
      if (!this.pointerActive) {
        return
      }
      this.pointerActive = false
      const point = cellPointFromEvent(this, e)
      if (this.selecting && point && !mouseModeActive(this)) {
        this.selectionFocus = point
        this.selecting = false
        const sel = normalizeSelection(this.selectionAnchor, this.selectionFocus)
        if (!sel) {
          clearSelection(this)
          focusInput(this, true)
        } else {
          doRenderSelection(this)
        }
      } else if (!hasSelection(this)) {
        focusInput(this, true)
      }
      if (point) {
        pushMouseEvent(this, 'release', e, point)
      }
    }

    this.onDocumentPointerDown = (e: MouseEvent) => {
      if (!isInsideTerminal(this, e.target as Node)) {
        disableAutofocus(this)
        blurTerminal(this)
      }
    }

    this.onDocumentFocusIn = (e: FocusEvent) => {
      if (!isInsideTerminal(this, e.target as Node)) {
        disableAutofocus(this)
      }
    }

    this.onContextMenu = (e: Event) => {
      if (this.selecting) {
        e.preventDefault()
      }
    }

    this.onWindowResize = () => {
      scheduleFit(this)
      doRenderSelection(this)
      doRenderCursor(this)
    }

    this.onKeydown = (e: KeyboardEvent) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return
      }
      if (this.composing) {
        return
      }
      if (isCopyShortcut(e) && hasSelection(this)) {
        e.preventDefault()
        void copySelectionToClipboard(this)
        return
      }
      if (isPasteShortcut(e)) {
        return
      }
      e.preventDefault()
      pushHookEvent(this, 'key', {
        key: e.key,
        shiftKey: e.shiftKey,
        ctrlKey: e.ctrlKey,
        altKey: e.altKey,
        metaKey: e.metaKey
      })
      this.input.value = ''
    }

    this.onPaste = (e: ClipboardEvent) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return
      }
      const text = e.clipboardData?.getData('text') ?? ''
      if (text === '') {
        return
      }
      e.preventDefault()
      clearSelection(this)
      pushHookEvent(this, 'text', { data: text })
      this.input.value = ''
    }

    this.onCopy = (e: ClipboardEvent) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return
      }
      if (!hasSelection(this)) {
        return
      }
      e.preventDefault()
      const sel = normalizeSelection(this.selectionAnchor, this.selectionFocus)
      const text = selectedText(sel, this.rowsData, this.cols)
      e.clipboardData?.setData('text/plain', text)
    }

    this.onCompositionStart = () => {
      this.composing = true
    }

    this.onCompositionEnd = (e: CompositionEvent) => {
      this.composing = false
      if (e.data) {
        clearSelection(this)
        pushHookEvent(this, 'text', { data: e.data })
      }
      this.input.value = ''
    }

    this.onInputFocus = () => {
      this.focused = true
      this.cursorBlinkVisible = true
      this.autofocusPending = false
      stopAutofocus(this)
      if (this.focusReporting) {
        pushHookEvent(this, 'focus', { focused: true })
      }
      syncCursorBlink(this)
      doRenderCursor(this)
    }

    this.onInputBlur = () => {
      this.focused = false
      this.cursorBlinkVisible = true
      if (!isInsideTerminal(this, document.activeElement)) {
        this.autofocusPending = false
        stopAutofocus(this)
      }
      if (this.focusReporting) {
        pushHookEvent(this, 'focus', { focused: false })
      }
      syncCursorBlink(this)
      doRenderCursor(this)
    }

    // Register listeners

    this.el.addEventListener('focus', this.onContainerFocus)
    this.el.addEventListener('blur', this.onContainerBlur)
    this.el.addEventListener('keydown', this.onKeydown)
    this.el.addEventListener('paste', this.onPaste as EventListener)
    this.el.addEventListener('copy', this.onCopy as EventListener)
    this.el.addEventListener('mousedown', this.onPointerDown)
    window.addEventListener('mousemove', this.onPointerMove)
    window.addEventListener('mouseup', this.onPointerUp)
    document.addEventListener('mousedown', this.onDocumentPointerDown, true)
    document.addEventListener('focusin', this.onDocumentFocusIn, true)
    this.el.addEventListener('contextmenu', this.onContextMenu)
    window.addEventListener('resize', this.onWindowResize)
    window.addEventListener('scroll', this.onWindowResize, true)
    this.input.addEventListener('keydown', this.onKeydown)
    this.input.addEventListener('paste', this.onPaste as EventListener)
    this.input.addEventListener('copy', this.onCopy as EventListener)
    this.input.addEventListener('compositionstart', this.onCompositionStart)
    this.input.addEventListener('compositionend', this.onCompositionEnd)
    this.input.addEventListener('focus', this.onInputFocus)
    this.input.addEventListener('blur', this.onInputBlur)

    if (this.fit && typeof ResizeObserver !== 'undefined') {
      this.resizeObserver = new ResizeObserver(() => scheduleFit(this))
      this.resizeObserver.observe(this.el)
    }

    this.handleEvent('ghostty:render', (payload: RenderPayload) => {
      if (payload.id !== this.el.id) return
      this.rowsData = payload.cells
      this.cursor = payload.cursor
      this.cols = payload.cells[0]?.length ?? this.cols
      this.rows = payload.cells.length || this.rows
      this.mouse = payload.mouse || { ...DEFAULT_MOUSE }
      this.scrollbar = payload.scrollbar ?? null
      this.focusReporting = payload.focus_reporting ?? false
      if (mouseModeActive(this)) {
        clearSelection(this)
      }
      renderCells(this.pre, payload.cells)
      doRenderSelection(this)
      syncCursorBlink(this)
      doRenderCursor(this)
      scheduleFit(this)
      sendReady(this)
    })

    if (this.target) {
      this.pushEventTo(this.target, 'refresh', {})
    }

    window.addEventListener('pageshow', this.onWindowResize)
    requestAnimationFrame(() => sendReady(this))
    setTimeout(() => sendReady(this), 50)
    scheduleAutofocus(this)
  },

  destroyed(this: Hook) {
    stopCursorBlink(this)
    stopAutofocus(this)
    if (this.pendingFitTimer !== null) {
      clearTimeout(this.pendingFitTimer)
      this.pendingFitTimer = null
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    }
    window.removeEventListener('mousemove', this.onPointerMove)
    window.removeEventListener('mouseup', this.onPointerUp)
    document.removeEventListener('mousedown', this.onDocumentPointerDown, true)
    document.removeEventListener('focusin', this.onDocumentFocusIn, true)
    window.removeEventListener('resize', this.onWindowResize)
    window.removeEventListener('scroll', this.onWindowResize, true)
    window.removeEventListener('pageshow', this.onWindowResize)
  }
}

export { GhosttyTerminal }
