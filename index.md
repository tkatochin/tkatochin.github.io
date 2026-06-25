---
layout: page
title: tkatochin.github.io
tagline: はてなブログ アーカイブ
---
{% include JB/setup %}

はてなブログから取得した記事アーカイブです。

## 最近の記事

<ul class="posts">
  {% for post in site.posts limit:20 %}
    <li><span>{{ post.date | date: "%Y/%m/%d" }}</span> &raquo; <a href="{{ BASE_PATH }}{{ post.url }}">{{ post.title }}</a></li>
  {% endfor %}
</ul>

過去の記事は[アーカイブ]({{ BASE_PATH }}{{ site.JB.archive_path }})から見られます。


