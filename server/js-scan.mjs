// js-scan.mjs — a JavaScript scanner, used to canonicalize thunk source.
//
// This exists because a thunk id is a content hash, and the content is source
// text. The id must therefore be a function of the source's *meaning*, not of
// its comments or its indentation: two peers that differ only in a comment are
// running the same thunk, and giving them different ids means neither can use
// the other's cached result.
//
// The version this replaces was three regexes:
//
//   src.replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "")
//
// That is not a comment stripper, it is a substring stripper, and it eats
// things that are not comments. `//` inside a string literal is the obvious
// one, and it is not exotic -- a URL is a `//`:
//
//   reduce = () => ({ state: { url: "http://alpha.example/x" } })
//   reduce = () => ({ state: { url: "http://bravo.evil.example" } })
//
// Both clean down to `... "http:` and both hash the same, so two thunks that
// fetch different URLs share one id and one cache entry. That is the bug this
// file fixes, and it is why the scanner tracks string, template and regex
// state rather than searching for delimiters.
//
// The scanner is a single left-to-right pass. It never re-scans its output, so
// a `/` that begins a regex literal is decided once, by whether the previous
// significant token can end an expression.
//
// It is not a full ECMAScript parser and does not need to be: it only has to
// find comments. Anything it cannot classify is a hard error rather than a
// guess, because a wrong guess here is a wrong id, and a wrong id is silent.

/** Thrown when the scanner meets something it will not guess about. */
export class ScanError extends Error {}

const isIdStart = (c) => c !== undefined && /[A-Za-z_$]/.test(c);
const isIdPart = (c) => c !== undefined && /[A-Za-z0-9_$]/.test(c);
const isDigit = (c) => c !== undefined && c >= "0" && c <= "9";

/** Tokens after which a `/` starts a regex literal rather than dividing.
 *  These are the tokens that cannot end an expression, so an operand -- and
 *  therefore a regex -- may follow. `return /x/`, `typeof /x/`, `(/x/)`. */
const REGEX_PRECEDING_KEYWORDS = new Set([
  "return", "typeof", "instanceof", "in", "of", "new", "delete", "void",
  "throw", "case", "do", "else", "yield", "await",
]);

/**
 * Strip comments from JavaScript source.
 *
 * Replaces each comment with a single space, and drops trailing whitespace on
 * every line, so that two sources differing only in comments or indentation
 * produce byte-identical output. Line structure is otherwise preserved:
 * collapsing a blank line is safe, but joining two lines is not, because it can
 * change what an automatic-semicolon-insertion rule does.
 *
 * @param {string} src
 * @returns {string} the source with comments removed
 * @throws {ScanError} on input this scanner will not guess about
 */
export function stripComments(src) {
  const out = [];
  let i = 0;
  // The last significant thing emitted, which is what decides whether a `/` is
  // a regex literal or a division operator. `""` means "start of input".
  let prev = "";
  // How many blank lines to carry forward, so runs of them collapse to one.
  let pendingBreaks = 0;
  // True while the main loop is scanning a `${ ... }` interpolation rather than
  // top-level source. One entry per open interpolation, innermost last, and the
  // entry is the `{` nesting depth *inside* that interpolation -- so the `}`
  // that ends it is the one seen at depth zero. A stack rather than a counter
  // because a template can nest inside another template's interpolation:
  // `` `a ${ `in ${y}` } b` `` has two interpolations open at once.
  const interpStack = [];

  const peek = (k = 0) => src[i + k];
  const atEnd = () => i >= src.length;

  /** Emit a newline, collapsing any run of them into one. */
  const newline = () => {
    if (out.length && out[out.length - 1] !== "\n") out.push("\n");
    pendingBreaks = 0;
  };

  /** Emit whitespace as at most one space: it separates tokens, nothing more. */
  const space = () => {
    if (out.length && out[out.length - 1] !== " " && out[out.length - 1] !== "\n") {
      out.push(" ");
    }
  };

  const lastChar = () => (out.length ? out[out.length - 1] : "");

  /** A `/` here begins a regex literal if the previous token cannot end an
   *  expression. `a / b` divides; `x = /a/` does not. */
  const regexAllowed = () => {
    if (prev === "") return true;
    if (isIdPart(prev)) return REGEX_PRECEDING_KEYWORDS.has(prev);
    // After a closing bracket or quote an operand has ended, so `/` divides.
    // `}` is genuinely ambiguous (`{}` block vs `{}` object literal); treating
    // it as "expression ended" is the conservative reading, because the other
    // reading can swallow a division as a regex and lose the rest of the file.
    return !(prev === ")" || prev === "]" || prev === "}" || prev === '"' || prev === "'" || prev === "`");
  };

  /** Consume a `'...'` or `"..."` string, honouring backslash escapes. */
  const string = (quote) => {
    out.push(quote);
    prev = quote;
    i += 1;
    for (;;) {
      if (atEnd()) throw new ScanError("unterminated string literal");
      const c = src[i];
      if (c === "\\") {
        // Copy both characters of the escape, so an escaped quote does not end
        // the string and `\"` inside it is not read as a real quote.
        out.push(c, peek(1) ?? "");
        i += 2;
        continue;
      }
      out.push(c);
      i += 1;
      if (c === quote) return;
      if (c === "\n") throw new ScanError("newline in a string literal");
    }
  };

  /** Consume a `/.../flags` regex literal. Only reached when `regexAllowed`. */
  const regex = () => {
    out.push("/");
    prev = "/";
    i += 1;
    let inClass = false;
    for (;;) {
      if (atEnd()) throw new ScanError("unterminated regex literal");
      const c = src[i];
      if (c === "\\") {
        out.push(c, peek(1) ?? "");
        i += 2;
        continue;
      }
      if (c === "\n") throw new ScanError("newline in a regex literal");
      if (c === "[") inClass = true;
      else if (c === "]") inClass = false;
      else if (c === "/" && !inClass) {
        out.push(c);
        i += 1;
        // Flags: letters only, and only while they are still adjacent.
        while (isIdPart(peek())) {
          out.push(src[i]);
          i += 1;
        }
        prev = "/";
        return;
      }
      out.push(c);
      i += 1;
    }
  };

  /** Consume a template literal. The `${ ... }` parts are ordinary source and
   *  are scanned by the main loop, so the loop keeps track of being inside an
   *  interpolation: a `}` at nesting depth zero closes it and calls this again
   *  to read the rest of the template.
   *
   *  `resuming` is true on that second call. The opening backtick has already
   *  been emitted and the `${`/`}` are already in `out`, so re-emitting a
   *  backtick here would put one into the output that is not in the source. */
  const template = (resuming = false) => {
    if (!resuming) {
      out.push("`");
      i += 1;
    }
    prev = "`";
    for (;;) {
      if (atEnd()) throw new ScanError("unterminated template literal");
      const c = src[i];
      if (c === "\\") {
        out.push(c, peek(1) ?? "");
        i += 2;
        continue;
      }
      if (c === "`") {
        out.push(c);
        i += 1;
        prev = "`";
        return;
      }
      if (c === "$" && peek(1) === "{") {
        out.push("${");
        i += 2;
        // Entering an interpolation: the main loop scans it and stops at the
        // `}` that closes it, then resumes this template.
        interpStack.push(0);
        return;
      }
      out.push(c);
      i += 1;
    }
  };

  const lineComment = () => {
    while (!atEnd() && src[i] !== "\n") i += 1;
    // `prev` is deliberately unchanged: a comment is not a token, so it must
    // not make a following `/` look like it follows an expression.
  };

  const blockComment = () => {
    i += 2;
    for (;;) {
      if (atEnd()) throw new ScanError("unterminated block comment");
      if (src[i] === "*" && peek(1) === "/") {
        i += 2;
        // A block comment spanning lines still separates two lines of code, so
        // it leaves a newline behind. Otherwise `a /* \n */ b` would join.
        if (/\n/.test(out.join("").slice(-2))) newline();
        return;
      }
      if (src[i] === "\n") {
        newline();
        i += 1;
        continue;
      }
      i += 1;
    }
  };

  /** One iteration of the main loop. Split out so the template's `${ ... }`
   *  handler can re-enter it without duplicating the dispatch. */
  function step() {
    const c = peek();

    // Inside a `${ ... }`: a `}` at depth zero ends the interpolation and hands
    // control back to the template, which resumes scanning for its closing
    // backtick. `{` and `}` nest, so an object literal in the interpolation
    // does not end it early.
    if (interpStack.length) {
      const top = interpStack.length - 1;
      if (c === "{") { interpStack[top] += 1; out.push(c); prev = c; i += 1; return; }
      if (c === "}") {
        if (interpStack[top] > 0) {
          interpStack[top] -= 1;
          out.push(c);
          prev = c;
          i += 1;
          return;
        }
        out.push(c);
        i += 1;
        interpStack.pop();
        template(true);
        return;
      }
    }

    if (c === "\n") {
      newline();
      i += 1;
      return;
    }
    if (c === " " || c === "\t" || c === "\r") {
      space();
      i += 1;
      return;
    }
    if (c === "/" && peek(1) === "/") { lineComment(); return; }
    if (c === "/" && peek(1) === "*") { blockComment(); return; }
    if (c === '"' || c === "'") { string(c); return; }
    if (c === "`") { template(); return; }
    if (c === "/") {
      if (regexAllowed()) { regex(); return; }
      out.push(c);
      prev = c;
      i += 1;
      return;
    }
    if (isIdStart(c)) {
      let j = i;
      while (isIdPart(src[j])) j += 1;
      const word = src.slice(i, j);
      out.push(word);
      prev = word;
      i = j;
      // A number literal is one token: `1.5` must not look like `1` followed by
      // a `.`, or the float branch in `yVal` would never see the fraction.
      return;
    }
    if (isDigit(c) || (c === "." && isDigit(peek(1)))) {
      const start = i;
      while (isDigit(peek())) i += 1;
      if (peek() === ".") { i += 1; while (isDigit(peek())) i += 1; }
      if (peek() === "e" || peek() === "E") {
        const save = i;
        i += 1;
        if (peek() === "+" || peek() === "-") i += 1;
        if (isDigit(peek())) { while (isDigit(peek())) i += 1; } else i = save;
      }
      const num = src.slice(start, i);
      out.push(num);
      prev = num;
      return;
    }
    out.push(c);
    prev = c;
    i += 1;
  }

  while (!atEnd()) step();

  // Trim the ends, and squeeze the blank-line runs the comment removals left.
  let text = out.join("");
  text = text
    .split("\n")
    .map((line) => line.replace(/[ \t]+$/, ""))
    .join("\n")
    .replace(/\n{2,}/g, "\n")
    .trim();
  return text;
}