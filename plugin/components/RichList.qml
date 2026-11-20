import QtQml

// Bullet-list editing on the editor's HTML.
//
// QML has no QTextCursor, and TextEdit.insert() cannot extend an existing
// list (an inserted fragment always starts a new QTextList, and its first
// block merges into the current one). So list edits re-parse the document's
// HTML (TextEdit.text, as Qt exports it) into one entry per paragraph, edit
// that, and serialise it back. Every function here is pure: it takes the HTML
// and the raw getText() projection (U+2029 between paragraphs) and returns new
// HTML, or null when the document holds something it does not model (tables),
// so the caller can leave the document alone.
QtObject {
    id: lib

    readonly property string defaultListStyle: "margin-top: 0px; margin-bottom: 0px; margin-left: 0px; margin-right: 0px;"
    readonly property string defaultBlockStyle: "margin-top:0px; margin-bottom:0px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;"
    // "- ", "* ", "• ", "1. ", "2) "... at the start of a pasted paragraph.
    readonly property var bulletPattern: /^([ \t]*)([-*+•◦▪‣–·]|\d{1,3}[.)])[ \t]+/

    function styleOf(attrs) {
        const m = /style="([^"]*)"/.exec(attrs || "");
        return m ? m[1] : "";
    }

    function withStyle(style) {
        return style ? ' style="' + style + '"' : "";
    }

    function setStyleProp(style, prop, value) {
        const re = new RegExp("(^|;)\\s*" + prop + "\\s*:[^;]*;?", "g");
        const rest = style.replace(re, "$1").trim();
        return (prop + ":" + value + "; " + rest).trim();
    }

    function removeStyleProp(style, prop) {
        const re = new RegExp("(^|;)\\s*" + prop + "\\s*:[^;]*;?", "g");
        return style.replace(re, "$1").trim();
    }

    // ── parse ────────────────────────────────────────────────────────────
    // One block per paragraph: {kind: "li", listTag, listStyle, depth, style,
    // inner}, {kind: "p", tag, style, inner} or {kind: "raw", html} (<hr />).
    function parse(html) {
        const open = /<body[^>]*>/.exec(html);
        const close = html.lastIndexOf("</body>");
        if (!open || close < 0)
            return null;
        const head = html.slice(0, open.index + open[0].length);
        const tail = html.slice(close);
        const body = html.slice(open.index + open[0].length, close);

        const blocks = [];
        const lists = [];
        let current = null;
        let depthInTags = 0;
        const tagRe = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/g;
        let last = 0;
        let m;

        const flushText = upTo => {
            if (current)
                current.inner += body.slice(last, upTo);
        };

        while ((m = tagRe.exec(body)) !== null) {
            const closing = m[1] === "/";
            const name = m[2].toLowerCase();
            const attrs = m[3];

            if (name === "table" || name === "tr" || name === "td" || name === "th" || name === "div")
                return null;

            const isList = name === "ul" || name === "ol";
            const isBlock = name === "p" || name === "li" || name === "pre" || /^h[1-6]$/.test(name);

            if (!isList && !isBlock && name !== "hr") {
                // Inline markup stays in the current block.
                flushText(m.index + m[0].length);
                last = m.index + m[0].length;
                continue;
            }

            flushText(m.index);
            last = m.index + m[0].length;

            if (isList) {
                current = null;
                if (closing)
                    lists.pop();
                else
                    lists.push({
                        tag: name,
                        style: styleOf(attrs)
                    });
            } else if (name === "hr") {
                current = null;
                blocks.push({
                    kind: "raw",
                    html: "<hr />"
                });
            } else if (closing) {
                current = null;
            } else if (name === "li") {
                const list = lists[lists.length - 1];
                if (!list)
                    return null;
                current = {
                    kind: "li",
                    listTag: list.tag,
                    listStyle: list.style,
                    depth: lists.length,
                    style: styleOf(attrs),
                    inner: ""
                };
                blocks.push(current);
            } else {
                current = {
                    kind: "p",
                    tag: name,
                    style: styleOf(attrs),
                    inner: ""
                };
                blocks.push(current);
            }
        }
        blocks.forEach(b => {
            if (b.kind === "raw")
                return;
            // Qt writes an empty paragraph as <br />; that is no character.
            if (/-qt-paragraph-type:\s*empty/.test(b.style)) {
                b.inner = "";
                b.style = removeStyleProp(b.style, "-qt-paragraph-type");
            }
            b.inner = b.inner.replace(/^\n+/, "").replace(/\n+$/, "");
        });
        return {
            head: head,
            tail: tail,
            blocks: blocks
        };
    }

    // ── serialise ────────────────────────────────────────────────────────
    function blockStyle(b) {
        let style = b.style || defaultBlockStyle;
        if (b.kind === "li") {
            // List items run flush; a rebuilt list keeps no stray gaps.
            style = setStyleProp(style, "margin-bottom", "0px");
            style = setStyleProp(style, "margin-top", "0px");
        }
        if (b.inner === "")
            style = "-qt-paragraph-type:empty; " + style;
        return style;
    }

    function serialize(doc) {
        const out = [];
        const open = []; // {tag, liOpen}
        const closeLevel = () => {
            const level = open.pop();
            if (level.liOpen)
                out.push("</li>");
            out.push("</" + level.tag + ">");
        };

        doc.blocks.forEach(b => {
            const inner = b.inner === "" ? "<br />" : b.inner;
            if (b.kind !== "li") {
                while (open.length > 0)
                    closeLevel();
                out.push(b.kind === "raw" ? b.html : "<" + b.tag + withStyle(blockStyle(b)) + ">" + inner + "</" + b.tag + ">");
                return;
            }
            const depth = Math.max(1, b.depth);
            while (open.length > depth)
                closeLevel();
            if (open.length === depth && open[depth - 1].tag !== b.listTag)
                closeLevel();
            while (open.length < depth) {
                const listStyle = setStyleProp(b.listStyle || defaultListStyle, "-qt-list-indent", String(open.length + 1));
                out.push("\n<" + b.listTag + withStyle(listStyle) + ">");
                open.push({
                    tag: b.listTag,
                    liOpen: false
                });
            }
            const level = open[open.length - 1];
            if (level.liOpen)
                out.push("</li>");
            out.push("\n<li" + withStyle(blockStyle(b)) + ">" + inner);
            level.liOpen = true;
        });
        while (open.length > 0)
            closeLevel();
        return doc.head + "\n" + out.join("").replace(/^\n/, "") + doc.tail;
    }

    // ── positions ────────────────────────────────────────────────────────
    // Start offset of every paragraph in the raw getText() projection.
    function paragraphStarts(raw) {
        const starts = [0];
        for (let i = 0; i < raw.length; i++) {
            if (raw.charCodeAt(i) === 0x2029)
                starts.push(i + 1);
        }
        return starts;
    }

    function paragraphAt(starts, pos) {
        let i = 0;
        while (i + 1 < starts.length && starts[i + 1] <= pos)
            i++;
        return i;
    }

    function load(html, raw) {
        const doc = parse(html);
        if (!doc || doc.blocks.length !== paragraphStarts(raw).length)
            return null;
        return doc;
    }

    // Split inline HTML after `offset` characters of its text, closing the
    // inline tags open at that point on the left and reopening them on the right.
    function splitInner(inner, offset) {
        const stack = [];
        let count = 0;
        let i = 0;
        while (i < inner.length && count < offset) {
            const c = inner[i];
            if (c === "<") {
                const end = inner.indexOf(">", i);
                if (end < 0)
                    break;
                const tag = inner.slice(i, end + 1);
                const m = /^<(\/?)([a-zA-Z][a-zA-Z0-9]*)/.exec(tag);
                const name = m ? m[2].toLowerCase() : "";
                if (name === "br" || name === "img")
                    count++;
                else if (m && m[1] === "/")
                    stack.pop();
                else if (m && !/\/>$/.test(tag))
                    stack.push({
                        name: name,
                        tag: tag
                    });
                i = end + 1;
            } else if (c === "&") {
                const end = inner.indexOf(";", i);
                i = end > i && end - i <= 10 ? end + 1 : i + 1;
                count++;
            } else {
                i++;
                count++;
            }
        }
        // Tags that open right at the split point belong to the right side.
        while (i < inner.length && inner[i] === "<" && inner[i + 1] !== "/") {
            const end = inner.indexOf(">", i);
            const tag = inner.slice(i, end + 1);
            const m = /^<([a-zA-Z][a-zA-Z0-9]*)/.exec(tag);
            if (!m || /\/>$/.test(tag) || m[1].toLowerCase() === "br" || m[1].toLowerCase() === "img")
                break;
            stack.push({
                name: m[1].toLowerCase(),
                tag: tag
            });
            i = end + 1;
        }
        let left = inner.slice(0, i);
        let right = inner.slice(i);
        // Closing tags right at the split point belong to the left side.
        while (stack.length > 0 && right.indexOf("</" + stack[stack.length - 1].name + ">") === 0) {
            const name = stack.pop().name;
            left += "</" + name + ">";
            right = right.slice(name.length + 3);
        }
        left += stack.slice().reverse().map(t => "</" + t.name + ">").join("");
        right = stack.map(t => t.tag).join("") + right;
        // Inline tags with no text left in them are noise.
        const prune = s => {
            let prev;
            do {
                prev = s;
                s = s.replace(/<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*><\/\1>/g, "");
            } while (s !== prev);
            return s;
        };
        return {
            left: prune(left),
            right: prune(right)
        };
    }

    // ── operations ───────────────────────────────────────────────────────
    // Shift+Return in a list item: a new item after it, taking the text after
    // the cursor. On an empty item, leave the list instead (as Return does).
    // Returns {html, cursor} or null when the cursor is not in a list item.
    function newItem(html, raw, pos) {
        const doc = load(html, raw);
        if (!doc)
            return null;
        const starts = paragraphStarts(raw);
        const k = paragraphAt(starts, pos);
        const b = doc.blocks[k];
        if (b.kind !== "li")
            return null;
        if (b.inner === "") {
            if (b.depth > 1) {
                b.depth--;
            } else {
                doc.blocks[k] = {
                    kind: "p",
                    tag: "p",
                    style: b.style,
                    inner: ""
                };
            }
            return {
                html: serialize(doc),
                cursor: pos
            };
        }
        const parts = splitInner(b.inner, pos - starts[k]);
        b.inner = parts.left;
        doc.blocks.splice(k + 1, 0, Object.assign({}, b, {
            inner: parts.right
        }));
        return {
            html: serialize(doc),
            cursor: pos + 1
        };
    }

    // Toggle a bullet list over the paragraphs from `from` to `to`: if they are
    // all list items they become paragraphs, otherwise they all become items.
    function toggleList(html, raw, from, to) {
        const doc = load(html, raw);
        if (!doc)
            return null;
        const starts = paragraphStarts(raw);
        const a = paragraphAt(starts, Math.min(from, to));
        const b = paragraphAt(starts, Math.max(from, to));
        const range = doc.blocks.slice(a, b + 1).filter(x => x.kind !== "raw");
        if (range.length === 0)
            return null;
        const allItems = range.every(x => x.kind === "li");
        // Join the list just above, if any, rather than starting another.
        const above = a > 0 && doc.blocks[a - 1].kind === "li" ? doc.blocks[a - 1] : null;
        range.forEach(x => {
            if (allItems) {
                x.kind = "p";
                x.tag = "p";
            } else if (x.kind !== "li") {
                x.kind = "li";
                x.listTag = above ? above.listTag : "ul";
                x.listStyle = above ? above.listStyle : defaultListStyle;
                x.depth = above ? above.depth : 1;
            }
        });
        return serialize(doc);
    }

    // Paragraphs between `from` and `to` (a paste) that start with a typed
    // bullet ("- ", "• ", "1. "...) become list items, the bullet dropped;
    // leading indentation nests them. Returns {html, removed} or null when
    // there is nothing to convert. `removed` is the number of characters
    // dropped, all of them before `to`.
    function convertBullets(html, raw, from, to) {
        const starts = paragraphStarts(raw);
        const a = paragraphAt(starts, from);
        let b = paragraphAt(starts, to);
        // A paste ending in a newline leaves the cursor at the start of the
        // next, untouched paragraph.
        if (b > a && starts[b] === to)
            b--;
        const hits = [];
        for (let k = a; k <= b; k++) {
            const end = k + 1 < starts.length ? starts[k + 1] - 1 : raw.length;
            const m = bulletPattern.exec(raw.slice(starts[k], end));
            if (m)
                hits.push({
                    k: k,
                    length: m[0].length,
                    indent: m[1].replace(/\t/g, "    ").length,
                    ordered: /\d/.test(m[2])
                });
        }
        if (hits.length === 0)
            return null;
        const doc = load(html, raw);
        if (!doc)
            return null;

        let removed = 0;
        let prevDepth = 0;
        let prevK = -2;
        let baseIndent = 0;
        hits.forEach(h => {
            const block = doc.blocks[h.k];
            if (block.kind === "raw")
                return;
            // Indentation counts from the first item of a run, two spaces a
            // level, and nests at most one level deeper than the item above.
            if (h.k !== prevK + 1) {
                prevDepth = 0;
                baseIndent = h.indent;
            }
            const depth = Math.min(prevDepth + 1, 1 + Math.max(0, Math.floor((h.indent - baseIndent) / 2)));
            block.inner = splitInner(block.inner, h.length).right;
            block.kind = "li";
            block.tag = "p";
            block.listTag = h.ordered ? "ol" : "ul";
            block.listStyle = block.listStyle || defaultListStyle;
            block.depth = depth;
            removed += h.length;
            prevDepth = depth;
            prevK = h.k;
        });
        return {
            html: serialize(doc),
            removed: removed
        };
    }
}
