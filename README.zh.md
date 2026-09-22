# Fine

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · **中文**

[![Fine](Assets/fine-demo.gif)](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)

<sub>[观看演示](https://github.com/NEWBIE0413/Fine/raw/refs/heads/main/Assets/fine-demo.mp4)</sub>

把你已经在用的编程智能体收进一个 Mac 窗口。

## 这是什么

Claude Code、Codex、OpenCode 和 omp 各自跑在自己的终端里。Fine 把它们并排放进
一个窗口，当作可以离开、也可以随时回来的对话。

没有包装，也没有重写。每个对话都是原本那个智能体，和在终端里一样运行，
自己的记录也照旧留着。

## 为什么

四个智能体就是四个终端窗口，而没有一个地方记得哪个对话是哪个。Fine 保管这份
清单 —— 你当时在做什么、由哪个智能体在做、进行到哪一步 —— 并从停下的地方重新打开。

开始一个对话时可以自己选智能体和模型，也可以让 Fine 看问题的难度来选。

## 安装

```sh
git clone https://github.com/NEWBIE0413/Fine.git
cd Fine
./scripts/package-app.sh release
ditto .build/Fine.app /Applications/Fine.app
```

带上你想用的智能体就行，装了哪些 Fine 会自己找到。

## 设置

没有设置窗口，也没有登录。账号本来就由各个智能体自己管，Fine 给的是一条命令行：

```sh
fine doctor          # 哪些已就绪、哪些还缺，以及补上它的命令
fine appearance dark # 立即生效
fine tabs            # 现在开着什么
```

它既写给人看，也写给编程智能体直接执行。

## 许可

MIT
