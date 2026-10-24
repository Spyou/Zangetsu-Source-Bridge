import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:pseudom/pseudom.dart' as pseudom;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

void _initPseudoSelector() {
  (int, int) parseNth(String arg) {
    arg = arg.toLowerCase().replaceAll(' ', '');
    if (arg == 'odd') return (2, 1);
    if (arg == 'even') return (2, 0);
    final match = RegExp(r'^(\d*)n([+-]?\d+)?$').firstMatch(arg);
    if (match != null) {
      final aStr = match.group(1);
      final a = aStr == null || aStr.isEmpty ? 1 : int.parse(aStr);
      final bStr = match.group(2);
      final b = bStr == null ? 0 : int.parse(bStr);
      return (a, b);
    }
    final n = int.tryParse(arg);
    return n != null ? (0, n) : (0, 0);
  }

  bool matchesNth(int index, int a, int b) {
    if (a == 0) return index == b;
    final diff = index - b;
    return diff % a == 0 && diff ~/ a >= 0;
  }

  String wholeText(Element element) => element.nodes.map((node) {
    if (node is Text) return node.text;
    if (node is Element) return wholeText(node);
    return '';
  }).join();

  String ownText(Element element) =>
      element.nodes.whereType<Text>().map((t) => t.text).join();

  bool nthChild(Element element, String? args) {
    final parent = element.parent;
    if (args == null || parent == null) return false;
    final (a, b) = parseNth(args);
    return matchesNth(parent.children.indexOf(element) + 1, a, b);
  }

  bool nthLastChild(Element element, String? args) {
    final parent = element.parent;
    if (args == null || parent == null) return false;
    final (a, b) = parseNth(args);
    return matchesNth(parent.children.length - parent.children.indexOf(element), a, b);
  }

  bool nthOfType(Element element, String? args) {
    final parent = element.parent;
    if (args == null || parent == null) return false;
    final siblings = parent.children.where((e) => e.localName == element.localName).toList();
    final (a, b) = parseNth(args);
    return matchesNth(siblings.indexOf(element) + 1, a, b);
  }

  bool nthLastOfType(Element element, String? args) {
    final parent = element.parent;
    if (args == null || parent == null) return false;
    final siblings = parent.children.where((e) => e.localName == element.localName).toList();
    final (a, b) = parseNth(args);
    return matchesNth(siblings.length - siblings.indexOf(element), a, b);
  }

  bool has(Element element, String? args) =>
      args != null && (pseudom.parse(args).selectFirst(element) != null ||
          (element.parent != null && pseudom.parse(args).selectFirst(element.parent!) == element));

  bool not(Element element, String? args) =>
      args != null && pseudom.parse(args).selectFirst(element) == null;

  bool contains(Element element, String? args) =>
      element.text.toLowerCase().contains((args ?? '').toLowerCase());

  bool containsOwn(Element element, String? args) =>
      ownText(element).toLowerCase().contains((args ?? '').toLowerCase());

  bool matches(Element element, String? args) {
    if (args == null) return false;
    try {
      return RegExp(args, caseSensitive: false).hasMatch(element.text);
    } catch (_) {
      return false;
    }
  }

  bool containsData(Element element, String? args) {
    final tag = element.localName;
    if (tag != 'script' && tag != 'style') return false;
    return element.text.toLowerCase().contains((args ?? '').toLowerCase());
  }

  bool containsWholeText(Element element, String? args) =>
      wholeText(element).contains(args ?? '');

  bool containsWholeOwnText(Element element, String? args) =>
      ownText(element).contains(args ?? '');

  bool matchesWholeText(Element element, String? args) {
    if (args == null) return false;
    try {
      return RegExp(args).hasMatch(wholeText(element));
    } catch (_) {
      return false;
    }
  }

  bool matchesWholeOwnText(Element element, String? args) {
    if (args == null) return false;
    try {
      return RegExp(args).hasMatch(ownText(element));
    } catch (_) {
      return false;
    }
  }

  bool isSelector(Element element, String? args) {
    if (args == null) return false;
    for (final selector in args.split(',').map((s) => s.trim())) {
      try {
        if (pseudom.parse(selector).selectFirst(element) != null) return true;
      } catch (_) {}
    }
    return false;
  }

  pseudom.PseudoSelector.handlers['nth-child'] = nthChild;
  pseudom.PseudoSelector.handlers['nth-last-child'] = nthLastChild;
  pseudom.PseudoSelector.handlers['nth-of-type'] = nthOfType;
  pseudom.PseudoSelector.handlers['nth-last-of-type'] = nthLastOfType;
  pseudom.PseudoSelector.handlers['has'] = has;
  pseudom.PseudoSelector.handlers['inot'] = not;
  pseudom.PseudoSelector.handlers['contains'] = contains;
  pseudom.PseudoSelector.handlers['containsOwn'] = containsOwn;
  pseudom.PseudoSelector.handlers['containsData'] = containsData;
  pseudom.PseudoSelector.handlers['containsWholeText'] = containsWholeText;
  pseudom.PseudoSelector.handlers['containsWholeOwnText'] = containsWholeOwnText;
  pseudom.PseudoSelector.handlers['matches'] = matches;
  pseudom.PseudoSelector.handlers['matchesWholeText'] = matchesWholeText;
  pseudom.PseudoSelector.handlers['matchesWholeOwnText'] = matchesWholeOwnText;
  pseudom.PseudoSelector.handlers['is'] = isSelector;
  pseudom.PseudoSelector.handlers['first-child'] = (e, _) => e.previousElementSibling == null;
  pseudom.PseudoSelector.handlers['last-child'] = (e, _) => e.nextElementSibling == null;
  pseudom.PseudoSelector.handlers['first-of-type'] = (e, _) {
    final p = e.parent;
    return p != null && p.children.where((c) => c.localName == e.localName).first == e;
  };
  pseudom.PseudoSelector.handlers['last-of-type'] = (e, _) {
    final p = e.parent;
    return p != null && p.children.where((c) => c.localName == e.localName).last == e;
  };
  pseudom.PseudoSelector.handlers['only-child'] =
      (e, _) => e.previousElementSibling == null && e.nextElementSibling == null;
  pseudom.PseudoSelector.handlers['only-of-type'] = (e, _) {
    final p = e.parent;
    return p != null && p.children.where((c) => c.localName == e.localName).length == 1;
  };
  pseudom.PseudoSelector.handlers['empty'] = (e, _) => e.children.isEmpty && e.text.trim().isEmpty;
  pseudom.PseudoSelector.handlers['root'] = (e, _) => e.parent == null;
  pseudom.PseudoSelector.handlers['lt'] = (e, args) {
    final n = int.tryParse(args ?? '');
    final p = e.parent;
    return n != null && p != null && p.children.indexOf(e) < n;
  };
  pseudom.PseudoSelector.handlers['gt'] = (e, args) {
    final n = int.tryParse(args ?? '');
    final p = e.parent;
    return n != null && p != null && p.children.indexOf(e) > n;
  };
  pseudom.PseudoSelector.handlers['eq'] = (e, args) {
    final n = int.tryParse(args ?? '');
    final p = e.parent;
    return n != null && p != null && p.children.indexOf(e) == n;
  };
}

String _fixSelector(String selector) => selector.replaceAll(':not', ':inot');

List<Element>? selectFrom(Document? doc, String selector) {
  try {
    _initPseudoSelector();
    final root = doc?.documentElement;
    if (root == null) return null;
    return pseudom.parse(_fixSelector(selector)).select(root).toList();
  } catch (_) {
    return null;
  }
}

Element? selectFirstFrom(Document? doc, String selector) {
  try {
    _initPseudoSelector();
    final root = doc?.documentElement;
    if (root == null) return null;
    return pseudom.parse(_fixSelector(selector)).selectFirst(root);
  } catch (_) {
    return null;
  }
}

List<Element>? selectFromElement(Element? element, String selector) {
  if (element == null) return null;
  try {
    _initPseudoSelector();
    return pseudom.parse(_fixSelector(selector)).select(element).toList();
  } catch (_) {
    return null;
  }
}

Element? selectFirstFromElement(Element? element, String selector) {
  if (element == null) return null;
  try {
    _initPseudoSelector();
    return pseudom.parse(_fixSelector(selector)).selectFirst(element);
  } catch (_) {
    return null;
  }
}

String? regSrc(String html) => RegExp(r'src="([^"]+)"').firstMatch(html)?.group(1);
String? regImg(String html) => RegExp(r'img="([^"]+)"').firstMatch(html)?.group(1);
String? regHref(String html) => RegExp(r'href="([^"]+)"').firstMatch(html)?.group(1);
String? regDataSrc(String html) => RegExp(r'data-src="([^"]+)"').firstMatch(html)?.group(1);

String? attrOf(Document? doc, String attribute) {
  try {
    return doc?.attributes[attribute];
  } catch (_) {
    return null;
  }
}

String? xpathFirstOf(Document? doc, String xpath) {
  final root = doc?.documentElement;
  if (root == null) return null;
  return HtmlXPath.node(root).query(xpath).attr;
}

List<String> xpathOf(Document? doc, String xpath) {
  final root = doc?.documentElement;
  if (root == null) return [];
  final query = HtmlXPath.node(root).query(xpath);
  if (query.nodes.length <= 1) return [];
  return query.attrs.map((e) => e!.trim()).toList();
}

String? elementXpathFirst(Element? element, String xpath) {
  if (element == null) return null;
  return HtmlXPath.node(element).query(xpath).attr;
}

List<String> elementXpath(Element? element, String xpath) {
  if (element == null) return [];
  final query = HtmlXPath.node(element).query(xpath);
  if (query.nodes.length <= 1) return [];
  return query.attrs.map((e) => e!.trim()).toList();
}

class MDocument {
  const MDocument(this._document);

  final Document? _document;

  factory MDocument.parse(String html) => MDocument(parse(html));

  MElement? get body => MElement(_document?.body);
  MElement? get documentElement => MElement(_document?.documentElement);
  MElement? get head => MElement(_document?.head);
  MElement? get parent => MElement(_document?.parent);
  String? get outerHtml => _document?.outerHtml;
  String? get text => _document?.text?.trim();
  List<MElement>? get children => _document?.children.map(MElement.new).toList();

  List<MElement>? select(String selector) =>
      selectFrom(_document, selector)?.map(MElement.new).toList();

  MElement? selectFirst(String selector) => MElement(selectFirstFrom(_document, selector));

  String? xpathFirst(String xpath) => xpathFirstOf(_document, xpath);
  List<String> xpath(String xpath) => xpathOf(_document, xpath);

  List<MElement>? getElementsByClassName(String classNames) => _document
      ?.getElementsByClassName(classNames)
      .map(MElement.new)
      .toList();

  List<MElement>? getElementsByTagName(String localNames) => _document
      ?.getElementsByTagName(localNames)
      .map(MElement.new)
      .toList();

  MElement? getElementById(String id) => MElement(_document?.getElementById(id));
  String? attr(String attribute) => attrOf(_document, attribute)?.trim();
  bool hasAttr(String attribute) => _document?.attributes.containsKey(attribute) ?? false;
}

class MElement {
  MElement(this._element);

  final Element? _element;

  String? get outerHtml => _element?.outerHtml;
  String? get innerHtml => _element?.innerHtml;
  String? get text => _element?.text.trim();
  String? get className => _element?.className;
  String? get localName => _element?.localName;
  String? get namespaceUri => _element?.namespaceUri;
  String? get getSrc => _element == null ? null : regSrc(_element.outerHtml);
  String? get getImg => _element == null ? null : regImg(_element.outerHtml);
  String? get getHref => _element == null ? null : regHref(_element.outerHtml);
  String? get getDataSrc => _element == null ? null : regDataSrc(_element.outerHtml);
  List<MElement>? get children => _element?.children.map(MElement.new).toList();
  MElement? get parent => MElement(_element?.parent);
  MElement? get nextElementSibling => MElement(_element?.nextElementSibling);
  MElement? get previousElementSibling => MElement(_element?.previousElementSibling);

  List<MElement>? select(String selector) =>
      selectFromElement(_element, selector)?.map(MElement.new).toList();

  MElement? selectFirst(String selector) => MElement(selectFirstFromElement(_element, selector));

  String? xpathFirst(String xpath) => elementXpathFirst(_element, xpath);
  List<String> xpath(String xpath) => elementXpath(_element, xpath);

  List<MElement>? getElementsByClassName(String classNames) =>
      _element?.getElementsByClassName(classNames).map(MElement.new).toList();

  List<MElement>? getElementsByTagName(String localNames) =>
      _element?.getElementsByTagName(localNames).map(MElement.new).toList();

  String? attr(String attribute) => _element?.attributes[attribute];
  bool hasAttr(String attribute) => _element?.attributes.containsKey(attribute) ?? false;
}
