import { Controller } from "@hotwired/stimulus"

// 伏せ字の入力欄を一時的に開く。ギフトコードは肩越しに覗かれるだけで渡ってしまうため、
// 既定は伏せたままにし、確かめたいときだけ開く。
//
// 開きっぱなしにはしない。入力中の画面はそのまま放置されやすく、
// 席を立っている間に読まれる。一定時間で自ら伏せ字へ戻す。
// 開いた状態は保存しないので、画面を移れば必ず伏せ字に戻る
export default class extends Controller {
  static targets = ["field", "button", "warning"]
  static values = { revertAfter: { type: Number, default: 10000 } }

  disconnect() {
    this.#clearTimer()
  }

  toggle() {
    this.fieldTarget.type === "password" ? this.show() : this.hide()
  }

  show() {
    this.fieldTarget.type = "text"
    this.buttonTarget.textContent = "隠す"
    this.#toggleWarning(true)

    this.#clearTimer()
    this.timer = setTimeout(() => this.hide(), this.revertAfterValue)
  }

  hide() {
    this.fieldTarget.type = "password"
    this.buttonTarget.textContent = "表示"
    this.#toggleWarning(false)

    this.#clearTimer()
  }

  #toggleWarning(shown) {
    if (this.hasWarningTarget) this.warningTarget.classList.toggle("hidden", !shown)
  }

  #clearTimer() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }
}
