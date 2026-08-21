import { Controller } from "@hotwired/stimulus"

// 本のカードをその場で開く。読み比べがこの画面の目的なので、詳細画面へ飛ばすと
// 一覧のどこまで見たかを見失う。開いた1枚はその場で下へ伸び、閉じれば元の高さに戻る。
//
// 全文は最初からカードに入っており、開閉でサーバーへは行かない。
// 抜粋に折るのも、開閉の文字を差し替えるのも CSS で足りる。
// ここでやることは、状態を1つ持つことと、折られているかを測ることの2つ
export default class extends Controller {
  static targets = ["toggle", "folded"]

  connect() {
    // 何行に折れるかは幅で決まるので、幅が変わるたびに測り直す。
    // observe した時点でも1回呼ばれるので、最初の1回はこれで足りる
    this.sizes = new ResizeObserver(() => this.#revealToggle())
    this.foldedTargets.forEach((text) => this.sizes.observe(text))

    // 字形が決まる前に測ると、代替の字で収まっていた本文が本来の字で溢れる
    document.fonts?.ready?.then(() => this.#revealToggle())
  }

  disconnect() {
    this.sizes.disconnect()
  }

  toggle() {
    const open = this.element.toggleAttribute("data-open")

    this.toggleTargets.forEach((button) => button.setAttribute("aria-expanded", open))
  }

  // 折って隠れている本文が無ければ、押しても何も起きないボタンになる。出さない。
  //
  // 開いている間は折っていないので、測ると必ず「隠れていない」になる。
  // そのまま伏せると、開いたカードから閉じるボタンが消えて戻れなくなる
  #revealToggle() {
    if (this.element.hasAttribute("data-open")) return

    // 1px は端数の逃げ。行の高さが整数で割り切れないときに、
    // 折っていない本文でも scrollHeight が数十分の1だけ大きく出る
    const folded = this.foldedTargets.some((text) => text.scrollHeight - text.clientHeight > 1)

    this.toggleTargets.forEach((button) => (button.hidden = !folded))
  }
}
