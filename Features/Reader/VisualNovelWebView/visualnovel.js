//
//  visualnovel.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

// VN mode shows one "screen" of the chapter at a time (a paragraph, a
// sentence, or a media item). The chapter content is moved once into an
// off-DOM `sourceRoot`, which is never changed again. Every screen is built
// by cloning nodes from it into a `stage`, the only thing attached under
// document.body. Switching screens calls stage.replaceChildren(), so nothing
// from an old screen can ever stay behind. A <ruby> is always cloned as one
// whole piece, so a screen boundary can never cut it in half.
window.hoshiReader = {
    ttuRegexNegated: /[^0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\p{Radical}\p{Unified_Ideograph}]+/gimu,
    ttuRegex: /[0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\p{Radical}\p{Unified_Ideograph}]/iu,
    nodeStartOffsets: new WeakMap(),
    nodeStartRawOffsets: new WeakMap(),
    activeCueId: null,
    cueWrappers: new Map(),
    
    sourceRoot: null,
    stage: null,
    leaves: [],
    screens: [],
    currentIndex: 0,
    totalScreens: 0,
    
    revealSpeed: 45,
    revealComplete: true,
    revealTimer: null,
    revealPairs: null,
    
    screenMode: 'Block',
    sentencesPerScreen: 1,
    preserveDialogueBubbles: false,
    mergeCrossScreenSasayakiCues: false,
    
    sasayakiCues: [],
    pendingHighlights: null,
    
    blockSelector: 'p, div, li, blockquote, h1, h2, h3, h4, h5, h6, pre, td, th, figure',
    sentenceEndRegex: /[。.!?！？…]/,
    closingPunctuation: '」』"”)）】〉》〕｝]、,',
    dialogueBrackets: { '「': '」', '『': '』' },
    
    // -- generic helpers shared with reader.js / selection.js / highlights.js --
    
    isVertical() {
        return window.getComputedStyle(document.body).writingMode === "vertical-rl";
    },
    
    isFurigana(node) {
        const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        return !!el?.closest('rt, rp');
    },
    
    countChars(text) {
        return Array.from(this.normalizeText(text)).length;
    },
    
    countRawChars(text) {
        return Array.from(text).length;
    },
    
    normalizeText(text) {
        return text.replace(this.ttuRegexNegated, '');
    },
    
    isMatchableChar(char) {
        return this.ttuRegex.test(char || '');
    },
    
    // This skips furigana everywhere, just like reader.js does. It also
    // skips text that has not been revealed yet (see startReveal()). Offset
    // counting, text selection, and highlight/cue wrapping all need to agree
    // that unrevealed text is not "there" yet.
    createWalker(rootNode) {
        const root = rootNode || document.body;
        return document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => {
                if (this.isFurigana(n)) return NodeFilter.FILTER_REJECT;
                if (n.parentElement && n.parentElement.closest('[data-hoshi-vn-unrevealed]')) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });
    },
    
    getRect(target) {
        const rect = target.getClientRects()[0];
        return rect || target.getBoundingClientRect();
    },
    
    // Only walks the stage (one screen), but starts counting from that screen's
    // startChar/startRaw so offsets stay GLOBAL. This keeps highlights correct
    // when moving between VN and Paginated/Continuous mode.
    buildNodeOffsets() {
        const offsets = new WeakMap();
        const rawOffsets = new WeakMap();
        const screen = this.screens[this.currentIndex];
        let count = screen ? screen.startChar : 0;
        let rawCount = screen ? screen.startRaw : 0;
        const walker = this.createWalker(this.stage);
        let node;
        
        while (node = walker.nextNode()) {
            offsets.set(node, count);
            rawOffsets.set(node, rawCount);
            count += this.countChars(node.textContent);
            rawCount += this.countRawChars(node.textContent);
        }
        
        this.nodeStartOffsets = offsets;
        this.nodeStartRawOffsets = rawOffsets;
    },
    
    unwrap(wrappers) {
        wrappers.forEach(wrapper => {
            const parent = wrapper.parentNode;
            if (!parent) {
                return;
            }
            while (wrapper.firstChild) {
                parent.insertBefore(wrapper.firstChild, wrapper);
            }
            parent.removeChild(wrapper);
            parent.normalize();
        });
    },
    
    registerCopyText() {
        if (window.copyTextRegistered) {
            return;
        }
        window.copyTextRegistered = true;
        document.addEventListener('copy', function (event) {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) {
                return;
            }
            const fragment = selection.getRangeAt(0).cloneContents();
            fragment.querySelectorAll('rt, rp').forEach(el => el.remove());
            const text = fragment.textContent;
            if (!text) {
                return;
            }
            event.preventDefault();
            event.clipboardData.setData('text/plain', text);
        }, true);
    },
    
    notifyRestoreComplete() {
        window.webkit?.messageHandlers?.restoreCompleted?.postMessage(null);
    },
    
    // Toggling a transform forces a real WebKit repaint (offsetHeight alone is
    // not enough). Needed because reveal's text-node changes can paint out of
    // order even when applied to the DOM in the right order. `element`
    // defaults to the stage; revealTick() also passes a highlight wrapper when
    // one sits between the stage and the pair, since it has its own paint
    // layer a stage-only repaint doesn't reach.
    forceRepaint(element) {
        const target = element || this.stage;
        target.style.transform = 'translateZ(0)';
        requestAnimationFrame(() => {
            target.style.transform = '';
        });
    },
    
    // -- detach + model --
    
    ensureSourceDetached() {
        if (this.sourceRoot) {
            return;
        }
        this.sourceRoot = document.createElement('div');
        while (document.body.firstChild) {
            this.sourceRoot.appendChild(document.body.firstChild);
        }
        this.stage = document.createElement('div');
        this.stage.className = 'hoshi-vn-stage';
        document.body.appendChild(this.stage);
    },
    
    isLeafBlock(el) {
        return !el.querySelector(this.blockSelector);
    },
    
    // Leaves are found from the untouched sourceRoot. figcaption is left out
    // of blockSelector on purpose, so a <figure><img><figcaption> group
    // stays as one leaf together with its image, instead of the caption
    // becoming its own separate leaf.
    collectLeaves() {
        const candidates = Array.from(this.sourceRoot.querySelectorAll(this.blockSelector));
        const leafBlocks = candidates.filter(el => this.isLeafBlock(el)).map(el => ({ element: el, kind: 'block' }));
        const standaloneMedia = Array.from(this.sourceRoot.querySelectorAll('img, svg'))
            .filter(el => !el.closest(this.blockSelector))
            .map(el => ({ element: el, kind: 'media' }));
        
        const all = leafBlocks.concat(standaloneMedia);
        all.sort((a, b) => {
            const position = a.element.compareDocumentPosition(b.element);
            if (position & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
            if (position & Node.DOCUMENT_POSITION_PRECEDING) return 1;
            return 0;
        });
        return all;
    },
    
    // Paginated mode counts every text node in the chapter, including loose
    // whitespace between paragraphs. Leaf-by-leaf counting skips that, so the
    // gaps would drift the two modes apart over many paragraphs. This walks
    // sourceRoot once like Paginated mode does, to find each leaf's true
    // starting offset instead of adding up counts from earlier screens.
    computeLeafStartOffsets() {
        const startChar = new Array(this.leaves.length).fill(0);
        const startRaw = new Array(this.leaves.length).fill(0);
        let leafPointer = 0;
        let runningChar = 0;
        let runningRaw = 0;
        const walker = this.createWalker(this.sourceRoot);
        let node;
        while (node = walker.nextNode()) {
            while (leafPointer < this.leaves.length) {
                const leafEl = this.leaves[leafPointer].element;
                if (leafEl.contains(node)) {
                    startChar[leafPointer] = runningChar;
                    startRaw[leafPointer] = runningRaw;
                    leafPointer++;
                    break;
                }
                const position = leafEl.compareDocumentPosition(node);
                if (position & Node.DOCUMENT_POSITION_FOLLOWING) {
                    // This leaf (for example a media-only or empty leaf) has
                    // no text nodes of its own. It sits fully before this
                    // node, so it "starts" at whatever offset we are at now.
                    startChar[leafPointer] = runningChar;
                    startRaw[leafPointer] = runningRaw;
                    leafPointer++;
                } else {
                    break;
                }
            }
            runningChar += this.countChars(node.textContent);
            runningRaw += this.countRawChars(node.textContent);
        }
        while (leafPointer < this.leaves.length) {
            startChar[leafPointer] = runningChar;
            startRaw[leafPointer] = runningRaw;
            leafPointer++;
        }
        return { startChar, startRaw };
    },
    
    // Gives each segment its true starting offset: the leaf's true start (from
    // computeLeafStartOffsets) plus the char/rawCount of the segments before it
    // in the same leaf. Segments in one leaf always sit next to each other, so
    // simple addition is safe here (unlike adding up across leaves, which
    // misses the gaps between them).
    tagSegmentsWithTrueOffsets(segments, leafIndex) {
        let withinLeafChar = 0;
        let withinLeafRaw = 0;
        segments.forEach(seg => {
            seg.leafIndex = leafIndex;
            seg.trueStartChar = (this.leafStartChar[leafIndex] || 0) + withinLeafChar;
            seg.trueStartRaw = (this.leafStartRaw[leafIndex] || 0) + withinLeafRaw;
            withinLeafChar += seg.charCount;
            withinLeafRaw += seg.rawCount;
        });
    },
    
    // Returns this leaf's sentence-level segments as {startNode, startOffset,
    // endNode, endOffset, charCount, rawCount, text}, in document order, with
    // preserveDialogueBubbles merging applied. Pure index/string-slice math,
    // no Range API, no DOM changes.
    //
    // Ruby elements can never be split: the punctuation scan below skips any
    // node that is a ruby's base text, so a boundary can never land there.
    getLeafSentenceSegments(leaf) {
        const walker = this.createWalker(leaf);
        const textNodes = [];
        let node;
        while (node = walker.nextNode()) {
            if (node.textContent.length) textNodes.push(node);
        }
        if (!textNodes.length) {
            return [];
        }
        
        const isRubyBase = (n) => !!(n.parentElement && n.parentElement.closest('ruby'));
        
        const boundaries = [];
        textNodes.forEach(tn => {
            if (isRubyBase(tn)) {
                return;
            }
            const text = tn.textContent;
            for (let i = 0; i < text.length; i++) {
                const ch = text[i];
                if (!this.sentenceEndRegex.test(ch)) {
                    continue;
                }
                if (ch === '.' && /[0-9]/.test(text[i - 1] || '') && /[0-9]/.test(text[i + 1] || '')) {
                    continue;
                }
                let j = i + 1;
                while (j < text.length && (this.closingPunctuation.indexOf(text[j]) !== -1 || this.sentenceEndRegex.test(text[j]))) j++;
                boundaries.push({ node: tn, offset: j });
                i = j - 1;
            }
        });
        const lastNode = textNodes[textNodes.length - 1];
        const last = boundaries[boundaries.length - 1];
        if (!last || last.node !== lastNode || last.offset < lastNode.textContent.length) {
            boundaries.push({ node: lastNode, offset: lastNode.textContent.length });
        }
        
        let segStartNode = textNodes[0];
        let segStartOffset = 0;
        let segments = boundaries.map(b => {
            const segment = { startNode: segStartNode, startOffset: segStartOffset, endNode: b.node, endOffset: b.offset };
            segStartNode = b.node;
            segStartOffset = b.offset;
            return segment;
        }).filter(s => s.startNode !== s.endNode || s.startOffset < s.endOffset);
        
        if (!segments.length) {
            return [];
        }
        
        segments.forEach(seg => {
            let count = 0, raw = 0, text = '';
            let started = false;
            for (const tn of textNodes) {
                if (tn === seg.startNode) started = true;
                if (!started) continue;
                const full = tn.textContent;
                const start = (tn === seg.startNode) ? seg.startOffset : 0;
                const end = (tn === seg.endNode) ? seg.endOffset : full.length;
                const slice = full.slice(start, end);
                text += slice;
                count += this.countChars(slice);
                raw += this.countRawChars(slice);
                if (tn === seg.endNode) break;
            }
            seg.charCount = count;
            seg.rawCount = raw;
            seg.text = text;
        });
        
        if (this.preserveDialogueBubbles) {
            const merged = [];
            let stackDepth = 0;
            segments.forEach(segment => {
                for (const ch of segment.text) {
                    if (this.dialogueBrackets[ch]) stackDepth++;
                    else if (Object.values(this.dialogueBrackets).includes(ch)) stackDepth = Math.max(0, stackDepth - 1);
                }
                if (merged.length && merged[merged.length - 1].openBrackets > 0) {
                    const prev = merged[merged.length - 1];
                    prev.endNode = segment.endNode;
                    prev.endOffset = segment.endOffset;
                    prev.charCount += segment.charCount;
                    prev.rawCount += segment.rawCount;
                    prev.text += segment.text;
                    prev.openBrackets = stackDepth;
                } else {
                    merged.push({ ...segment, openBrackets: stackDepth });
                }
            });
            segments = merged;
        }
        
        return segments;
    },
    
    // -- screen building --
    
    // Renders a candidate group into the stage briefly to check if it
    // overflows, like Android's measureScreenFits()/fitScreensToViewport()
    // does, instead of guessing from a character count. Safe to use the
    // stage here because this only runs during buildScreens(), before any
    // real screen is shown, and the stage is cleared right after measuring.
    measureGroupOverflows(group) {
        this.stage.replaceChildren();
        
        const cloneCache = new WeakMap();
        const ensureClone = (sourceEl) => {
            if (sourceEl === this.sourceRoot) {
                return this.stage;
            }
            if (cloneCache.has(sourceEl)) {
                return cloneCache.get(sourceEl);
            }
            const clone = sourceEl.cloneNode(false);
            const parentClone = ensureClone(sourceEl.parentElement);
            parentClone.appendChild(clone);
            cloneCache.set(sourceEl, clone);
            return clone;
        };
        
        group.forEach(unit => {
            (unit.mediaElements || []).forEach(mediaEl => {
                const parentClone = ensureClone(mediaEl.parentElement);
                parentClone.appendChild(mediaEl.cloneNode(true));
            });
        });
        
        const clonedRubyRoots = new Set();
        group.forEach(unit => {
            const segment = unit.segment;
            const leaf = this.leaves[segment.leafIndex];
            const walker = this.createWalker(leaf.element);
            let node;
            let started = false;
            while (node = walker.nextNode()) {
                if (node === segment.startNode) started = true;
                if (!started) continue;
                
                const rubyRoot = node.parentElement && node.parentElement.closest('ruby');
                if (rubyRoot) {
                    if (!clonedRubyRoots.has(rubyRoot)) {
                        clonedRubyRoots.add(rubyRoot);
                        const parentClone = ensureClone(rubyRoot.parentElement);
                        parentClone.appendChild(rubyRoot.cloneNode(true));
                    }
                } else {
                    const full = node.textContent;
                    const start = (node === segment.startNode) ? segment.startOffset : 0;
                    const end = (node === segment.endNode) ? segment.endOffset : full.length;
                    const slice = full.slice(start, end);
                    if (slice.length) {
                        const parentClone = ensureClone(node.parentElement);
                        parentClone.appendChild(document.createTextNode(slice));
                    }
                }
                
                if (node === segment.endNode) break;
            }
        });
        
        // This checks document.body, not this.stage. body is the real
        // scroll container (see its overflow-x/overflow-y:auto CSS
        // comment). body is what the user actually scrolls, and it is not a
        // flex item itself.
        const overflow = this.isVertical()
            ? document.body.scrollWidth > document.body.clientWidth + 1
            : document.body.scrollHeight > document.body.clientHeight + 1;
        
        this.stage.replaceChildren();
        return overflow;
    },
    
    // -- last-resort splitting for an oversized single segment --
    // Native scrolling is off (VisualNovelWebView.swift sets
    // isScrollEnabled = false), so a segment (a whole sentence, or a whole
    // Keep Dialogue Together block) that overflows a screen on its own would
    // leave part of it unreachable. This only runs after normal
    // group-shrinking has already brought a group down to one segment that
    // still overflows alone. Matches Android's splitScreenToViewport, which
    // also binary-searches smaller "viewport split units". The cut is made
    // character by character, never inside a ruby, since a permanently
    // unreachable screen is worse than briefly breaking the sentence rule.
    
    // Lists every valid spot inside a segment where a finer cut could end:
    // right after any single plain-text character, or right after a whole
    // ruby element. It never cuts inside a ruby, the same rule used
    // everywhere else.
    buildCutPoints(segment) {
        const leaf = this.leaves[segment.leafIndex];
        const walker = this.createWalker(leaf.element);
        const cutPoints = [];
        let node;
        let started = false;
        let inRubyLastNode = null;
        while (node = walker.nextNode()) {
            if (node === segment.startNode) started = true;
            if (!started) continue;
            
            const rubyRoot = node.parentElement && node.parentElement.closest('ruby');
            if (rubyRoot) {
                inRubyLastNode = node;
                if (node === segment.endNode) {
                    cutPoints.push({ node, offset: node.textContent.length });
                }
            } else {
                if (inRubyLastNode) {
                    cutPoints.push({ node: inRubyLastNode, offset: inRubyLastNode.textContent.length });
                    inRubyLastNode = null;
                }
                const full = node.textContent;
                const start = (node === segment.startNode) ? segment.startOffset : 0;
                const end = (node === segment.endNode) ? segment.endOffset : full.length;
                for (let i = start + 1; i <= end; i++) {
                    cutPoints.push({ node, offset: i });
                }
            }
            
            if (node === segment.endNode) break;
        }
        return cutPoints;
    },
    
    // Works out charCount/rawCount/text again for the smaller range from
    // [startNode,startOffset) up to cutPoint. We cannot just split the
    // original segment's counts by a simple ratio, because matchable-char
    // filtering is not the same across every part of the text.
    buildSubSegment(originalSegment, startNode, startOffset, cutPoint) {
        const leaf = this.leaves[originalSegment.leafIndex];
        const walker = this.createWalker(leaf.element);
        let node;
        let started = false;
        let count = 0, raw = 0, text = '';
        while (node = walker.nextNode()) {
            if (node === startNode) started = true;
            if (!started) continue;
            const full = node.textContent;
            const s = (node === startNode) ? startOffset : 0;
            const e = (node === cutPoint.node) ? cutPoint.offset : full.length;
            const slice = full.slice(s, e);
            text += slice;
            count += this.countChars(slice);
            raw += this.countRawChars(slice);
            if (node === cutPoint.node) break;
        }
        return {
            startNode, startOffset, endNode: cutPoint.node, endOffset: cutPoint.offset,
            charCount: count, rawCount: raw, text, leafIndex: originalSegment.leafIndex
        };
    },
    
    // Does a binary search over buildCutPoints() to find the longest start
    // piece that still fits on one screen. It repeats this for what is
    // left, so the returned sub-segments together still cover the whole
    // original segment, start to end.
    splitOversizedSegment(segment) {
        const cutPoints = this.buildCutPoints(segment);
        if (!cutPoints.length) {
            return [segment];
        }
        const results = [];
        let startNode = segment.startNode;
        let startOffset = segment.startOffset;
        let cutIndex = 0;
        // Carries the true (whole-document-accurate) offsets through the
        // split, the same way tagSegmentsWithTrueOffsets does for normal
        // segments. Without this, a screen whose first segment came from a
        // last-resort split would fall back to the less accurate running
        // total in buildScreens().
        let trueChar = segment.trueStartChar || 0;
        let trueRaw = segment.trueStartRaw || 0;
        while (cutIndex < cutPoints.length) {
            let low = cutIndex;
            let high = cutPoints.length - 1;
            let best = cutIndex;
            while (low <= high) {
                const mid = Math.floor((low + high) / 2);
                const candidate = this.buildSubSegment(segment, startNode, startOffset, cutPoints[mid]);
                if (mid === cutIndex || !this.measureGroupOverflows([{ segment: candidate, mediaElements: [] }])) {
                    best = mid;
                    low = mid + 1;
                } else {
                    high = mid - 1;
                }
            }
            const chosen = this.buildSubSegment(segment, startNode, startOffset, cutPoints[best]);
            chosen.trueStartChar = trueChar;
            chosen.trueStartRaw = trueRaw;
            trueChar += chosen.charCount;
            trueRaw += chosen.rawCount;
            results.push(chosen);
            startNode = cutPoints[best].node;
            startOffset = cutPoints[best].offset;
            cutIndex = best + 1;
        }
        return results;
    },
    
    // Used by both buildBlockScreens() and buildSentenceScreens(). Takes up
    // to maxCount units from the front of `remaining`, shrinking the group
    // down to whatever actually fits (see measureGroupOverflows), and adds
    // one screen for it to `screens`. Falls back to splitOversizedSegment()
    // when even a single unit does not fit on its own. See that function's
    // comment for why. This changes both `remaining` and `screens`.
    consumeFittingGroup(remaining, screens, maxCount) {
        let count = Math.min(maxCount, remaining.length);
        let group = remaining.slice(0, count);
        while (count > 1 && this.measureGroupOverflows(group)) {
            count--;
            group = remaining.slice(0, count);
        }
        remaining.splice(0, count);
        
        if (count === 1 && this.measureGroupOverflows(group)) {
            const unit = group[0];
            this.splitOversizedSegment(unit.segment).forEach((sub, i) => {
                screens.push({
                    kind: 'text',
                    segments: [sub],
                    mediaElements: i === 0 ? (unit.mediaElements || []) : []
                });
            });
        } else {
            screens.push({
                kind: 'text',
                segments: group.map(u => u.segment),
                mediaElements: group.reduce((acc, u) => acc.concat(u.mediaElements || []), [])
            });
        }
    },
    
    // Block mode keeps each screen tied to one paragraph. Every leaf makes
    // its own screen or screens, only split when too long to fit. Not
    // affected by the cross-paragraph merging Sentences mode does below.
    buildBlockScreens() {
        const screens = [];
        this.leaves.forEach((leaf, leafIndex) => {
            if (leaf.kind === 'media') {
                screens.push({ kind: 'media', leafIndex, mediaElements: [leaf.element] });
                return;
            }
            
            // A leaf with an embedded image and no text (a cover page like
            // <div><svg><image/></svg></div>) has no text nodes, so
            // getLeafSentenceSegments finds nothing. Route it through the
            // media path instead of leaving a blank screen to swipe past.
            const embeddedMedia = Array.from(leaf.element.querySelectorAll('img, svg'));
            const segments = this.getLeafSentenceSegments(leaf.element);
            this.tagSegmentsWithTrueOffsets(segments, leafIndex);
            // A leaf can have only whitespace text nodes between its tags,
            // so segments is non-empty but has zero MATCHABLE characters.
            // Check charCount, not just segment count, or such a leaf goes
            // through the text path's wrapper clone instead of the media
            // path, and its image renders tiny since the wrapper has no
            // size of its own.
            const hasRealText = segments.some(s => s.charCount > 0);
            if (!hasRealText) {
                if (embeddedMedia.length) {
                    screens.push({ kind: 'media', leafIndex, mediaElements: embeddedMedia });
                }
                return;
            }
            
            // Splits this leaf's segments with the same real-measurement
            // check as Sentences mode (measureGroupOverflows), not a
            // character-count guess. A guess could under-split at a larger
            // font size, since the same character count needs more space
            // per character the bigger the font gets.
            let remaining = segments.map((seg, i) => ({ segment: seg, mediaElements: i === 0 ? embeddedMedia : [] }));
            while (remaining.length) {
                this.consumeFittingGroup(remaining, screens, remaining.length);
            }
        });
        return screens;
    },
    
    // Sentences mode groups sentences into screens across the WHOLE chapter,
    // not just inside one paragraph.
    // A flat list of "units" is built in document order: one unit per
    // sentence segment, and one standalone unit per media/illustration leaf.
    // Units are grouped up to sentencesPerScreen at a time, flushed when the
    // target count is reached, the group stops fitting on screen, or a
    // standalone unit comes up next. So a paragraph with fewer sentences than
    // the target pulls sentences from the NEXT paragraph, instead of being
    // shown alone as an unfinished group.
    buildSentenceScreens() {
        const units = [];
        this.leaves.forEach((leaf, leafIndex) => {
            if (leaf.kind === 'media') {
                units.push({ standalone: true, leafIndex, mediaElements: [leaf.element] });
                return;
            }
            
            const embeddedMedia = Array.from(leaf.element.querySelectorAll('img, svg'));
            const segments = this.getLeafSentenceSegments(leaf.element);
            this.tagSegmentsWithTrueOffsets(segments, leafIndex);
            const hasRealText = segments.some(s => s.charCount > 0);
            if (!hasRealText) {
                if (embeddedMedia.length) {
                    units.push({ standalone: true, leafIndex, mediaElements: embeddedMedia });
                }
                return;
            }
            
            segments.forEach((segment, i) => {
                units.push({ standalone: false, segment, mediaElements: i === 0 ? embeddedMedia : [] });
            });
        });
        
        const groupSize = Math.max(1, this.sentencesPerScreen);
        const screens = [];
        let pending = [];
        
        // Matches Android's fitScreensToViewport()/measureScreenFits(): render
        // the candidate group and shrink it until it actually fits, moving
        // the removed sentence(s) to the next screen. Better than trusting
        // sentencesPerScreen blindly (can overflow) or a character-count
        // guess (gives fewer sentences than asked when they run long). See
        // consumeFittingGroup() for the fallback when even one sentence does
        // not fit alone.
        const flush = () => {
            while (pending.length) {
                this.consumeFittingGroup(pending, screens, groupSize);
            }
        };
        
        units.forEach(unit => {
            if (unit.standalone) {
                flush();
                screens.push({ kind: 'media', leafIndex: unit.leafIndex, mediaElements: unit.mediaElements });
                return;
            }
            pending.push(unit);
            if (pending.length >= groupSize) {
                flush();
            }
        });
        flush();
        
        return screens;
    },
    
    buildScreens(settings) {
        if (settings) {
            this.revealSpeed = Number.isFinite(settings.revealSpeed) ? settings.revealSpeed : this.revealSpeed;
            this.screenMode = settings.screenMode || 'Block';
            this.sentencesPerScreen = Math.max(1, settings.sentencesPerScreen || 1);
            this.preserveDialogueBubbles = !!settings.preserveDialogueBubbles;
            this.mergeCrossScreenSasayakiCues = !!settings.mergeCrossScreenSasayakiCues;
        }
        
        this.ensureSourceDetached();
        this.leaves = this.collectLeaves();
        const leafStartOffsets = this.computeLeafStartOffsets();
        this.leafStartChar = leafStartOffsets.startChar;
        this.leafStartRaw = leafStartOffsets.startRaw;
        
        const screens = this.screenMode === 'Sentences' ? this.buildSentenceScreens() : this.buildBlockScreens();
        
        // Text screens get their startChar/startRaw straight from the first
        // segment's true offset (see computeLeafStartOffsets()). Media
        // screens have no segments, so they just take over the position
        // where the previous text screen ended.
        let runningChar = 0;
        let runningRaw = 0;
        screens.forEach(screen => {
            if (screen.kind === 'text' && screen.segments.length && screen.segments[0].trueStartChar !== undefined) {
                screen.startChar = screen.segments[0].trueStartChar;
                screen.startRaw = screen.segments[0].trueStartRaw;
                const chars = screen.segments.reduce((s, seg) => s + seg.charCount, 0);
                const raws = screen.segments.reduce((s, seg) => s + seg.rawCount, 0);
                screen.endChar = screen.startChar + chars;
                screen.endRaw = screen.startRaw + raws;
            } else {
                screen.startChar = runningChar;
                screen.startRaw = runningRaw;
                screen.endChar = runningChar;
                screen.endRaw = runningRaw;
            }
            runningChar = screen.endChar;
            runningRaw = screen.endRaw;
        });
        
        this.screens = screens;
        this.totalScreens = screens.length;
        if (this.currentIndex >= this.totalScreens) {
            this.currentIndex = Math.max(0, this.totalScreens - 1);
        }
        // The first render happens later, inside restoreProgress() or
        // jumpToFragment() (both go through showScreen()). Swift calls one
        // of those right after this.
    },
    
    // -- render --
    
    renderScreen(index) {
        this.cancelReveal();
        this.stage.replaceChildren();
        
        const screen = this.screens[index];
        if (!screen) {
            this.buildNodeOffsets();
            return;
        }
        
        // Shallow-clones a source element's ancestor chain up to sourceRoot,
        // only when needed, caching the result so a paragraph wrapper is
        // only cloned once even with several children going back into it.
        // Rebuilt fresh every render, so it never points at a stale clone
        // from a previous screen.
        const cloneCache = new WeakMap();
        const ensureClone = (sourceEl) => {
            if (sourceEl === this.sourceRoot) {
                return this.stage;
            }
            if (cloneCache.has(sourceEl)) {
                return cloneCache.get(sourceEl);
            }
            const clone = sourceEl.cloneNode(false);
            const parentClone = ensureClone(sourceEl.parentElement);
            parentClone.appendChild(clone);
            cloneCache.set(sourceEl, clone);
            return clone;
        };
        
        if (screen.kind === 'media') {
            // .hoshi-vn-media-screen (CSS) centers the stage, which fits the
            // image via max-width/max-height like Paginated mode does. The
            // image goes straight into the stage, not through ensureClone's
            // wrapper chain, since a wrapper div has no fixed size of its
            // own for the image to size against.
            this.stage.classList.add('hoshi-vn-media-screen');
            const leaf = this.leaves[screen.leafIndex];
            const mediaElements = screen.mediaElements || [leaf.element];
            mediaElements.forEach(mediaEl => {
                this.stage.appendChild(mediaEl.cloneNode(true));
            });
            this.buildNodeOffsets();
            this.reapplyPendingHighlights();
            return;
        }
        this.stage.classList.remove('hoshi-vn-media-screen');
        
        document.body.style.justifyContent = '';
        const clonedRubyRoots = new Set();
        
        (screen.mediaElements || []).forEach(mediaEl => {
            const parentClone = ensureClone(mediaEl.parentElement);
            parentClone.appendChild(mediaEl.cloneNode(true));
        });
        
        // Sentences mode can put segments from DIFFERENT leaves on one
        // screen, so each segment resolves its own leaf via its leafIndex,
        // instead of assuming one shared leaf for the whole screen.
        screen.segments.forEach(segment => {
            const leaf = this.leaves[segment.leafIndex];
            const walker = this.createWalker(leaf.element);
            let node;
            let started = false;
            while (node = walker.nextNode()) {
                if (node === segment.startNode) started = true;
                if (!started) continue;
                
                const rubyRoot = node.parentElement && node.parentElement.closest('ruby');
                if (rubyRoot) {
                    // Ruby is cloned as one whole piece, base and reading
                    // together, so a boundary can never split them.
                    if (!clonedRubyRoots.has(rubyRoot)) {
                        clonedRubyRoots.add(rubyRoot);
                        const parentClone = ensureClone(rubyRoot.parentElement);
                        parentClone.appendChild(rubyRoot.cloneNode(true));
                    }
                } else {
                    const full = node.textContent;
                    const start = (node === segment.startNode) ? segment.startOffset : 0;
                    const end = (node === segment.endNode) ? segment.endOffset : full.length;
                    const slice = full.slice(start, end);
                    if (slice.length) {
                        const parentClone = ensureClone(node.parentElement);
                        parentClone.appendChild(document.createTextNode(slice));
                    }
                }
                
                if (node === segment.endNode) break;
            }
        });
        
        // Highlights are not put back on here on purpose. A .hoshi-highlight
        // wrapper around text about to reveal shows that text fully from
        // the start, no matter what paint fixes exist. Adding highlights
        // only after reveal finishes (see startReveal()'s early returns and
        // completeReveal()) avoids this: the wrapper just does not exist
        // yet while its text is still revealing.
        this.buildNodeOffsets();
    },
    
    // highlights.js's applyHighlights() only finds highlights whose offset
    // falls inside whatever can currently be walked, meaning this screen. A
    // fresh render replaces all of the stage's content. So highlights need
    // to be added back after every render, not just once when the chapter
    // loads.
    reapplyPendingHighlights() {
        if (this.pendingHighlights && this.pendingHighlights.length && window.hoshiHighlights) {
            window.hoshiHighlights.applyHighlights(this.pendingHighlights);
        }
    },
    
    registerHighlight(highlight) {
        this.pendingHighlights = this.pendingHighlights || [];
        this.pendingHighlights.push(highlight);
    },
    
    unregisterHighlight(id) {
        if (!this.pendingHighlights) {
            return;
        }
        this.pendingHighlights = this.pendingHighlights.filter(h => h.id !== id);
    },
    
    showScreen(index) {
        if (!this.totalScreens) {
            return;
        }
        this.currentIndex = Math.max(0, Math.min(index, this.totalScreens - 1));
        this.renderScreen(this.currentIndex);
        this.startReveal();
    },
    
    screenIndexForElement(el) {
        let leafIndex = -1;
        for (let i = 0; i < this.leaves.length; i++) {
            if (this.leaves[i].element === el || this.leaves[i].element.contains(el)) {
                leafIndex = i;
                break;
            }
        }
        if (leafIndex === -1) {
            return null;
        }
        // A text screen can hold segments from multiple leaves (Sentences
        // mode groups across paragraphs), so this checks if ANY segment
        // came from this leaf, instead of matching one leafIndex per screen.
        const screenIndices = [];
        this.screens.forEach((s, idx) => {
            if (s.kind === 'media') {
                if (s.leafIndex === leafIndex) screenIndices.push(idx);
            } else if (s.segments.some(seg => seg.leafIndex === leafIndex)) {
                screenIndices.push(idx);
            }
        });
        if (!screenIndices.length) {
            return null;
        }
        if (screenIndices.length === 1) {
            return screenIndices[0];
        }
        let best = screenIndices[0];
        for (const idx of screenIndices) {
            const screen = this.screens[idx];
            const segment = screen.kind === 'media' ? null : screen.segments.find(seg => seg.leafIndex === leafIndex);
            if (!segment) continue;
            const position = segment.startNode.compareDocumentPosition(el);
            const startsAtOrBeforeEl = !(position & Node.DOCUMENT_POSITION_FOLLOWING) || segment.startNode === el || segment.startNode.contains(el);
            if (startsAtOrBeforeEl) best = idx; else break;
        }
        return best;
    },
    
    sourceOffsetToScreenIndex(charOffset) {
        for (let i = 0; i < this.screens.length; i++) {
            const s = this.screens[i];
            if (charOffset >= s.startChar && charOffset < s.endChar) {
                return i;
            }
        }
        return this.screens.length ? this.screens.length - 1 : null;
    },
    
    paginate(direction) {
        if (!this.totalScreens) {
            return "limit";
        }
        if (direction === "forward") {
            if (this.currentIndex < this.totalScreens - 1) {
                this.showScreen(this.currentIndex + 1);
                return "scrolled";
            }
            return "limit";
        } else {
            if (this.currentIndex > 0) {
                this.showScreen(this.currentIndex - 1);
                return "scrolled";
            }
            return "limit";
        }
    },
    
    // Progress is a fraction of chapter CHARACTER position, like reader.js's
    // Paginated calculateProgress(), not a screen-index fraction. A
    // screen-index fraction breaks whenever the chapter gets re-split into a
    // different number of screens (switching Block/Sentences mode, changing
    // sentencesPerScreen), since currentIndex/totalScreens from the old
    // split means something else against the new one. Character position
    // survives a re-split since it describes WHERE in the text you are.
    calculateProgress() {
        const totalChars = this.screens.length ? this.screens[this.screens.length - 1].endChar : 0;
        if (!totalChars) {
            return 0;
        }
        const screen = this.screens[this.currentIndex];
        return screen ? screen.startChar / totalChars : 0;
    },
    
    async restoreProgress(progress) {
        await document.fonts.ready;
        
        if (!this.totalScreens) {
            this.notifyRestoreComplete();
            return;
        }
        
        const totalChars = this.screens[this.screens.length - 1].endChar;
        const targetChar = progress * totalChars;
        const index = this.sourceOffsetToScreenIndex(targetChar) ?? 0;
        this.showScreen(index);
        
        requestAnimationFrame(() => this.notifyRestoreComplete());
    },
    
    async jumpToFragment(fragment) {
        await document.fonts.ready;
        
        const rawFragment = (fragment || '').trim();
        let target = null;
        if (rawFragment && this.sourceRoot) {
            try {
                target = this.sourceRoot.querySelector('#' + CSS.escape(rawFragment));
            } catch (e) {
                target = null;
            }
            if (!target) {
                const named = Array.from(this.sourceRoot.querySelectorAll('[name]'));
                target = named.find(n => n.getAttribute('name') === rawFragment) || null;
            }
        }
        
        if (!target) {
            this.notifyRestoreComplete();
            return false;
        }
        
        const index = this.screenIndexForElement(target) ?? 0;
        this.showScreen(index);
        
        requestAnimationFrame(() => this.notifyRestoreComplete());
        return true;
    },
    
    // -- typewriter reveal --
    // Each stage text
    // node becomes an empty visible node plus a hidden span holding the
    // full text, one character moving over every delay_ms =
    // max(1, 1000/revealSpeed). Furigana is never ticked per character
    // (that used to desync kanji and reading). Instead each ruby's <rt> is
    // hidden with CSS visibility when its word's pair is made, and shown
    // the instant that pair finishes, revealed as one piece with its word.
    startReveal() {
        const speed = Number(this.revealSpeed);
        if (!Number.isFinite(speed) || speed <= 0) {
            // Instant speed skips the reveal, but still needs the repaint:
            // otherwise the same WebKit paint-ordering bug revealTick()/
            // completeReveal() work around elsewhere shows up here too, and
            // the old screen's last frame overlaps the new one.
            this.revealComplete = true;
            this.forceRepaint();
            this.reapplyPendingHighlights();
            return;
        }
        
        const textNodes = [];
        const walker = this.createWalker(this.stage);
        let node;
        while (node = walker.nextNode()) {
            if (node.textContent.length) textNodes.push(node);
        }
        if (!textNodes.length) {
            this.revealComplete = true;
            this.forceRepaint();
            this.reapplyPendingHighlights();
            return;
        }
        
        // Uses visibility:hidden, not display:none, so the hidden part still
        // takes up its layout space. Otherwise the paragraph would shrink
        // and shift as more of it reveals.
        const rubyLocalIndex = new Map();
        const pairs = textNodes.map(node => {
            const parent = node.parentNode;
            const text = node.textContent;
            const visible = document.createTextNode('');
            const hidden = document.createElement('span');
            hidden.setAttribute('data-hoshi-vn-unrevealed', '');
            hidden.setAttribute('aria-hidden', 'true');
            hidden.style.visibility = 'hidden';
            hidden.appendChild(document.createTextNode(text));
            parent.insertBefore(visible, node);
            parent.insertBefore(hidden, node);
            parent.removeChild(node);
            
            const pair = { visible, hidden, hiddenText: hidden.firstChild, chars: Array.from(text), revealed: 0, rt: null };
            
            // rubyRoot.querySelector('rt') always finds only the FIRST
            // reading, which is wrong for a <ruby>base1<rt/>base2<rt/></ruby>
            // (real books do have this). The local index picks the right rt.
            const rubyRoot = parent.closest && parent.closest('ruby');
            if (rubyRoot) {
                const localIndex = rubyLocalIndex.get(rubyRoot) || 0;
                rubyLocalIndex.set(rubyRoot, localIndex + 1);
                const rt = rubyRoot.querySelectorAll('rt')[localIndex];
                if (rt) {
                    rt.style.visibility = 'hidden';
                    pair.rt = rt;
                }
            }
            
            return pair;
        });
        
        this.revealComplete = false;
        this.revealPairs = pairs;
        
        // Reveals the first character right away instead of waiting one full
        // tick first. At a slow speed that wait left a freshly opened screen
        // looking blank for a second, like it was broken. Every later tick
        // is scheduled by revealTick() itself through scheduleRevealTick().
        this.revealTick(speed);
    },
    
    scheduleRevealTick(speed) {
        const delay = Math.max(1, 1000 / speed);
        this.revealTimer = setTimeout(() => this.revealTick(speed), delay);
    },
    
    revealTick(speed) {
        this.revealTimer = null;
        if (this.revealComplete || !this.revealPairs) {
            return;
        }
        for (let pairIndex = 0; pairIndex < this.revealPairs.length; pairIndex++) {
            const pair = this.revealPairs[pairIndex];
            if (pair.revealed >= pair.chars.length) continue;
            pair.revealed++;
            // Replaces the whole visible text node instead of changing
            // .textContent in place, since an empty node set later does
            // not always repaint reliably in this column layout.
            const newVisible = document.createTextNode(pair.chars.slice(0, pair.revealed).join(''));
            const revealParent = pair.visible.parentNode;
            revealParent.replaceChild(newVisible, pair.visible);
            pair.visible = newVisible;
            pair.hiddenText.textContent = pair.chars.slice(pair.revealed).join('');
            if (pair.revealed >= pair.chars.length && pair.rt) {
                pair.rt.style.visibility = '';
            }
            // WebKit paint-ordering issue, not a layout one, so offsetHeight
            // alone is not enough. Same fix highlights.js uses for the same
            // kind of bug.
            this.forceRepaint();
            // A .hoshi-highlight wrapper has its own paint layer that the
            // stage-level repaint above does not reach, so repaint it too.
            const highlightAncestor = revealParent.closest && revealParent.closest('.hoshi-highlight');
            if (highlightAncestor) {
                this.forceRepaint(highlightAncestor);
            }
            break;
        }
        const done = this.revealPairs.every(p => p.revealed >= p.chars.length);
        if (done) {
            this.completeReveal();
        } else {
            this.scheduleRevealTick(speed);
        }
    },
    
    // Only stops the timer here. No other cleanup is needed, since a reveal
    // only ever exists on the current stage. The caller (renderScreen,
    // through showScreen) is about to wipe that stage with
    // replaceChildren() anyway.
    cancelReveal() {
        if (this.revealTimer !== null) {
            clearTimeout(this.revealTimer);
            this.revealTimer = null;
        }
        this.revealPairs = null;
        this.revealComplete = true;
    },
    
    completeReveal() {
        if (this.revealTimer !== null) {
            clearTimeout(this.revealTimer);
            this.revealTimer = null;
        }
        if (this.revealPairs) {
            this.revealPairs.forEach(pair => {
                const newVisible = document.createTextNode(pair.chars.join(''));
                if (pair.visible.parentNode) pair.visible.parentNode.replaceChild(newVisible, pair.visible);
                pair.visible = newVisible;
                if (pair.hidden.parentNode) pair.hidden.parentNode.removeChild(pair.hidden);
                if (pair.rt) pair.rt.style.visibility = '';
            });
        }
        this.revealPairs = null;
        this.revealComplete = true;
        
        // Forces a full layout reset, so the column-wrap result is the same
        // whether reveal finished by ticking to the end or by an instant
        // tap-to-skip. Multi-column layout can otherwise settle on a
        // different column break depending on how content grew into place.
        const previousDisplay = this.stage.style.display;
        this.stage.style.display = 'none';
        void this.stage.offsetHeight;
        this.stage.style.display = previousDisplay;
        
        // Also forces a real repaint, not just a layout pass, for the same
        // paint-ordering reason forceRepaint() is used in revealTick().
        // Finishing several pairs in one loop can otherwise leave some of
        // them not visually painted for a moment, even though their DOM
        // content is correct.
        this.forceRepaint();
        
        this.buildNodeOffsets();
        this.reapplyPendingHighlights();
    },
    
    // Called from a tap, before a dictionary lookup. It uses up the tap to
    // finish an active reveal right away, instead of doing a lookup or
    // moving to the next screen.
    completeRevealIfActive() {
        if (this.revealComplete) {
            return false;
        }
        this.completeReveal();
        return true;
    },
    
    // -- Sasayaki cue support --
    // Cues are stored as plain {id, start, end} matchable-char ranges.
    // Applying a cue does no DOM work. Wrapping happens only once the
    // highlight is actually shown, and only touches the current stage.
    
    applySasayakiCues(cues) {
        this.resetSasayakiCues();
        this.sasayakiCues = (cues || []).map(c => ({ id: c.id, start: c.start, end: c.start + c.length }));
    },
    
    highlightSasayakiCue(cueId, reveal) {
        this.clearSasayakiCue();
        
        const cue = (this.sasayakiCues || []).find(c => c.id === cueId);
        if (!cue) {
            return null;
        }
        
        const currentScreen = this.screens[this.currentIndex];
        const intersectsCurrent = !!currentScreen && cue.start < currentScreen.endChar && cue.end > currentScreen.startChar;
        
        let targetIndex = this.currentIndex;
        if (!intersectsCurrent || this.mergeCrossScreenSasayakiCues) {
            const resolved = this.sourceOffsetToScreenIndex(cue.start);
            if (resolved !== null) targetIndex = resolved;
        }
        
        let jumped = false;
        if (reveal && targetIndex !== this.currentIndex) {
            this.showScreen(targetIndex);
            jumped = true;
        }
        
        const wrappers = this.wrapStageRangeAsCue(cue.start, cue.end);
        if (wrappers.length) {
            this.activeCueId = cueId;
            this.cueWrappers.set(cueId, wrappers);
        }
        
        return jumped ? this.calculateProgress() : null;
    },
    
    // Wraps whole text nodes on the current stage that fall inside
    // [start, end) in matchable-char terms. This uses whole-node size, not
    // the exact character, on purpose: the stage is thrown away and rebuilt
    // on every render. So any small mistake here is just a look on one
    // screen, never a lasting problem.
    wrapStageRangeAsCue(start, end) {
        const nodesToWrap = [];
        const walker = this.createWalker(this.stage);
        let node;
        while (node = walker.nextNode()) {
            const nodeStart = this.nodeStartOffsets.get(node) ?? 0;
            const nodeEnd = nodeStart + this.countChars(node.textContent);
            if (nodeEnd <= start || nodeStart >= end) continue;
            nodesToWrap.push(node);
        }
        
        const wrappers = [];
        for (let i = nodesToWrap.length - 1; i >= 0; i--) {
            const node = nodesToWrap[i];
            const wrapper = document.createElement('span');
            wrapper.className = 'hoshi-sasayaki-cue hoshi-sasayaki-active';
            node.parentNode.insertBefore(wrapper, node);
            wrapper.appendChild(node);
            wrappers.push(wrapper);
        }
        return wrappers.reverse();
    },
    
    clearSasayakiCue() {
        if (!this.activeCueId) {
            return;
        }
        const wrappers = this.cueWrappers.get(this.activeCueId) || [];
        this.unwrap(wrappers);
        this.cueWrappers.delete(this.activeCueId);
        this.activeCueId = null;
    },
    
    resetSasayakiCues() {
        this.cueWrappers.forEach(wrappers => this.unwrap(wrappers));
        this.cueWrappers.clear();
        this.activeCueId = null;
    }
};
