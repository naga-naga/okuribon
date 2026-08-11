import { Controller } from "@hotwired/stimulus"

// 本のカードをその場で開く。読み比べがこの画面の目的なので、詳細画面へ飛ばすと
// 一覧のどこまで見たかを見失う。開いた1枚はその場で下へ伸び、閉じれば元の高さに戻る。
//
// 全文は最初からカードに入っており、開閉でサーバーへは行かない。
// 抜粋に折るのも、開閉の文字を差し替えるのも CSS なので、
// ここでやることは状態を1つ持つことだけ
export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const open = this.element.toggleAttribute("data-open")

    this.toggleTargets.forEach((button) => button.setAttribute("aria-expanded", open))
  }
}
