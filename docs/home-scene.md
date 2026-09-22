# 홈 화면 배경 바꾸기

다크 모드 홈 화면 위쪽의 장면을 원하는 그림으로 바꿀 수 있다.

```sh
cp ~/Downloads/내그림.png ~/.fine/home-scene.png
```

Fine의 홈 화면을 다시 열면 반영된다. 빌드도, 저장소 수정도 필요 없다.

- 받는 확장자: `png` `jpg` `jpeg` `heic` `webp` (이 순서로 먼저 찾은 것을 쓴다)
- 파일을 지우면 기본 장면(절차적 밤하늘)으로 돌아간다
- 그림은 위쪽에 걸리고 아래로 갈수록 옅어져 바탕에 녹는다. 위쪽 2/3에 초점이 있는 그림이 잘 맞는다
- 가로로 꽉 채우고 세로는 잘라내므로, 가로로 긴 그림이 유리하다

## 빌드에 넣고 싶다면

`Sources/Fine/HarnessIcons.xcassets/HomeScene.imageset/`에 이미지와 `Contents.json`을 두면
번들에서 찾는다. 이 경로는 `.gitignore`에 있어 저장소에 올라가지 않는다 —
남의 그림을 공개 저장소에 싣지 않기 위해서다.

## 찾는 순서

1. `~/.fine/home-scene.*`
2. 번들의 `HomeScene` 에셋
3. 절차적 밤하늘 (기본값)
