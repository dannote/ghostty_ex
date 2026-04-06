import { applyCellTextStyles } from './render'
import { rgb } from './util'

import type { Cell, CellMetrics, CursorState } from './types'

export function cursorVisible(cursor: CursorState | null, blinkVisible: boolean): boolean {
  return Boolean(cursor && cursor.visible && cursor.x !== null && cursor.y !== null && blinkVisible)
}

export function cursorDisplayStyle(style: string, focused: boolean): string {
  if (!focused && style === 'block') {
    return 'block_hollow'
  }
  return style
}

export function cursorCell(cursor: CursorState, rowsData: Cell[][]): Cell | null {
  if (cursor.y === null || cursor.x === null) return null

  const row = rowsData[cursor.y]
  if (!row) return null

  if (cursor.wide_tail && cursor.x > 0) {
    return row[cursor.x - 1] ?? null
  }

  return row[cursor.x] ?? null
}

export function cursorChar(cell: Cell | null): string {
  return cell?.[0] || ' '
}

export function cursorColor(cursor: CursorState, pre: HTMLPreElement): string {
  if (cursor.color) {
    return rgb(cursor.color)
  }
  return window.getComputedStyle(pre).color || '#cdd6f4'
}

export function cursorTextColor(cell: Cell | null, pre: HTMLPreElement): string {
  if (cell?.[2]) {
    return rgb(cell[2])
  }
  return window.getComputedStyle(pre).backgroundColor || '#1e1e2e'
}

export function renderCursor(
  cursorEl: HTMLDivElement,
  cursorTextEl: HTMLSpanElement,
  cursor: CursorState | null,
  rowsData: Cell[][],
  focused: boolean,
  blinkVisible: boolean,
  metrics: CellMetrics,
  pre: HTMLPreElement,
  input: HTMLTextAreaElement
): void {
  if (!cursorVisible(cursor, blinkVisible)) {
    cursorEl.style.display = 'none'
    syncInputPosition(input, null)
    return
  }

  const c = cursor as CursorState
  const cx = c.x as number
  const cy = c.y as number
  let leftCol = cx
  let widthCols = 1

  if (c.wide_tail && cx > 0) {
    leftCol -= 1
    widthCols = 2
  }

  const left = metrics.paddingLeft + leftCol * metrics.width
  const top = metrics.paddingTop + cy * metrics.height
  const width = metrics.width * widthCols
  const height = metrics.height
  const style = cursorDisplayStyle(c.style, focused)
  const color = cursorColor(c, pre)

  syncInputPosition(input, { left, top, height })

  cursorEl.style.display = 'block'
  cursorEl.style.left = `${left}px`
  cursorEl.style.top = `${top}px`
  cursorEl.style.width = `${width}px`
  cursorEl.style.height = `${height}px`
  cursorEl.style.opacity = focused ? '1' : '0.85'

  cursorTextEl.textContent = ''
  cursorTextEl.style.color = ''
  cursorTextEl.style.backgroundColor = 'transparent'
  cursorTextEl.style.fontWeight = ''
  cursorTextEl.style.fontStyle = ''
  cursorTextEl.style.opacity = '1'
  cursorTextEl.style.textDecoration = 'none'

  cursorEl.style.backgroundColor = 'transparent'
  cursorEl.style.border = 'none'
  cursorEl.style.borderBottom = 'none'
  cursorEl.style.borderLeft = 'none'

  if (style === 'block') {
    const cell = cursorCell(c, rowsData)
    cursorEl.style.backgroundColor = color
    cursorTextEl.textContent = cursorChar(cell)
    cursorTextEl.style.color = cursorTextColor(cell, pre)
    applyCellTextStyles(cursorTextEl, cell)
    return
  }

  if (style === 'underline') {
    cursorEl.style.borderBottom = `2px solid ${color}`
    return
  }

  if (style === 'bar') {
    const barWidth = Math.max(2, Math.round(metrics.width * 0.15))
    cursorEl.style.width = `${barWidth}px`
    cursorEl.style.backgroundColor = color
    return
  }

  cursorEl.style.border = `1px solid ${color}`
}

function syncInputPosition(
  input: HTMLTextAreaElement,
  position: { left: number; top: number; height: number } | null
): void {
  if (!position) {
    input.style.left = '0'
    input.style.top = '0'
    return
  }

  input.style.left = `${position.left}px`
  input.style.top = `${position.top}px`
  input.style.height = `${position.height}px`
}
