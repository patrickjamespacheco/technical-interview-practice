(function (root) {
  "use strict";

  var WORDS = {
    python: new Set("and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield".split(" ")),
    react: new Set("async await break case catch class const continue debugger default delete do else export extends false finally for from function if import in instanceof let new null of return static super switch this throw true try typeof undefined var void while with yield".split(" ")),
    swift: new Set("actor any as associatedtype async await break case catch class continue convenience default defer deinit do else enum extension fallthrough false fileprivate final for func guard if import in indirect init inout internal is isolated let nil nonisolated open operator override package precedencegroup private protocol public repeat required rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while".split(" "))
  };
  var TYPES = new Set("Array Bool Date Decimal Dict Dictionary Double Error Float Int Map Number Object Promise Result Set String Task Tuple URL UUID Void".split(" "));

  function esc(value) {
    return String(value).replace(/[&<>]/g, function (char) { return {"&": "&amp;", "<": "&lt;", ">": "&gt;"}[char]; });
  }

  function span(kind, value) { return '<span class="tok-' + kind + '">' + esc(value) + '</span>'; }

  function closedStringEnd(source, start, quote) {
    var triple = source.slice(start, start + 3) === quote + quote + quote;
    var i = start + (triple ? 3 : 1);
    var target = triple ? quote + quote + quote : quote;
    while (i < source.length) {
      if (source.slice(i, i + target.length) === target) return i + target.length;
      if (!triple && source[i] === "\n") return -1;
      if (source[i] === "\\") i += 2; else i += 1;
    }
    return -1;
  }

  function tokenize(source, language) {
    source = String(source == null ? "" : source);
    language = WORDS[language] ? language : "react";
    var out = "", i = 0;
    while (i < source.length) {
      var rest = source.slice(i), block = rest.match(/^\/\*[\s\S]*?\*\//);
      if (block) { out += span("comment", block[0]); i += block[0].length; continue; }
      if (rest.indexOf("/*") === 0) { out += esc(rest); break; }
      if ((language === "python" && source[i] === "#") || (language !== "python" && rest.indexOf("//") === 0)) {
        var newline = source.indexOf("\n", i), end = newline < 0 ? source.length : newline;
        out += span("comment", source.slice(i, end)); i = end; continue;
      }
      if (source[i] === "'" || source[i] === '"' || (language === "react" && source[i] === "`")) {
        var stringEnd = closedStringEnd(source, i, source[i]);
        if (stringEnd < 0) {
          var lineEnd = source.indexOf("\n", i);
          if (lineEnd < 0) lineEnd = source.length;
          out += esc(source.slice(i, lineEnd)); i = lineEnd; continue;
        }
        out += span("string", source.slice(i, stringEnd)); i = stringEnd; continue;
      }
      var number = rest.match(/^\b(?:0[xob][0-9a-f_]+|\d(?:[\d_]*\.?[\d_]*)?)\b/i);
      if (number) { out += span("number", number[0]); i += number[0].length; continue; }
      var identifier = rest.match(/^[A-Za-z_$][\w$]*/);
      if (identifier) {
        var word = identifier[0], kind = WORDS[language].has(word) ? "keyword" : (TYPES.has(word) || /^[A-Z][A-Za-z0-9_]*$/.test(word) ? "type" : "");
        out += kind ? span(kind, word) : esc(word); i += word.length; continue;
      }
      out += esc(source[i]); i += 1;
    }
    return out;
  }

  function region(source, language, label) {
    return '<div class="source-region" role="region" aria-label="' + esc(label) + '" tabindex="0"><pre><code class="language-' + esc(language) + '">' + tokenize(source, language) + '</code></pre></div>';
  }

  root.ProblemSourceViewer = { escape: esc, tokenize: tokenize, region: region };
}(typeof window === "undefined" ? globalThis : window));
