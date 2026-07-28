import { CellFlags } from './types'
import { esc, rgb } from './util'

import type { Cell, CellMetrics, Color, Selection } from './types'

export function renderCells(pre: HTMLPreElement, rows: Cell[][]): void {
  // Coalesce runs of consecutive cells with identical style into one span.
  // Upstream (simple) version emits one span per styled cell — 3200 spans for
  // an 80x40 grid in practice — which is the bulk of the rendering cost.
  // RLE typically 10x's the DOM size reduction and improves perf.
  let html = ''
  for (const row of rows) {
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
    html += '\n'
  }
  pre.innerHTML = html
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
