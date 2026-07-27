FROM ruby:3.4-bookworm

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN apt-get update -o Acquire::Retries=3 \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends -o Acquire::Retries=3 \
        sudo \
        # Rails
        postgresql-client \
        libpq-dev \
        libvips \
        # あると便利
        jq \
        less \
    && rm -rf /var/lib/apt/lists/*

# 非 root ユーザーを用意する。
# Claude Code は root では --dangerously-skip-permissions を受け付けない
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID --create-home --shell /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# アプリの gem はボリュームへ。
# ここで作っておかないとボリュームが root 所有になる
ENV BUNDLE_PATH=/bundle
RUN mkdir -p /bundle && chown -R $USERNAME:$USERNAME /bundle

# Claude Code の認証情報と設定の置き場。同じくボリュームの所有者対策
RUN mkdir -p /home/$USERNAME/.claude \
    && chown -R $USERNAME:$USERNAME /home/$USERNAME/.claude
