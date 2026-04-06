export function isCopyShortcut(e: KeyboardEvent): boolean {
  return (e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === 'c'
}

export function isPasteShortcut(e: KeyboardEvent): boolean {
  return (e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === 'v'
}

export function mouseButtonName(button: number): string | null {
  switch (button) {
    case 0:
      return 'left'
    case 1:
      return 'middle'
    case 2:
      return 'right'
    case 3:
      return 'four'
    case 4:
      return 'five'
    default:
      return null
  }
}

export function primaryPressedButton(e: MouseEvent): number {
  if (e.buttons & 1) return 0
  if (e.buttons & 4) return 1
  if (e.buttons & 2) return 2
  if (e.buttons & 8) return 3
  if (e.buttons & 16) return 4
  return -1
}

export function hasMouseModifiers(e: MouseEvent): boolean {
  return e.shiftKey || e.ctrlKey || e.altKey || e.metaKey
}
