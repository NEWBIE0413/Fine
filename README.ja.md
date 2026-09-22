<div align="center">

<img src="Assets/fine-1024.png" width="96" alt="">

# Fine

**使っているコーディングエージェントを、ひとつのウィンドウにまとめる Mac アプリ。**

[English](README.md) · [한국어](README.ko.md) · 日本語 · [中文](README.zh.md)

<a href="https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4">
  <img src="Assets/fine-demo.gif" width="720" alt="">
</a>

<sub>クリックでデモを再生</sub>

</div>

---

## できること

Claude Code、Codex、OpenCode、omp はそれぞれ自分のターミナルで動きます。Fine は
それらをひとつのウィンドウにまとめ、離れてもまた戻ってこられる会話として扱います。

包み直したり作り直したりはしていません。どの会話もターミナルで動いていたエージェント
そのままで、積み上げた履歴もそのままです。

## つくった理由

エージェントが四つあればターミナルも四つ。そして、どの会話が何だったかを覚えている
場所はどこにもありません。Fine がそれを持ちます。何をしていたか、どのエージェント
だったか、どこまで進んだか。そして止まったところから開き直します。

始めるときにエージェントとモデルを自分で選んでも、質問の難しさを見て Fine に
選ばせても構いません。

## インストール

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

使いたいエージェントがあれば十分です。入っているものは Fine が見つけます。

## 設定

設定画面もサインインもありません。アカウントは各エージェントが持っているからです。
かわりにコマンドラインがあります。

```sh
fine doctor            # 何が整い、何が足りないか、そして埋める方法
fine appearance dark   # すぐ反映されます
fine tabs              # いま何が開いているか
```

人が読んでもよく、コーディングエージェントがそのまま実行してもよいように
書いてあります。手順は [`skills/fine-setup`](skills/fine-setup/SKILL.md) に。

<div align="center"><sub>MIT</sub></div>
