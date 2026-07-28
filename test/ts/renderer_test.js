import { describe, expect, test } from 'bun:test'

import { isBrowserDevShortcut } from '../../priv/ts/input.ts'
import { renderCells } from '../../priv/ts/render.ts'

function keyboardEvent(key, modifiers = {}) {
  return {
    key,
    ctrlKey: false,
    metaKey: false,
    shiftKey: false,
    altKey: false,
    ...modifiers
  }
}

describe('isBrowserDevShortcut', () => {
  test('passes through refresh and function-key shortcuts', () => {
    expect(isBrowserDevShortcut(keyboardEvent('F5'))).toBe(true)
    expect(isBrowserDevShortcut(keyboardEvent('F12'))).toBe(true)
    expect(isBrowserDevShortcut(keyboardEvent('r', { ctrlKey: true, shiftKey: true }))).toBe(true)
  })

  test('passes through developer tools shortcuts on macOS', () => {
    for (const key of ['i', 'j', 'c']) {
      expect(isBrowserDevShortcut(keyboardEvent(key, { metaKey: true, altKey: true }))).toBe(true)
    }
  })

  test('keeps terminal key combinations in the terminal', () => {
    expect(isBrowserDevShortcut(keyboardEvent('r', { ctrlKey: true }))).toBe(false)
    expect(isBrowserDevShortcut(keyboardEvent('i', { metaKey: true }))).toBe(false)
  })
})

describe('renderCells', () => {
  test('coalesces adjacent cells with the same style and escapes text', () => {
    const pre = { innerHTML: '' }
    const red = [255, 0, 0]

    renderCells(pre, [
      [
        ['<', red, null, 0],
        ['&', red, null, 0],
        ['>', null, null, 0]
      ]
    ])

    expect(pre.innerHTML).toBe('<span style="color:rgb(255,0,0)">&lt;&amp;</span>&gt;\n')
  })

  test('does not combine style runs across rows', () => {
    const pre = { innerHTML: '' }
    const red = [255, 0, 0]

    renderCells(pre, [[['a', red, null, 0]], [['b', red, null, 0]]])

    expect(pre.innerHTML).toBe(
      '<span style="color:rgb(255,0,0)">a</span>\n<span style="color:rgb(255,0,0)">b</span>\n'
    )
  })
})
