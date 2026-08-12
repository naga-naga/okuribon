import { Controller } from "@hotwired/stimulus"

// 保存すると希望リストごと差し替わるので、押していたボタンは消え、この controller も
// 作り直される。戻す先はインスタンスに持てないため、モジュールの側に置く
let pendingFocus = null

// 続けて押されたぶんをまとめて送るまでの待ち。順位を何段も上げるときに、
// 1回ごとに往復すると押している最中に画面が入れ替わる
const SAVE_DELAY = 250

// 希望リストを並べ替える。行の並びがそのまま送る並びで、hidden は行の中にあるので
// 行を動かせば一緒に動く。順位は送らず、サーバー側で1から振り直す。
//
// つまむ口と ↑↓ の2つを置く。ドラッグはつまめる人にしか使えず、
// キーボードからは届かない。↑↓ だけが読み上げにも渡る道になる
export default class extends Controller {
  static targets = ["row", "controls", "position", "handle", "up", "down", "book"]

  connect() {
    // 並べ替えは JavaScript でしか動かない。動く環境になって初めて口を出す
    this.controlsTargets.forEach((controls) => (controls.hidden = false))

    this.#restoreFocus()
  }

  disconnect() {
    this.#release()
  }

  moveUp(event) {
    this.#move(this.upTargets.indexOf(event.currentTarget), -1)
  }

  moveDown(event) {
    this.#move(this.downTargets.indexOf(event.currentTarget), 1)
  }

  // つまんだところから離すまでを1回の並べ替えとして扱う。
  //
  // 続きは window で受ける。setPointerCapture でつまんだ行に寄せると、
  // 差し込みのたびに行が DOM から抜き差しされ、その時点で捕まえた手が離れる。
  // 1行ぶん動かしたところで追従が止まってしまう
  grab(event) {
    if (this.dragging) return

    event.preventDefault()

    this.dragging = this.rowTargets[this.handleTargets.indexOf(event.currentTarget)]
    this.dragging.setAttribute("data-dragging", "")

    // 持ち上げた行はポインタと同じだけ動かす。つまんだ位置を起点にするので、
    // ハンドルのどこを掴んでも指の下から行がずれない
    this.grabbedAt = event.clientY
    this.shift = 0

    window.addEventListener("pointermove", this.#drag)
    window.addEventListener("pointerup", this.#drop)
    // 着信などで取り上げられたときも、動かしたところまでは保存する。
    // 画面に出ている並びと保存された並びが食い違うほうが困る
    window.addEventListener("pointercancel", this.#drop)
  }

  // 重ねた行の半分を越えたら、その前か後ろへ差し込む。行そのものが動くので、
  // 落ちる位置を別に描かなくても、いまどこへ入るかが順位ごと見えている。
  //
  // 差し込みで動くのは行の居場所で、持ち上げた見た目のほうはポインタに置いていく。
  // 居場所が1つぶん飛んだぶんを shift に溜めて打ち消さないと、順位が入れ替わる
  // たびに行が指から離れて跳ねる
  #drag = (event) => {
    const over = this.rowTargets.find((row) => {
      if (row === this.dragging) return false

      const { top, bottom } = row.getBoundingClientRect()
      return event.clientY >= top && event.clientY <= bottom
    })

    if (over) {
      const before = this.dragging.getBoundingClientRect().top

      const { top, height } = over.getBoundingClientRect()
      event.clientY > top + height / 2 ? over.after(this.dragging) : over.before(this.dragging)

      this.shift += before - this.dragging.getBoundingClientRect().top

      this.#renumber()
    }

    // 一覧の外へ出ても追従は続ける。指は止まっていないのに行だけ止まると、
    // つまんだものが手から外れたように見える
    this.dragging.style.transform = `translateY(${event.clientY - this.grabbedAt + this.shift}px)`
  }

  #drop = () => {
    const row = this.dragging

    this.#release()
    this.#save(row)
  }

  #release() {
    if (!this.dragging) return

    this.dragging.removeAttribute("data-dragging")
    this.dragging.style.transform = ""
    this.dragging = null

    window.removeEventListener("pointermove", this.#drag)
    window.removeEventListener("pointerup", this.#drop)
    window.removeEventListener("pointercancel", this.#drop)
  }

  #move(index, step) {
    const row = this.rowTargets[index]
    const neighbor = this.rowTargets[index + step]
    if (!row || !neighbor) return

    step < 0 ? neighbor.before(row) : neighbor.after(row)

    this.#renumber()
    this.#save(row, step)
  }

  // 動かすと後ろの順位がすべてずれる。1行だけ書き換えると、
  // 画面に出ている順位とリストの何番目かが食い違う
  #renumber() {
    this.positionTargets.forEach((position, index) => (position.textContent = index + 1))
    this.upTargets.forEach((button, index) => (button.disabled = index === 0))
    this.downTargets.forEach((button, index) => (button.disabled = index === this.downTargets.length - 1))
  }

  #save(row, step = 0) {
    pendingFocus = { bookId: this.#bookIdOf(row), step }

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), SAVE_DELAY)
  }

  // 押していたボタンへ戻す。端まで来て押せなくなった行は、そこで手が止まるので戻さない
  #restoreFocus() {
    const focus = pendingFocus
    pendingFocus = null
    if (!focus || focus.step === 0) return

    const index = this.bookTargets.findIndex((input) => input.value === focus.bookId)
    if (index < 0) return

    const button = (focus.step < 0 ? this.upTargets : this.downTargets)[index]
    if (button && !button.disabled) button.focus()
  }

  #bookIdOf(row) {
    return this.bookTargets[this.rowTargets.indexOf(row)].value
  }
}
