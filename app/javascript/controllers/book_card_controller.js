import { Controller } from "@hotwired/stimulus"

// 本のカードをその場で開く。読み比べがこの画面の目的なので、詳細画面へ飛ばすと
// 列の中のどこまで見たかを見失う。開いた1枚はその行を占め、閉じれば元の位置に戻る。
//
// 全文は最初からカードに入っており、開閉でサーバーへは行かない。
// 抜粋に折るのも CSS なので、ここでやることは状態を1つ持つことだけ
export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const open = this.element.toggleAttribute("data-open")

    // 開く口と閉じる口は別々のボタンだが、開き先は1つ。両方に同じ状態を配る
    this.toggleTargets.forEach((button) => button.setAttribute("aria-expanded", open))
  }
}
