import { Controller } from "@hotwired/stimulus"

// 保存すると希望リストごと差し替わるので、掴んでいたハンドルは消え、この controller も
// 作り直される。戻す先はインスタンスに持てないため、モジュールの側に置く
let pendingFocus = null

// 続けて押されたぶんをまとめて送るまでの待ち。順位を何段も上げるときに、
// 1回ごとに往復すると押している最中に画面が入れ替わる
const SAVE_DELAY = 250

// キーが行を送る先。↑↓ は隣へ、Home / End は端へ。ポインタで触れる人はドラッグで
// 一息に動かせるので、端まで送る道をキーの側にも置く。口は1つも増えない
const STEPS = {
  ArrowUp: () => -1,
  ArrowDown: () => 1,
  Home: (index) => -index,
  End: (index, length) => length - 1 - index,
}

// 希望リストを並べ替える。行の並びがそのまま送る並びで、hidden は行の中にあるので
// 行を動かせば一緒に動く。順位は送らず、サーバー側で1から振り直す。
//
// 口はハンドル1つ。つまんで動かすほかに、フォーカスしてキーでも動かせる。
// ↑↓ のボタンを並べると行の口が4つになり、題に6文字しか残らないので、
// キーボードと読み上げに渡る道はハンドル自身が持つ（docs/spec.md 6.2）
export default class extends Controller {
  static targets = ["row", "controls", "position", "title", "handle", "book", "form"]
  static values = { status: String }

  connect() {
    // 並べ替えは JavaScript でしか動かない。動く環境になって初めて口と説明を出す
    this.controlsTargets.forEach((controls) => (controls.hidden = false))

    this.#restoreFocus()
  }

  disconnect() {
    this.#release()
  }

  // ハンドルを掴んだままキーで動かす。ドラッグと同じ口に載せるので、
  // 「並べ替えはここ」と言える場所が行に1つしかない
  key(event) {
    const index = this.handleTargets.indexOf(event.currentTarget)
    const step = STEPS[event.key]?.(index, this.rowTargets.length)

    // 端の行で Home / End を押したときは step が 0 になる。行き先が無い
    if (!step) return

    // 押しっぱなしで画面が一緒に流れると、動かしている行を目で追えなくなる
    event.preventDefault()

    this.#move(index, step)
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

    const handle = this.handleTargets[index]

    step < 0 ? neighbor.before(row) : neighbor.after(row)

    this.#renumber()

    // 行を DOM から抜き差しした時点でフォーカスが外れる。掴んでいた口は行と一緒に
    // 動いた先へ移っているので、そこで掴み直す。戻さないと、続けてもう1つ動かせない
    handle.focus()
    this.#announce(row)

    this.#save(row, step)
  }

  // 動かすと後ろの順位がすべてずれる。1行だけ書き換えると、
  // 画面に出ている順位とリストの何番目かが食い違う
  #renumber() {
    this.positionTargets.forEach((position, index) => (position.textContent = index + 1))
  }

  // 振り直した順位は画面では見えるが、読み上げには何も届かない。
  //
  // 題まで言うのは、前と同じ文になると読み上げそのものが飛ぶため。順位だけだと、
  // 別の本を続けて1位へ送ったときに二度とも「1位に移動しました」になる。
  //
  // 区画は希望リストの外にある。中身と一緒に差し替わると、読み上げる先が
  // 保存のたびに作り直される
  #announce(row) {
    const status = document.getElementById(this.statusValue)
    if (!status) return

    const index = this.rowTargets.indexOf(row)
    status.textContent = `${this.titleTargets[index].textContent}を${index + 1}位に移動しました`
  }

  #save(row, step = 0) {
    pendingFocus = { bookId: this.#bookIdOf(row), step }

    clearTimeout(this.timer)
    // 送り先の form は行を包まない。行の中には外す口の form があり、
    // form は入れ子にできないため、順序を送る hidden は form 属性で結んである
    this.timer = setTimeout(() => this.formTarget.requestSubmit(), SAVE_DELAY)
  }

  // 掴んでいたハンドルへ戻す。ドラッグで動かしたぶんは戻さない。
  // ポインタは行の上にあるので、焦点の輪郭だけが後から付くことになる
  #restoreFocus() {
    const focus = pendingFocus
    pendingFocus = null
    if (!focus || focus.step === 0) return

    const index = this.bookTargets.findIndex((input) => input.value === focus.bookId)
    if (index < 0) return

    this.handleTargets[index]?.focus()
  }

  #bookIdOf(row) {
    return this.bookTargets[this.rowTargets.indexOf(row)].value
  }
}
