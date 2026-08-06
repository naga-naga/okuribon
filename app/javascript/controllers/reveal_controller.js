import { Controller } from "@hotwired/stimulus"

// 伏せ字の入力欄を一時的に開く。ギフトコードは肩越しに覗かれるだけで渡ってしまうため、
// 既定は伏せたままにし、確かめたいときだけ開く。
// 開いた状態は保存しない。画面を移れば必ず伏せ字に戻る
export default class extends Controller {
  static targets = ["field", "button"]

  toggle() {
    const hidden = this.fieldTarget.type === "password"

    this.fieldTarget.type = hidden ? "text" : "password"
    this.buttonTarget.textContent = hidden ? "隠す" : "表示"
  }
}
