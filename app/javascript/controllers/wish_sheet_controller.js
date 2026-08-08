import { Controller } from "@hotwired/stimulus"

// 狭い画面で希望リストを畳む。畳んだ状態でも順位のチップは横に残るので、
// 一覧を読んでいる間ずっと「いま何冊・何位まで選んだか」が見えている。
//
// 広い画面では一覧の右に開いたまま置くため、この開閉は効かない（出し分けは CSS 側）。
// 状態はこの要素に置き、希望の追加・削除で差し替えるのは中身だけにする。
// 外枠ごと入れ替えると、シートを開いて操作した瞬間に閉じてしまう
export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const open = this.element.toggleAttribute("data-open")

    this.toggleTargets.forEach((button) => button.setAttribute("aria-expanded", open))
  }
}
