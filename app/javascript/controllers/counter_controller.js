import { Controller } from "@hotwired/stimulus"

// 入力中の文字数を出す。上限ではなく目安なので、超えても止めず色も変えない。
// 字数で切ると、書きたいだけ書けなくなる
export default class extends Controller {
  static targets = ["field", "output"]

  count() {
    this.outputTarget.textContent = this.fieldTarget.value.length
  }
}
