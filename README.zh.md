<div align="center">

<img src="Assets/fine-1024.png" width="96" alt="">

# Fine

**把你在用的编程智能体收进一个 Mac 窗口。**

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · 中文

<a href="https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4">
  <img src="Assets/fine-demo.gif" width="720" alt="">
</a>

<sub>点击观看演示</sub>

</div>

---

## 它做什么

Claude Code、Codex、OpenCode 和 omp 各自跑在自己的终端里。Fine 把它们收进一个
窗口，当作随时可以离开、也随时可以回来的对话。

没有包装，也没有重写。每个对话都是原来那个智能体，和在终端里一样运行，
攒下的记录也照旧。

## 为什么做它

四个智能体就是四个终端窗口，而没有一处记得哪个对话是哪件事。Fine 替你记着：
你当时在做什么、由哪个智能体在做、进行到了哪一步。然后从停下的地方重新打开。

开始时可以自己挑智能体和模型，也可以让 Fine 看问题有多难来挑。

## 安装

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

带上你想用的智能体就够了，装了哪些 Fine 会自己找到。

## 设置

没有设置窗口，也没有登录 —— 账号本来就由各个智能体自己管。取而代之的是一条命令行。

```sh
fine doctor            # 哪些已就绪、哪些还缺，以及怎么补上
fine appearance dark   # 立即生效
fine tabs              # 现在开着什么
```

它既写给人读，也写给编程智能体直接执行。具体步骤见
[`skills/fine-setup`](skills/fine-setup/SKILL.md)。

<div align="center"><sub>MIT</sub></div>
