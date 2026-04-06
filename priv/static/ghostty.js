// priv/ts/types.ts
var DEFAULT_MOUSE = {
  tracking: false,
  x10: false,
  normal: false,
  button: false,
  any: false,
  sgr: false
};
var CellFlags = {
  BOLD: 1,
  ITALIC: 2,
  DIM: 4,
  UNDERLINE: 8,
  STRIKETHROUGH: 16,
  OVERLINE: 128
};

// priv/ts/util.ts
function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function rgb(color) {
  return `rgb(${color[0]},${color[1]},${color[2]})`;
}
function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

// priv/ts/render.ts
function renderCells(pre, rows) {
  let html = "";
  for (const row of rows) {
    for (const [char, fg, bg, flags] of row) {
      const styles = cellStyles(fg, bg, flags);
      const ch = char || " ";
      if (styles.length > 0) {
        html += `<span style="${styles.join(";")}">${esc(ch)}</span>`;
      } else {
        html += esc(ch);
      }
    }
    html += `
`;
  }
  pre.innerHTML = html;
}
function renderSelection(layer, selection, cols, metrics) {
  layer.innerHTML = "";
  if (!selection) {
    return;
  }
  for (let row = selection.start.row;row <= selection.end.row; row += 1) {
    const startCol = row === selection.start.row ? selection.start.col : 0;
    const endCol = row === selection.end.row ? selection.end.col : cols - 1;
    const rect = document.createElement("div");
    rect.style.position = "absolute";
    rect.style.left = `${metrics.paddingLeft + startCol * metrics.width}px`;
    rect.style.top = `${metrics.paddingTop + row * metrics.height}px`;
    rect.style.width = `${Math.max(1, endCol - startCol + 1) * metrics.width}px`;
    rect.style.height = `${metrics.height}px`;
    rect.style.background = "rgba(137, 180, 250, 0.35)";
    rect.style.borderRadius = "2px";
    layer.appendChild(rect);
  }
}
function cellStyles(fg, bg, flags) {
  const styles = [];
  const decorations = [];
  if (fg)
    styles.push(`color:${rgb(fg)}`);
  if (bg)
    styles.push(`background:${rgb(bg)}`);
  if (flags & CellFlags.BOLD)
    styles.push("font-weight:bold");
  if (flags & CellFlags.ITALIC)
    styles.push("font-style:italic");
  if (flags & CellFlags.DIM)
    styles.push("opacity:0.5");
  if (flags & CellFlags.UNDERLINE)
    decorations.push("underline");
  if (flags & CellFlags.STRIKETHROUGH)
    decorations.push("line-through");
  if (flags & CellFlags.OVERLINE)
    decorations.push("overline");
  if (decorations.length > 0)
    styles.push(`text-decoration:${decorations.join(" ")}`);
  return styles;
}
function applyCellTextStyles(el, cell) {
  if (!cell)
    return;
  const [, , , flags] = cell;
  const decorations = [];
  el.style.fontWeight = flags & CellFlags.BOLD ? "bold" : "";
  el.style.fontStyle = flags & CellFlags.ITALIC ? "italic" : "";
  el.style.opacity = flags & CellFlags.DIM ? "0.5" : "1";
  if (flags & CellFlags.UNDERLINE)
    decorations.push("underline");
  if (flags & CellFlags.STRIKETHROUGH)
    decorations.push("line-through");
  if (flags & CellFlags.OVERLINE)
    decorations.push("overline");
  el.style.textDecoration = decorations.length > 0 ? decorations.join(" ") : "none";
}

// priv/ts/cursor.ts
function cursorVisible(cursor, blinkVisible) {
  return Boolean(cursor && cursor.visible && cursor.x !== null && cursor.y !== null && blinkVisible);
}
function cursorDisplayStyle(style, focused) {
  if (!focused && style === "block") {
    return "block_hollow";
  }
  return style;
}
function cursorCell(cursor, rowsData) {
  if (cursor.y === null || cursor.x === null)
    return null;
  const row = rowsData[cursor.y];
  if (!row)
    return null;
  if (cursor.wide_tail && cursor.x > 0) {
    return row[cursor.x - 1] ?? null;
  }
  return row[cursor.x] ?? null;
}
function cursorChar(cell) {
  return cell?.[0] || " ";
}
function cursorColor(cursor, pre) {
  if (cursor.color) {
    return rgb(cursor.color);
  }
  return window.getComputedStyle(pre).color || "#cdd6f4";
}
function cursorTextColor(cell, pre) {
  if (cell?.[2]) {
    return rgb(cell[2]);
  }
  return window.getComputedStyle(pre).backgroundColor || "#1e1e2e";
}
function renderCursor(cursorEl, cursorTextEl, cursor, rowsData, focused, blinkVisible, metrics, pre, input) {
  if (!cursorVisible(cursor, blinkVisible)) {
    cursorEl.style.display = "none";
    syncInputPosition(input, null);
    return;
  }
  const c = cursor;
  const cx = c.x;
  const cy = c.y;
  let leftCol = cx;
  let widthCols = 1;
  if (c.wide_tail && cx > 0) {
    leftCol -= 1;
    widthCols = 2;
  }
  const left = metrics.paddingLeft + leftCol * metrics.width;
  const top = metrics.paddingTop + cy * metrics.height;
  const width = metrics.width * widthCols;
  const height = metrics.height;
  const style = cursorDisplayStyle(c.style, focused);
  const color = cursorColor(c, pre);
  syncInputPosition(input, { left, top, height });
  cursorEl.style.display = "block";
  cursorEl.style.left = `${left}px`;
  cursorEl.style.top = `${top}px`;
  cursorEl.style.width = `${width}px`;
  cursorEl.style.height = `${height}px`;
  cursorEl.style.opacity = focused ? "1" : "0.85";
  cursorTextEl.textContent = "";
  cursorTextEl.style.color = "";
  cursorTextEl.style.backgroundColor = "transparent";
  cursorTextEl.style.fontWeight = "";
  cursorTextEl.style.fontStyle = "";
  cursorTextEl.style.opacity = "1";
  cursorTextEl.style.textDecoration = "none";
  cursorEl.style.backgroundColor = "transparent";
  cursorEl.style.border = "none";
  cursorEl.style.borderBottom = "none";
  cursorEl.style.borderLeft = "none";
  if (style === "block") {
    const cell = cursorCell(c, rowsData);
    cursorEl.style.backgroundColor = color;
    cursorTextEl.textContent = cursorChar(cell);
    cursorTextEl.style.color = cursorTextColor(cell, pre);
    applyCellTextStyles(cursorTextEl, cell);
    return;
  }
  if (style === "underline") {
    cursorEl.style.borderBottom = `2px solid ${color}`;
    return;
  }
  if (style === "bar") {
    const barWidth = Math.max(2, Math.round(metrics.width * 0.15));
    cursorEl.style.width = `${barWidth}px`;
    cursorEl.style.backgroundColor = color;
    return;
  }
  cursorEl.style.border = `1px solid ${color}`;
}
function syncInputPosition(input, position) {
  if (!position) {
    input.style.left = "0";
    input.style.top = "0";
    return;
  }
  input.style.left = `${position.left}px`;
  input.style.top = `${position.top}px`;
  input.style.height = `${position.height}px`;
}

// priv/ts/dom.ts
function createScreen() {
  const screen = document.createElement("div");
  screen.style.position = "relative";
  screen.style.display = "block";
  screen.style.width = "100%";
  return screen;
}
function createPre() {
  const pre = document.createElement("pre");
  pre.style.margin = "0";
  pre.style.padding = "8px";
  pre.style.backgroundColor = "#1e1e2e";
  pre.style.color = "#cdd6f4";
  pre.style.overflow = "hidden";
  pre.style.position = "relative";
  pre.style.width = "100%";
  pre.style.boxSizing = "border-box";
  pre.style.userSelect = "none";
  pre.style.webkitUserSelect = "none";
  pre.style.cursor = "text";
  return pre;
}
function createSelectionLayer() {
  const layer = document.createElement("div");
  layer.setAttribute("aria-hidden", "true");
  layer.setAttribute("data-ghostty-selection-layer", "true");
  layer.style.position = "absolute";
  layer.style.inset = "0";
  layer.style.pointerEvents = "none";
  layer.style.zIndex = "0";
  return layer;
}
function createMeasure() {
  const span = document.createElement("span");
  span.textContent = "MMMMMMMMMM";
  span.setAttribute("aria-hidden", "true");
  span.style.position = "absolute";
  span.style.visibility = "hidden";
  span.style.pointerEvents = "none";
  span.style.whiteSpace = "pre";
  span.style.font = "inherit";
  span.style.lineHeight = "inherit";
  return span;
}
function createCursorEl() {
  const cursorEl = document.createElement("div");
  cursorEl.setAttribute("aria-hidden", "true");
  cursorEl.style.position = "absolute";
  cursorEl.style.display = "none";
  cursorEl.style.pointerEvents = "none";
  cursorEl.style.boxSizing = "border-box";
  cursorEl.style.whiteSpace = "pre";
  cursorEl.style.zIndex = "1";
  const cursorText = document.createElement("span");
  cursorText.style.display = "block";
  cursorText.style.width = "100%";
  cursorText.style.height = "100%";
  cursorText.style.font = "inherit";
  cursorText.style.lineHeight = "inherit";
  cursorEl.appendChild(cursorText);
  return { cursorEl, cursorText };
}
function setupInput(input) {
  input.setAttribute("data-ghostty-input", "true");
  input.setAttribute("aria-label", "Terminal input");
  input.setAttribute("autocapitalize", "off");
  input.setAttribute("autocomplete", "off");
  input.setAttribute("autocorrect", "off");
  input.setAttribute("spellcheck", "false");
  input.style.position = "absolute";
  input.style.left = "0";
  input.style.top = "0";
  input.style.width = "1px";
  input.style.height = "1em";
  input.style.padding = "0";
  input.style.margin = "0";
  input.style.border = "0";
  input.style.outline = "none";
  input.style.opacity = "0";
  input.style.resize = "none";
  input.style.overflow = "hidden";
  input.style.background = "transparent";
  input.style.color = "transparent";
  input.style.caretColor = "transparent";
  input.style.whiteSpace = "pre";
  input.style.pointerEvents = "none";
  input.style.zIndex = "2";
}
function measureCellMetrics(pre, measure, input, cursorEl) {
  const styles = window.getComputedStyle(pre);
  measure.style.fontFamily = styles.fontFamily;
  measure.style.fontSize = styles.fontSize;
  measure.style.fontWeight = styles.fontWeight;
  measure.style.fontStyle = styles.fontStyle;
  measure.style.lineHeight = styles.lineHeight;
  input.style.fontFamily = styles.fontFamily;
  input.style.fontSize = styles.fontSize;
  input.style.lineHeight = styles.lineHeight;
  cursorEl.style.fontFamily = styles.fontFamily;
  cursorEl.style.fontSize = styles.fontSize;
  cursorEl.style.lineHeight = styles.lineHeight;
  const measureRect = measure.getBoundingClientRect();
  const fontSize = parseFloat(styles.fontSize) || 16;
  const lineHeight = parseFloat(styles.lineHeight) || fontSize * 1.2;
  const width = measureRect.width > 0 ? measureRect.width / 10 : fontSize * 0.6;
  return {
    width,
    height: lineHeight,
    paddingLeft: parseFloat(styles.paddingLeft) || 0,
    paddingRight: parseFloat(styles.paddingRight) || 0,
    paddingTop: parseFloat(styles.paddingTop) || 0,
    paddingBottom: parseFloat(styles.paddingBottom) || 0
  };
}

// priv/ts/input.ts
function isCopyShortcut(e) {
  return (e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === "c";
}
function isPasteShortcut(e) {
  return (e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === "v";
}
function mouseButtonName(button) {
  switch (button) {
    case 0:
      return "left";
    case 1:
      return "middle";
    case 2:
      return "right";
    case 3:
      return "four";
    case 4:
      return "five";
    default:
      return null;
  }
}
function primaryPressedButton(e) {
  if (e.buttons & 1)
    return 0;
  if (e.buttons & 4)
    return 1;
  if (e.buttons & 2)
    return 2;
  if (e.buttons & 8)
    return 3;
  if (e.buttons & 16)
    return 4;
  return -1;
}
function hasMouseModifiers(e) {
  return e.shiftKey || e.ctrlKey || e.altKey || e.metaKey;
}

// priv/ts/selection.ts
function normalizeSelection(anchor, focus) {
  if (!anchor || !focus) {
    return null;
  }
  const start = { ...anchor };
  const end = { ...focus };
  if (end.row < start.row || end.row === start.row && end.col < start.col) {
    return { start: end, end: start };
  }
  if (start.row === end.row && start.col === end.col) {
    return null;
  }
  return { start, end };
}
function selectedText(selection, rowsData, cols) {
  if (!selection) {
    return "";
  }
  const lines = [];
  for (let row = selection.start.row;row <= selection.end.row; row += 1) {
    const sourceRow = rowsData[row] || [];
    const startCol = row === selection.start.row ? selection.start.col : 0;
    const endCol = row === selection.end.row ? selection.end.col : cols - 1;
    let text = "";
    for (let col = startCol;col <= endCol; col += 1) {
      const cell = sourceRow[col];
      text += cell?.[0] || " ";
    }
    lines.push(text);
  }
  return lines.join(`
`);
}

// priv/ts/hook.ts
function pushHookEvent(hook, name, payload) {
  if (hook.target) {
    hook.pushEventTo(hook.target, name, payload);
  } else {
    hook.pushEvent(name, payload);
  }
}
function metrics(hook) {
  return measureCellMetrics(hook.pre, hook.measure, hook.input, hook.cursorEl);
}
function isInsideTerminal(hook, node) {
  return Boolean(node && (node === hook.el || node === hook.input || hook.el.contains(node)));
}
function mouseModeActive(hook) {
  return Boolean(hook.mouse?.tracking);
}
function hasSelection(hook) {
  return !mouseModeActive(hook) && normalizeSelection(hook.selectionAnchor, hook.selectionFocus) !== null;
}
function clearSelection(hook) {
  hook.selectionAnchor = null;
  hook.selectionFocus = null;
  hook.selecting = false;
  hook.selectionLayer.innerHTML = "";
}
function focusInput(hook, force = false) {
  if (!force && !shouldAutofocus(hook)) {
    return;
  }
  if (document.activeElement !== hook.el) {
    hook.el.focus({ preventScroll: true });
  }
  if (document.activeElement !== hook.input) {
    hook.input.focus({ preventScroll: true });
  }
}
function blurTerminal(hook) {
  hook.pointerActive = false;
  if (document.activeElement === hook.input) {
    hook.input.blur();
  }
  if (document.activeElement === hook.el) {
    hook.el.blur();
  }
  hook.focused = false;
  hook.cursorBlinkVisible = true;
  syncCursorBlink(hook);
  doRenderCursor(hook);
}
function disableAutofocus(hook) {
  hook.autofocusPending = false;
  stopAutofocus(hook);
}
function shouldAutofocus(hook) {
  const active = document.activeElement;
  if (!active || active === document.body || active === document.documentElement) {
    return true;
  }
  return isInsideTerminal(hook, active);
}
function scheduleAutofocus(hook) {
  if (!hook.autofocusPending) {
    return;
  }
  if (document.activeElement === hook.input) {
    disableAutofocus(hook);
    return;
  }
  stopAutofocus(hook);
  for (const delay of [0, 50, 150, 300, 600, 1000]) {
    const timer = setTimeout(() => {
      if (!hook.el.isConnected || document.activeElement === hook.input) {
        return;
      }
      if (!shouldAutofocus(hook)) {
        disableAutofocus(hook);
        return;
      }
      focusInput(hook);
    }, delay);
    hook.autofocusTimers.push(timer);
  }
}
function stopAutofocus(hook) {
  for (const timer of hook.autofocusTimers) {
    clearTimeout(timer);
  }
  hook.autofocusTimers = [];
}
function syncCursorBlink(hook) {
  stopCursorBlink(hook);
  if (hook.cursor?.visible && hook.cursor?.blinking && hook.focused) {
    hook.cursorBlinkTimer = setInterval(() => {
      hook.cursorBlinkVisible = !hook.cursorBlinkVisible;
      doRenderCursor(hook);
    }, 600);
    return;
  }
  hook.cursorBlinkVisible = true;
}
function stopCursorBlink(hook) {
  if (hook.cursorBlinkTimer !== null) {
    clearInterval(hook.cursorBlinkTimer);
    hook.cursorBlinkTimer = null;
  }
}
function doRenderCursor(hook) {
  renderCursor(hook.cursorEl, hook.cursorText, hook.cursor, hook.rowsData, hook.focused, hook.cursorBlinkVisible, metrics(hook), hook.pre, hook.input);
}
function doRenderSelection(hook) {
  const sel = mouseModeActive(hook) ? null : normalizeSelection(hook.selectionAnchor, hook.selectionFocus);
  renderSelection(hook.selectionLayer, sel, hook.cols, metrics(hook));
}
function cellPointFromEvent(hook, e) {
  const m = metrics(hook);
  const rect = hook.pre.getBoundingClientRect();
  const x = e.clientX - rect.left - m.paddingLeft;
  const y = e.clientY - rect.top - m.paddingTop;
  if (x < 0 || y < 0) {
    return null;
  }
  const col = clamp(Math.floor(x / m.width), 0, hook.cols - 1);
  const row = clamp(Math.floor(y / m.height), 0, hook.rows - 1);
  return { col, row, encodeX: col * 10 + 5, encodeY: row * 20 + 10 };
}
function pushMouseEvent(hook, action, e, point) {
  pushHookEvent(hook, "mouse", {
    action,
    button: mouseButtonName(action === "motion" ? primaryPressedButton(e) : e.button),
    x: point.encodeX,
    y: point.encodeY,
    shiftKey: e.shiftKey,
    ctrlKey: e.ctrlKey,
    altKey: e.altKey,
    metaKey: e.metaKey
  });
}
function pointerTargetsTerminal(hook, target) {
  return target === hook.el || target === hook.pre || hook.pre.contains(target);
}
function scheduleFit(hook) {
  if (!hook.fit) {
    return;
  }
  if (hook.pendingFitTimer !== null) {
    clearTimeout(hook.pendingFitTimer);
  }
  hook.pendingFitTimer = setTimeout(() => {
    hook.pendingFitTimer = null;
    fitToContainer(hook);
  }, 75);
}
function currentFitSize(hook) {
  const m = metrics(hook);
  const rect = hook.el.getBoundingClientRect();
  const preRect = hook.pre.getBoundingClientRect();
  const availableWidth = Math.max(0, rect.width - m.paddingLeft - m.paddingRight);
  const availableHeight = Math.max(0, preRect.height - m.paddingTop - m.paddingBottom);
  if (availableWidth < m.width * 20 || availableHeight < m.height * 5) {
    return null;
  }
  return {
    cols: Math.max(2, Math.floor(availableWidth / m.width)),
    rows: Math.max(2, Math.floor(availableHeight / m.height))
  };
}
function fitToContainer(hook) {
  const size = currentFitSize(hook);
  if (!size) {
    return;
  }
  if (size.cols === hook.lastFitCols && size.rows === hook.lastFitRows) {
    return;
  }
  hook.lastFitCols = size.cols;
  hook.lastFitRows = size.rows;
  pushHookEvent(hook, "resize", size);
}
function sendReady(hook) {
  if (hook.readySent) {
    return;
  }
  const size = hook.fit ? currentFitSize(hook) : { cols: hook.cols, rows: hook.rows };
  if (!size) {
    return;
  }
  hook.lastFitCols = size.cols;
  hook.lastFitRows = size.rows;
  pushHookEvent(hook, "ready", size);
  hook.readySent = true;
}
async function copySelectionToClipboard(hook) {
  const sel = normalizeSelection(hook.selectionAnchor, hook.selectionFocus);
  const text = selectedText(sel, hook.rowsData, hook.cols);
  if (text === "") {
    return;
  }
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {}
  }
  hook.input.value = text;
  hook.input.select();
  document.execCommand("copy");
  hook.input.value = "";
  focusInput(hook, true);
}
var GhosttyTerminal = {
  mounted() {
    this.cols = parseInt(this.el.dataset.cols ?? "80");
    this.rows = parseInt(this.el.dataset.rows ?? "24");
    this.fit = this.el.dataset.fit === "true";
    this.autofocus = this.el.dataset.autofocus === "true";
    this.rowsData = [];
    this.cursor = null;
    this.mouse = { ...DEFAULT_MOUSE };
    this.focused = false;
    this.composing = false;
    this.cursorBlinkVisible = true;
    this.cursorBlinkTimer = null;
    this.target = this.el.getAttribute("phx-target");
    this.resizeObserver = null;
    this.pendingFitTimer = null;
    this.lastFitCols = null;
    this.lastFitRows = null;
    this.selectionAnchor = null;
    this.selectionFocus = null;
    this.selecting = false;
    this.pointerActive = false;
    this.autofocusTimers = [];
    this.readySent = false;
    this.autofocusPending = this.autofocus;
    this.el.tabIndex = 0;
    this.el.style.position = "relative";
    this.el.style.outline = "none";
    this.input = this.el.querySelector("textarea[data-ghostty-input='true']") ?? document.createElement("textarea");
    for (const child of Array.from(this.el.children)) {
      if (child !== this.input) {
        child.remove();
      }
    }
    this.screen = createScreen();
    this.el.appendChild(this.screen);
    this.pre = createPre();
    this.screen.appendChild(this.pre);
    this.selectionLayer = createSelectionLayer();
    this.screen.appendChild(this.selectionLayer);
    this.measure = createMeasure();
    this.screen.appendChild(this.measure);
    setupInput(this.input);
    this.screen.appendChild(this.input);
    const { cursorEl, cursorText } = createCursorEl();
    this.cursorEl = cursorEl;
    this.cursorText = cursorText;
    this.screen.appendChild(this.cursorEl);
    this.onContainerFocus = () => {
      this.focused = true;
      this.cursorBlinkVisible = true;
      syncCursorBlink(this);
      doRenderCursor(this);
      focusInput(this, true);
    };
    this.onContainerBlur = () => {
      setTimeout(() => {
        if (document.activeElement !== this.el && document.activeElement !== this.input) {
          this.focused = false;
          this.cursorBlinkVisible = true;
          syncCursorBlink(this);
          doRenderCursor(this);
        }
      }, 0);
    };
    this.onPointerDown = (e) => {
      if (!pointerTargetsTerminal(this, e.target)) {
        return;
      }
      const point = cellPointFromEvent(this, e);
      if (!point) {
        return;
      }
      this.pointerActive = true;
      focusInput(this, true);
      if (!mouseModeActive(this) && e.button === 0 && !hasMouseModifiers(e)) {
        this.selecting = true;
        this.selectionAnchor = point;
        this.selectionFocus = point;
        doRenderSelection(this);
        e.preventDefault();
      }
      pushMouseEvent(this, "press", e, point);
    };
    this.onPointerMove = (e) => {
      if (!this.pointerActive) {
        return;
      }
      const point = cellPointFromEvent(this, e);
      if (!point) {
        return;
      }
      if (this.selecting && !mouseModeActive(this)) {
        this.selectionFocus = point;
        doRenderSelection(this);
        e.preventDefault();
      }
      if (e.buttons !== 0) {
        pushMouseEvent(this, "motion", e, point);
      }
    };
    this.onPointerUp = (e) => {
      if (!this.pointerActive) {
        return;
      }
      this.pointerActive = false;
      const point = cellPointFromEvent(this, e);
      if (this.selecting && point && !mouseModeActive(this)) {
        this.selectionFocus = point;
        this.selecting = false;
        const sel = normalizeSelection(this.selectionAnchor, this.selectionFocus);
        if (!sel) {
          clearSelection(this);
          focusInput(this, true);
        } else {
          doRenderSelection(this);
        }
      } else if (!hasSelection(this)) {
        focusInput(this, true);
      }
      if (point) {
        pushMouseEvent(this, "release", e, point);
      }
    };
    this.onDocumentPointerDown = (e) => {
      if (!isInsideTerminal(this, e.target)) {
        disableAutofocus(this);
        blurTerminal(this);
      }
    };
    this.onDocumentFocusIn = (e) => {
      if (!isInsideTerminal(this, e.target)) {
        disableAutofocus(this);
      }
    };
    this.onContextMenu = (e) => {
      if (this.selecting) {
        e.preventDefault();
      }
    };
    this.onWindowResize = () => {
      scheduleFit(this);
      doRenderSelection(this);
      doRenderCursor(this);
    };
    this.onKeydown = (e) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return;
      }
      if (this.composing) {
        return;
      }
      if (isCopyShortcut(e) && hasSelection(this)) {
        e.preventDefault();
        copySelectionToClipboard(this);
        return;
      }
      if (isPasteShortcut(e)) {
        return;
      }
      e.preventDefault();
      pushHookEvent(this, "key", {
        key: e.key,
        shiftKey: e.shiftKey,
        ctrlKey: e.ctrlKey,
        altKey: e.altKey,
        metaKey: e.metaKey
      });
      this.input.value = "";
    };
    this.onPaste = (e) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return;
      }
      const text = e.clipboardData?.getData("text") ?? "";
      if (text === "") {
        return;
      }
      e.preventDefault();
      clearSelection(this);
      pushHookEvent(this, "text", { data: text });
      this.input.value = "";
    };
    this.onCopy = (e) => {
      if (e.currentTarget === this.el && document.activeElement === this.input) {
        return;
      }
      if (!hasSelection(this)) {
        return;
      }
      e.preventDefault();
      const sel = normalizeSelection(this.selectionAnchor, this.selectionFocus);
      const text = selectedText(sel, this.rowsData, this.cols);
      e.clipboardData?.setData("text/plain", text);
    };
    this.onCompositionStart = () => {
      this.composing = true;
    };
    this.onCompositionEnd = (e) => {
      this.composing = false;
      if (e.data) {
        clearSelection(this);
        pushHookEvent(this, "text", { data: e.data });
      }
      this.input.value = "";
    };
    this.onInputFocus = () => {
      this.focused = true;
      this.cursorBlinkVisible = true;
      this.autofocusPending = false;
      stopAutofocus(this);
      pushHookEvent(this, "focus", { focused: true });
      syncCursorBlink(this);
      doRenderCursor(this);
    };
    this.onInputBlur = () => {
      this.focused = false;
      this.cursorBlinkVisible = true;
      if (!isInsideTerminal(this, document.activeElement)) {
        this.autofocusPending = false;
        stopAutofocus(this);
      }
      pushHookEvent(this, "focus", { focused: false });
      syncCursorBlink(this);
      doRenderCursor(this);
    };
    this.el.addEventListener("focus", this.onContainerFocus);
    this.el.addEventListener("blur", this.onContainerBlur);
    this.el.addEventListener("keydown", this.onKeydown);
    this.el.addEventListener("paste", this.onPaste);
    this.el.addEventListener("copy", this.onCopy);
    this.el.addEventListener("mousedown", this.onPointerDown);
    window.addEventListener("mousemove", this.onPointerMove);
    window.addEventListener("mouseup", this.onPointerUp);
    document.addEventListener("mousedown", this.onDocumentPointerDown, true);
    document.addEventListener("focusin", this.onDocumentFocusIn, true);
    this.el.addEventListener("contextmenu", this.onContextMenu);
    window.addEventListener("resize", this.onWindowResize);
    window.addEventListener("scroll", this.onWindowResize, true);
    this.input.addEventListener("keydown", this.onKeydown);
    this.input.addEventListener("paste", this.onPaste);
    this.input.addEventListener("copy", this.onCopy);
    this.input.addEventListener("compositionstart", this.onCompositionStart);
    this.input.addEventListener("compositionend", this.onCompositionEnd);
    this.input.addEventListener("focus", this.onInputFocus);
    this.input.addEventListener("blur", this.onInputBlur);
    if (this.fit && typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(() => scheduleFit(this));
      this.resizeObserver.observe(this.el);
    }
    this.handleEvent("ghostty:render", (payload) => {
      if (payload.id !== this.el.id)
        return;
      this.rowsData = payload.cells;
      this.cursor = payload.cursor;
      this.cols = payload.cells[0]?.length ?? this.cols;
      this.rows = payload.cells.length || this.rows;
      this.mouse = payload.mouse || { ...DEFAULT_MOUSE };
      if (mouseModeActive(this)) {
        clearSelection(this);
      }
      renderCells(this.pre, payload.cells);
      doRenderSelection(this);
      syncCursorBlink(this);
      doRenderCursor(this);
      scheduleFit(this);
      sendReady(this);
    });
    if (this.target) {
      this.pushEventTo(this.target, "refresh", {});
    }
    window.addEventListener("pageshow", this.onWindowResize);
    requestAnimationFrame(() => sendReady(this));
    setTimeout(() => sendReady(this), 50);
    scheduleAutofocus(this);
  },
  destroyed() {
    stopCursorBlink(this);
    stopAutofocus(this);
    if (this.pendingFitTimer !== null) {
      clearTimeout(this.pendingFitTimer);
      this.pendingFitTimer = null;
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }
    window.removeEventListener("mousemove", this.onPointerMove);
    window.removeEventListener("mouseup", this.onPointerUp);
    document.removeEventListener("mousedown", this.onDocumentPointerDown, true);
    document.removeEventListener("focusin", this.onDocumentFocusIn, true);
    window.removeEventListener("resize", this.onWindowResize);
    window.removeEventListener("scroll", this.onWindowResize, true);
    window.removeEventListener("pageshow", this.onWindowResize);
  }
};
export {
  GhosttyTerminal
};
