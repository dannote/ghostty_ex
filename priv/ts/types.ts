export type Color = [number, number, number]

export type Cell = [string, Color | null, Color | null, number]

export interface CellPoint {
  col: number
  row: number
  encodeX: number
  encodeY: number
}

export interface MouseModes {
  tracking: boolean
  x10: boolean
  normal: boolean
  button: boolean
  any: boolean
  sgr: boolean
}

export interface CursorState {
  x: number | null
  y: number | null
  visible: boolean
  blinking: boolean
  style: 'block' | 'bar' | 'underline' | 'block_hollow'
  wide_tail: boolean
  color: Color | null
}

export interface ScrollbarState {
  total: number
  offset: number
  len: number
}

export interface RenderPayload {
  id: string
  cells: Cell[][]
  cursor: CursorState
  mouse: MouseModes
  scrollbar: ScrollbarState
  focus_reporting: boolean
}

export interface CellMetrics {
  width: number
  height: number
  paddingLeft: number
  paddingRight: number
  paddingTop: number
  paddingBottom: number
}

export interface Selection {
  start: CellPoint
  end: CellPoint
}

export const DEFAULT_MOUSE: MouseModes = {
  tracking: false,
  x10: false,
  normal: false,
  button: false,
  any: false,
  sgr: false
}

export const CellFlags = {
  BOLD: 1,
  ITALIC: 2,
  DIM: 4,
  UNDERLINE: 8,
  STRIKETHROUGH: 16,
  OVERLINE: 128
} as const
