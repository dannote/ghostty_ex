export function createScreen(): HTMLDivElement {
  const screen = document.createElement('div')
  screen.style.position = 'relative'
  screen.style.display = 'block'
  screen.style.width = '100%'
  return screen
}

export function createPre(): HTMLPreElement {
  const pre = document.createElement('pre')
  pre.style.margin = '0'
  pre.style.padding = '8px'
  pre.style.backgroundColor = '#1e1e2e'
  pre.style.color = '#cdd6f4'
  pre.style.overflow = 'hidden'
  pre.style.position = 'relative'
  pre.style.width = '100%'
  pre.style.boxSizing = 'border-box'
  pre.style.userSelect = 'none'
  pre.style.webkitUserSelect = 'none'
  pre.style.cursor = 'text'
  return pre
}

export function createSelectionLayer(): HTMLDivElement {
  const layer = document.createElement('div')
  layer.setAttribute('aria-hidden', 'true')
  layer.setAttribute('data-ghostty-selection-layer', 'true')
  layer.style.position = 'absolute'
  layer.style.inset = '0'
  layer.style.pointerEvents = 'none'
  layer.style.zIndex = '0'
  return layer
}

export function createMeasure(): HTMLSpanElement {
  const span = document.createElement('span')
  span.textContent = 'MMMMMMMMMM'
  span.setAttribute('aria-hidden', 'true')
  span.style.position = 'absolute'
  span.style.visibility = 'hidden'
  span.style.pointerEvents = 'none'
  span.style.whiteSpace = 'pre'
  span.style.font = 'inherit'
  span.style.lineHeight = 'inherit'
  return span
}

export function createCursorEl(): { cursorEl: HTMLDivElement; cursorText: HTMLSpanElement } {
  const cursorEl = document.createElement('div')
  cursorEl.setAttribute('aria-hidden', 'true')
  cursorEl.style.position = 'absolute'
  cursorEl.style.display = 'none'
  cursorEl.style.pointerEvents = 'none'
  cursorEl.style.boxSizing = 'border-box'
  cursorEl.style.whiteSpace = 'pre'
  cursorEl.style.zIndex = '1'

  const cursorText = document.createElement('span')
  cursorText.style.display = 'block'
  cursorText.style.width = '100%'
  cursorText.style.height = '100%'
  cursorText.style.font = 'inherit'
  cursorText.style.lineHeight = 'inherit'
  cursorEl.appendChild(cursorText)

  return { cursorEl, cursorText }
}

export function setupInput(input: HTMLTextAreaElement): void {
  input.setAttribute('data-ghostty-input', 'true')
  input.setAttribute('aria-label', 'Terminal input')
  input.setAttribute('autocapitalize', 'off')
  input.setAttribute('autocomplete', 'off')
  input.setAttribute('autocorrect', 'off')
  input.setAttribute('spellcheck', 'false')
  input.style.position = 'absolute'
  input.style.left = '0'
  input.style.top = '0'
  input.style.width = '1px'
  input.style.height = '1em'
  input.style.padding = '0'
  input.style.margin = '0'
  input.style.border = '0'
  input.style.outline = 'none'
  input.style.opacity = '0'
  input.style.resize = 'none'
  input.style.overflow = 'hidden'
  input.style.background = 'transparent'
  input.style.color = 'transparent'
  input.style.caretColor = 'transparent'
  input.style.whiteSpace = 'pre'
  input.style.pointerEvents = 'none'
  input.style.zIndex = '2'
}

export function measureCellMetrics(
  pre: HTMLPreElement,
  measure: HTMLSpanElement,
  input: HTMLTextAreaElement,
  cursorEl: HTMLDivElement
): {
  width: number
  height: number
  paddingLeft: number
  paddingRight: number
  paddingTop: number
  paddingBottom: number
} {
  const styles = window.getComputedStyle(pre)

  measure.style.fontFamily = styles.fontFamily
  measure.style.fontSize = styles.fontSize
  measure.style.fontWeight = styles.fontWeight
  measure.style.fontStyle = styles.fontStyle
  measure.style.lineHeight = styles.lineHeight

  input.style.fontFamily = styles.fontFamily
  input.style.fontSize = styles.fontSize
  input.style.lineHeight = styles.lineHeight
  cursorEl.style.fontFamily = styles.fontFamily
  cursorEl.style.fontSize = styles.fontSize
  cursorEl.style.lineHeight = styles.lineHeight

  const measureRect = measure.getBoundingClientRect()
  const fontSize = parseFloat(styles.fontSize) || 16
  const lineHeight = parseFloat(styles.lineHeight) || fontSize * 1.2
  const width = measureRect.width > 0 ? measureRect.width / 10 : fontSize * 0.6

  return {
    width,
    height: lineHeight,
    paddingLeft: parseFloat(styles.paddingLeft) || 0,
    paddingRight: parseFloat(styles.paddingRight) || 0,
    paddingTop: parseFloat(styles.paddingTop) || 0,
    paddingBottom: parseFloat(styles.paddingBottom) || 0
  }
}
