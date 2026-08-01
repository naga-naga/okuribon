# frozen_string_literal: true

# ログイン状態の出し入れをここへ集約する。
# セッションに置くのは利用者の id だけにする。表示名やアバターまで持たせると、
# 本人が変えたあともログインし直すまで古い値が出続ける
module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :logged_in?
  end

  private

  # 見つからないことも結果なので、nil も含めて1リクエストに1回だけ引く
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  # ログインのたびにセッションを作り直す。ログイン前に配ったセッション ID が
  # ログイン後もそのまま通ると、攻撃者が先に踏ませた ID で本人になりすませる
  def log_in(user)
    reset_session
    session[:user_id] = user.id
    @current_user = user
  end

  def log_out
    reset_session
    @current_user = nil
  end

  # 保護された画面のコントローラで before_action に指定する
  def require_login
    return if logged_in?

    store_return_to
    redirect_to login_path
  end

  # 覚えるのはサーバーが見た URL だけ。パラメータや Referer からは受け取らない。
  # 戻り先を外から渡せると、ログインを踏ませるだけで外部サイトへ飛ばせる。
  # 書き込みは覚えない。ログインしただけで送信をやり直させてしまう
  def store_return_to
    session[:return_to] = request.fullpath if request.get?
  end

  # 一度使ったら消す。残すと、次のログインで関係のない画面へ飛ぶ
  def pop_return_to
    session.delete(:return_to) || root_path
  end
end
