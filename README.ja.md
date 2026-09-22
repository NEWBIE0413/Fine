# Fine

[English](README.md) · [한국어](README.ko.md) · **日本語** · [中文](README.zh.md)

[![Fine](Assets/fine-demo.gif)](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)

<sub>[デモを見る](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)</sub>

すでに使っているコーディングエージェントを、ひとつのウィンドウにまとめる Mac アプリ。

## これは何か

Claude Code、Codex、OpenCode、omp はそれぞれ自分のターミナルで動きます。Fine は
それらをひとつのウィンドウに並べ、離れてもまた戻ってこられる会話として扱います。

包んだり作り直したりはしていません。どの会話もターミナルで動いていたエージェント
そのもので、自分の履歴もそのまま持っています。

## なぜ

エージェントが四つあればターミナルも四つになり、どの会話が何だったかを覚えている
場所はどこにもありません。Fine がその一覧を持ちます — 何をしていたか、どのエージェント
だったか、どこまで進んだか。そして止まったところから開き直します。

会話を始めるときにエージェントとモデルを選ぶこともできますし、質問の難しさを見て
Fine に選ばせることもできます。

## インストール

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

使いたいエージェントがあれば十分です。入っているものを Fine が見つけます。

## 設定

設定画面もサインインもありません。アカウントはエージェントがそれぞれ持っていて、
Fine にはかわりにコマンドラインがあります:

```sh
fine doctor          # 何が整っていて、何が足りず、それを埋めるコマンド
fine appearance dark # すぐに反映されます
fine tabs            # 何が開いているか
```

人が読んでもよく、コーディングエージェントがそのまま実行してもよいように
作られています。

## ライセンス

MIT
