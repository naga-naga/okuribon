import { Controller } from "@hotwired/stimulus"

// 状態ヘッダーが画面の上へ出たら、畳んだ帯に差し替えて上部に残す。
// 下には十数枚のカードが続くので、これが無いと読み進めた先で
// フェーズ・締切までの残り・すべきことの3点が視界から消える（docs/spec.md 6.1）。
//
// 帯は最初から描いてあり、ここでやるのは隠す・出すだけ。JavaScript が動かない
// 環境では帯が出ないままになり、状態ヘッダーがそのまま流れる。
//
// スクロール量ではなく交差で見るのは、状態ヘッダーの高さがフェーズと
// 概要の長さで変わるため。しきい値を px で持つと、どこかのフェーズでずれる
export default class extends Controller {
  static targets = ["header", "bar"]

  connect() {
    this.observer = new IntersectionObserver(([entry]) => this.#update(entry))
    this.observer.observe(this.headerTarget)
  }

  disconnect() {
    this.observer.disconnect()
  }

  // 上へ出たときだけ畳む。ページの途中から上へ戻る途中で状態ヘッダーが
  // 下から近づいてくる間は、まだ本体が読めるので帯を出さない。
  // 出すと同じ3点が上下に並ぶ
  #update(entry) {
    this.barTarget.hidden = entry.isIntersecting || entry.boundingClientRect.top > 0
  }
}
