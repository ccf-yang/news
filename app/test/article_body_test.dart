import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/data/article_body.dart';

void main() {
  test('抽取 p 段落并优先使用 article 容器', () {
    const html = '''
<html><head><style>.x{color:red}</style></head>
<body>
<nav>导航导航导航导航导航导航导航导航</nav>
<article>
  <h1>标题</h1>
  <p>这是第一段正文，长度超过十五个字，用来验证解析。</p>
  <p>这是第二段正文，同样超过十五个字，应该被保留下来。</p>
</article>
<footer>页脚页脚页脚页脚页脚页脚页脚页脚</footer>
</body></html>
''';

    final text = ArticleBodyService.extractArticleText(html);
    expect(text, contains('这是第一段正文'));
    expect(text, contains('这是第二段正文'));
    expect(text, isNot(contains('导航')));
    expect(text, isNot(contains('页脚')));
    expect(text, isNot(contains('color:red')));
  });

  test('解码实体与换行', () {
    const html =
        '<p>Tom &amp; Jerry&nbsp;的 &#39;测试&#39; 文本，长度足够触发保留。</p>';
    final text = ArticleBodyService.extractArticleText(html);
    expect(text, contains("Tom & Jerry 的 '测试'"));
  });

  test('没有 p 标签时退化为整页文本', () {
    const html =
        '<div>这是一段没有段落标签的正文内容，长度明显超过一百二十个字符，因此会走到整页纯文本的兜底分支。'
        '再补一些内容：1234567890 1234567890 1234567890 1234567890。</div>';
    final text = ArticleBodyService.extractArticleText(html);
    expect(text, contains('没有段落标签'));
  });

  test('超长正文截断到 18000 字符', () {
    final html = List.generate(
      1000,
      (i) => '<p>第 $i 段内容，每段都超过十五个字的长度要求，所以会被保留。</p>',
    ).join();
    final text = ArticleBodyService.extractArticleText(html);
    expect(text.length, lessThanOrEqualTo(18001));
    expect(text.endsWith('…'), isTrue);
  });
}
