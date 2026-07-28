import { CellFlags } from './types'
import { esc, rgb } from './util'

import type { Cell, CellMetrics, Color, RenderRow, Selection } from './types'

export function renderCells(pre: HTMLPreElement, rows: Cell[][]): void {
  pre.innerHTML = rows
    .map((row, index) => `<span data-ghostty-row="${index}">${renderRow(row)}</span>\n`)
    .join('')
}

export function applyRowUpdates(rows: Cell[][], updates: RenderRow[]): RenderRow[] {
  const accepted: RenderRow[] = []

  for (const update of updates) {
    const { index, cells } = update
    const current = rows[index]

    if (
      Number.isInteger(index) &&
      index >= 0 &&
      Array.isArray(cells) &&
      current !== undefined &&
      cells.length === current.length
    ) {
      rows[index] = cells
      accepted.push(update)
    }
  }

  return accepted
}

export function renderRows(pre: HTMLPreElement, rows: RenderRow[]): boolean {
  const replacements: Array<{ element: Element; html: string }> = []

  for (const { index, cells } of rows) {
    const element = pre.children.item(index)
    if (!element || element.getAttribute('data-ghostty-row') !== String(index)) {
      return false
    }
    replacements.push({ element, html: renderRow(cells) })
  }

  for (const { element, html } of replacements) {
    element.innerHTML = html
  }

  return true
}

function renderRow(row: Cell[]): string {
  // Coalesce runs of consecutive cells with identical style into one span.
  let html = ''
  let runStyle: string | null = null
  let runChars = ''

  for (const [char, fg, bg, flags] of row) {
    const styles = cellStyles(fg, bg, flags)
    const styleStr = styles.length > 0 ? styles.join(';') : ''
    const ch = char || ' '
    if (styleStr === runStyle) {
      runChars += esc(ch)
    } else {
      if (runChars) {
        html += runStyle ? `<span style="${runStyle}">${runChars}</span>` : runChars
      }
      runStyle = styleStr
      runChars = esc(ch)
    }
  }

  if (runChars) {
    html += runStyle ? `<span style="${runStyle}">${runChars}</span>` : runChars
  }

  return html
}

export function renderSelection(
  layer: HTMLDivElement,
  selection: Selection | null,
  cols: number,
  metrics: CellMetrics
): void {
  layer.innerHTML = ''

  if (!selection) {
    return
  }

  for (let row = selection.start.row; row <= selection.end.row; row += 1) {
    const startCol = row === selection.start.row ? selection.start.col : 0
    const endCol = row === selection.end.row ? selection.end.col : cols - 1
    const rect = document.createElement('div')
    rect.style.position = 'absolute'
    rect.style.left = `${metrics.paddingLeft + startCol * metrics.width}px`
    rect.style.top = `${metrics.paddingTop + row * metrics.height}px`
    rect.style.width = `${Math.max(1, endCol - startCol + 1) * metrics.width}px`
    rect.style.height = `${metrics.height}px`
    rect.style.background = 'rgba(137, 180, 250, 0.35)'
    rect.style.borderRadius = '2px'
    layer.appendChild(rect)
  }
}

function cellStyles(fg: Color | null, bg: Color | null, flags: number): string[] {
  const styles: string[] = []
  const decorations: string[] = []

  if (fg) styles.push(`color:${rgb(fg)}`)
  if (bg) styles.push(`background:${rgb(bg)}`)
  if (flags & CellFlags.BOLD) styles.push('font-weight:bold')
  if (flags & CellFlags.ITALIC) styles.push('font-style:italic')
  if (flags & CellFlags.DIM) styles.push('opacity:0.5')
  if (flags & CellFlags.UNDERLINE) decorations.push('underline')
  if (flags & CellFlags.STRIKETHROUGH) decorations.push('line-through')
  if (flags & CellFlags.OVERLINE) decorations.push('overline')
  if (decorations.length > 0) styles.push(`text-decoration:${decorations.join(' ')}`)

  return styles
}

export function applyCellTextStyles(el: HTMLElement, cell: Cell | null): void {
  if (!cell) return

  const [, , , flags] = cell
  const decorations: string[] = []

  el.style.fontWeight = flags & CellFlags.BOLD ? 'bold' : ''
  el.style.fontStyle = flags & CellFlags.ITALIC ? 'italic' : ''
  el.style.opacity = flags & CellFlags.DIM ? '0.5' : '1'
  if (flags & CellFlags.UNDERLINE) decorations.push('underline')
  if (flags & CellFlags.STRIKETHROUGH) decorations.push('line-through')
  if (flags & CellFlags.OVERLINE) decorations.push('overline')
  el.style.textDecoration = decorations.length > 0 ? decorations.join(' ') : 'none'
}
