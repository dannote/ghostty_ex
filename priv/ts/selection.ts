import type { Cell, CellPoint, Selection } from './types'

export function normalizeSelection(
  anchor: CellPoint | null,
  focus: CellPoint | null
): Selection | null {
  if (!anchor || !focus) {
    return null
  }

  const start = { ...anchor }
  const end = { ...focus }

  if (end.row < start.row || (end.row === start.row && end.col < start.col)) {
    return { start: end, end: start }
  }

  if (start.row === end.row && start.col === end.col) {
    return null
  }

  return { start, end }
}

export function selectedText(
  selection: Selection | null,
  rowsData: Cell[][],
  cols: number
): string {
  if (!selection) {
    return ''
  }

  const lines: string[] = []

  for (let row = selection.start.row; row <= selection.end.row; row += 1) {
    const sourceRow = rowsData[row] || []
    const startCol = row === selection.start.row ? selection.start.col : 0
    const endCol = row === selection.end.row ? selection.end.col : cols - 1
    let text = ''

    for (let col = startCol; col <= endCol; col += 1) {
      const cell = sourceRow[col]
      text += cell?.[0] || ' '
    }

    lines.push(text.trimEnd())
  }

  return lines.join('\n')
}
