import { Controller } from "@hotwired/stimulus"

// 招待URLをクリップボードへ写す。押したあとにボタンの文字を変えて、
// 見た目の変わらない操作が済んだことを伝える。
//
// navigator.clipboard は安全なコンテキスト（https と localhost）でしか使えない。
// 素の http で開いた開発機やLAN内のホストでは undefined になるので、
// 入力欄の選択に落として、あとは利用者の手でコピーできる状態にする
export default class extends Controller {
  static targets = ["source", "button"]
  static values = { revertAfter: { type: Number, default: 2000 } }

  disconnect() {
    this.#clearTimer()
  }

  async copy() {
    this.sourceTarget.select()

    if (!navigator.clipboard) return

    await navigator.clipboard.writeText(this.sourceTarget.value)
    this.#flash("コピーしました")
  }

  #flash(label) {
    this.buttonTarget.textContent = label

    this.#clearTimer()
    this.timer = setTimeout(() => {
      this.buttonTarget.textContent = "コピー"
    }, this.revertAfterValue)
  }

  #clearTimer() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }
}
