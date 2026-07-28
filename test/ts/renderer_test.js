import { describe, expect, test } from 'bun:test'

import { isBrowserDevShortcut } from '../../priv/ts/input.ts'
import { applyRowUpdates, renderCells, renderRows } from '../../priv/ts/render.ts'

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

    expect(pre.innerHTML).toBe(
      '<span data-ghostty-row="0"><span style="color:rgb(255,0,0)">&lt;&amp;</span>&gt;</span>\n'
    )
  })

  test('does not combine style runs across rows', () => {
    const pre = { innerHTML: '' }
    const red = [255, 0, 0]

    renderCells(pre, [[['a', red, null, 0]], [['b', red, null, 0]]])

    expect(pre.innerHTML).toBe(
      '<span data-ghostty-row="0"><span style="color:rgb(255,0,0)">a</span></span>\n' +
        '<span data-ghostty-row="1"><span style="color:rgb(255,0,0)">b</span></span>\n'
    )
  })
})

describe('row updates', () => {
  test('merges only valid same-shape rows', () => {
    const blank = ['', null, null, 0]
    const rows = [
      [blank, blank],
      [blank, blank]
    ]
    const replacement = [
      ['a', null, null, 0],
      ['b', null, null, 0]
    ]

    const accepted = applyRowUpdates(rows, [
      { index: 1, cells: replacement },
      { index: 0.5, cells: replacement },
      { index: 2, cells: replacement },
      { index: 0, cells: [blank] }
    ])

    expect(accepted).toEqual([{ index: 1, cells: replacement }])
    expect(rows[1]).toBe(replacement)
  })

  test('replaces only the requested row DOM', () => {
    const elements = [0, 1].map((index) => ({
      innerHTML: `old-${index}`,
      getAttribute: (name) => (name === 'data-ghostty-row' ? String(index) : null)
    }))
    const pre = { children: { item: (index) => elements[index] ?? null } }

    expect(renderRows(pre, [{ index: 1, cells: [['x', null, null, 0]] }])).toBe(true)
    expect(elements[0].innerHTML).toBe('old-0')
    expect(elements[1].innerHTML).toBe('x')
  })

  test('requests a full fallback when row wrappers are missing', () => {
    const pre = { children: { item: () => null } }

    expect(renderRows(pre, [{ index: 0, cells: [['x', null, null, 0]] }])).toBe(false)
  })
})
