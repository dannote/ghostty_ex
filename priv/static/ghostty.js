export const GhosttyTerminal = {
  mounted() {
    this.cols = parseInt(this.el.dataset.cols)
    this.rows = parseInt(this.el.dataset.rows)

    this.el.innerHTML = ""
    this.pre = document.createElement("pre")
    this.pre.style.margin = "0"
    this.pre.style.padding = "8px"
    this.pre.style.backgroundColor = "#1e1e2e"
    this.pre.style.color = "#cdd6f4"
    this.pre.style.overflow = "hidden"
    this.el.appendChild(this.pre)

    this.el.tabIndex = 0
    this.el.addEventListener("keydown", (e) => {
      e.preventDefault()
      const payload = {
        key: e.key,
        shiftKey: e.shiftKey,
        ctrlKey: e.ctrlKey,
        altKey: e.altKey,
        metaKey: e.metaKey,
      }
      const target = this.el.getAttribute("phx-target")
      if (target) {
        this.pushEventTo(target, "key", payload)
      } else {
        this.pushEvent("key", payload)
      }
    })

    this.handleEvent("ghostty:render", ({ id, cells }) => {
      if (id !== this.el.id) return
      this.renderCells(cells)
    })

    this.el.addEventListener("click", () => this.el.focus())
  },

  renderCells(rows) {
    let html = ""
    for (const row of rows) {
      for (const [char, fg, bg, flags] of row) {
        const styles = []
        if (fg) styles.push(`color:rgb(${fg[0]},${fg[1]},${fg[2]})`)
        if (bg) styles.push(`background:rgb(${bg[0]},${bg[1]},${bg[2]})`)
        if (flags & 1) styles.push("font-weight:bold")
        if (flags & 2) styles.push("font-style:italic")
        if (flags & 4) styles.push("opacity:0.5")
        if (flags & 8) styles.push("text-decoration:underline")
        if (flags & 16) styles.push("text-decoration:line-through")

        const ch = char || " "
        if (styles.length > 0) {
          html += `<span style="${styles.join(";")}">${esc(ch)}</span>`
        } else {
          html += esc(ch)
        }
      }
      html += "\n"
    }
    this.pre.innerHTML = html
  },
}

function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}
