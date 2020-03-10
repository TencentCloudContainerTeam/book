# 腾讯云容器服务

## 在线阅读

地址: https://book.kubetencent.io

## 电子书构建

本电子书使用 hugo 构建，采用基于 hugo-theme-learn 二次开发的主题，集成 github actions 自动构建发布到 Github Pages.

## 内容组织

所有文章使用 markdown 文件格式写，主要用中文，放在 `content/zh` 目录下，预留英文目录 `content/en`，若有英文需求，再翻译。

文章内容的每个目录下有一个 `_index.md` 文件，表示父文章，同级目录中其余 md 文件都是这个文件对应文章的下一级文章（子文章）。

## 写作规则

每个 markdown 文件即一篇文章，每篇文章都有一个 yaml 格式的文件头，例如：

``` yaml
---
title: "GPU 虚拟化"
state: TODO
weight: 10
chapter: false
---
```

* `title`: 必选。表示文章标题，此标题会显示在左侧目录树和文章内容的标题中。
* `weight`: 可选。目录树对标题的排序首要考虑 `weight` 大小，若不设置 `weight`，标题的先后顺序就没有保证，通常都需要对内容排序，所以强烈建议设置改值，值越小，排序越靠前，建议以10的倍数为步长来设置，如：第一篇 `weight` 为 10, 第二篇为 20, 若后续想到需要在这两篇之间插一篇，则设置一个 10 到 20 的中间值。
* `state`: 可选。表示此文章的当前状态，通常用 `TODO`, `Alpha`, `Beta` 这个值，内容成熟的文章不设置该字段。如果设置为 `TODO`，主页中的目录展示将对 `TODO` 文章的标题不设置跳转连接，即表示规划中的内容；如果文章设置了该字段其它值，将会在文章内容的开头提示当前文章状态，以知会读者该内容还不够成熟。
* `chapter`: 可选。通常不用设置该字段，设置该字段唯一作用就是改变样式，如果置为 true，内容都会居中显示，并且不显示标题。

## License

![](https://res.cloudinary.com/imroc/image/upload/v1583293970/kubernetes-practice-guide/img/licensebutton.png?classes=no-margin)

[署名-非商业性使用-相同方式共享 4.0 \(CC BY-NC-SA 4.0\)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)
