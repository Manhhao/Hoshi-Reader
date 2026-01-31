//
//  reader.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

window.hoshiReader = {
    selection: null,
    scanDelimiters: '。、！？…‥「」『』（）()【】〈〉《》〔〕｛｝{}［］[]・：；:;，,.─\n\r',
    sentenceDelimiters: '。！？.!?\n\r',
    ttuRegex: /[^0-9A-Z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚｦ-ﾝ\p{Radical}\p{Unified_Ideograph}]+/gimu,
    
    isVertical() {
        return window.getComputedStyle(document.body).writingMode === "vertical-rl";
    },
    
    isScanBoundary(char) {
        return /^[\s\u3000]$/.test(char) || this.scanDelimiters.includes(char);
    },
    
    isFurigana(node) {
        const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        return !!el?.closest('rt, rp');
    },
    
    findParagraph(node) {
        let el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        return el?.closest('p') || null;
    },
    
    countChars(text) {
        return text.replace(this.ttuRegex, '').length;
    },
    
    createWalker(rootNode) {
        const root = rootNode || document.body;
        
        return document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => this.isFurigana(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
        });
    },
    
    calculateProgress() {
        var walker = this.createWalker();
        var totalChars = 0;
        var exploredChars = 0;
        var node;
        
        while (node = walker.nextNode()) {
            var nodeLen = this.countChars(node.textContent);
            totalChars += nodeLen;
            
            if (nodeLen > 0) {
                var range = document.createRange();
                range.selectNodeContents(node);
                var anchor = this.isVertical() ? range.getBoundingClientRect().top : range.getBoundingClientRect().left;
                if (anchor < 0) {
                    exploredChars += nodeLen;
                }
            }
        }
        
        return totalChars > 0 ? exploredChars / totalChars : 0;
    },
    
    restoreProgress(progress) {
        if (progress <= 0) {
            return;
        }
        
        var vertical = this.isVertical();
        if (progress >= 0.99) {
            if (vertical) {
                var lastPage = Math.floor((document.body.scrollHeight - window.innerHeight) / window.innerHeight) * window.innerHeight;
                window.scrollTo(0, lastPage);
            } else {
                var lastPage = Math.floor((document.body.scrollWidth - window.innerWidth) / window.innerWidth) * window.innerWidth;
                window.scrollTo(lastPage, 0);
            }
            return;
        }
        
        var walker = this.createWalker();
        var totalChars = 0;
        var node;
        
        while (node = walker.nextNode()) {
            totalChars += this.countChars(node.textContent);
        }
        
        if (totalChars <= 0) {
            return;
        }
        
        // i tbh don't know why this works anymore, the logic was broken with custom fonts but gemini produced something that worked
        var targetCharCount = totalChars * progress;
        var runningSum = 0;
        var targetNode = null;
        var charsBeforeNode = 0;
        
        walker = this.createWalker();
        while (node = walker.nextNode()) {
            var nodeChars = this.countChars(node.textContent);
            if (runningSum + nodeChars > targetCharCount) {
                targetNode = node;
                charsBeforeNode = runningSum;
                break;
            }
            runningSum += nodeChars;
        }
        
        if (targetNode) {
            var nodeChars = this.countChars(targetNode.textContent);
            var charsIntoNode = targetCharCount - charsBeforeNode;
            var charRatio = nodeChars > 0 ? charsIntoNode / nodeChars : 0;
            
            var range = document.createRange();
            range.selectNodeContents(targetNode);
            var rect = range.getBoundingClientRect();
            
            var targetY = rect.top + (rect.height * charRatio);
            
            if (vertical) {
                var pageIndex = Math.max(0, Math.floor(targetY / window.innerHeight));
                var maxScroll = Math.max(0, document.body.scrollHeight - window.innerHeight);
                var scrollY = Math.min(pageIndex * window.innerHeight, maxScroll);
                window.scrollTo(0, scrollY);
            } else {
                var targetX = rect.left + (rect.width * charRatio);
                var pageIndex = Math.max(0, Math.floor(targetX / window.innerWidth));
                var maxScroll = Math.max(0, document.body.scrollWidth - window.innerWidth);
                var scrollX = Math.min(pageIndex * window.innerWidth, maxScroll);
                window.scrollTo(scrollX, 0);
            }
        }
    },
    
    getSentence(startNode, startOffset) {
        const container = this.findParagraph(startNode) || document.body;
        const walker = this.createWalker(container);
        
        walker.currentNode = startNode;
        const partsBefore = [];
        let node = startNode;
        let limit = startOffset;
        
        while (node) {
            const text = node.textContent;
            let foundStart = false;
            for (let i = limit - 1; i >= 0; i--) {
                if (this.sentenceDelimiters.includes(text[i])) {
                    partsBefore.push(text.slice(i + 1, limit));
                    foundStart = true;
                    break;
                }
            }
            
            if (foundStart) {
                break;
            }
            
            partsBefore.push(text.slice(0, limit));
            node = walker.previousNode();
            if (node) limit = node.textContent.length;
        }
        
        walker.currentNode = startNode;
        const partsAfter = [];
        node = startNode;
        let start = startOffset;
        
        while (node) {
            const text = node.textContent;
            let foundEnd = false;
            
            for (let i = start; i < text.length; i++) {
                if (this.sentenceDelimiters.includes(text[i])) {
                    partsAfter.push(text.slice(start, i + 1));
                    foundEnd = true;
                    break;
                }
            }
            
            if (foundEnd) {
                break;
            }
            
            partsAfter.push(text.slice(start));
            
            node = walker.nextNode();
            start = 0;
        }
        
        return (partsBefore.reverse().join('') + partsAfter.join('')).trim();
    },
    
    getCaretRange(x, y) {
        if (document.caretPositionFromPoint) {
            const pos = document.caretPositionFromPoint(x, y);
            if (!pos) {
                return null;
            }
            
            const range = document.createRange();
            range.setStart(pos.offsetNode, pos.offset);
            range.collapse(true);
            return range;
        }
        else if (document.caretRangeFromPoint) {
            const range = document.caretRangeFromPoint(x, y);
            return range;
        }
        return null;
    },
    
    getCharacterAtPoint(x, y) {
        const range = this.getCaretRange(x, y);
        if (!range) {
            return null;
        }
        
        const node = range.startContainer;
        if (node.nodeType !== Node.TEXT_NODE) {
            return null;
        }
        
        if (this.isFurigana(node)) {
            return null;
        }
        
        const text = node.textContent;
        const caret = range.startOffset;
        
        for (const offset of [caret, caret - 1, caret + 1]) {
            if (offset < 0 || offset >= text.length) {
                continue;
            }
            
            const charRange = document.createRange();
            charRange.setStart(node, offset);
            charRange.setEnd(node, offset + 1);
            const rect = charRange.getBoundingClientRect();
            
            const inside = x >= rect.left && x <= rect.right
            && y >= rect.top && y <= rect.bottom;
            
            if (inside) {
                if (this.isScanBoundary(text[offset])) {
                    return null;
                }
                return { node, offset };
            }
        }
        
        return null;
    },
    
    selectText(x, y, maxLength) {
        const hit = this.getCharacterAtPoint(x, y);
        
        if (!hit) {
            this.clearHighlight();
            return null;
        }
        
        this.clearHighlight();
        
        const container = this.findParagraph(hit.node) || document.body;
        const walker = this.createWalker(container);
        
        let text = '';
        let node = hit.node;
        let offset = hit.offset;
        let ranges = [];
        
        walker.currentNode = node;
        while (text.length < maxLength && node) {
            const content = node.textContent;
            const start = offset;
            
            while (offset < content.length && text.length < maxLength) {
                const char = content[offset];
                if (this.isScanBoundary(char)) {
                    break;
                }
                text += char;
                offset++;
            }
            
            if (offset > start) {
                ranges.push({ node, start, end: offset });
            }
            
            if (offset < content.length || text.length >= maxLength) {
                break;
            }
            
            node = walker.nextNode();
            offset = 0;
        }
        
        if (!text) {
            return null;
        }
        
        this.selection = {
            startNode: hit.node,
            startOffset: hit.offset,
            ranges,
            text
        };
        
        const sentence = this.getSentence(hit.node, hit.offset);
        webkit.messageHandlers.textSelected.postMessage({
            text,
            sentence,
            rect: this.getSelectionRect()
        });
        
        return text;
    },
    
    getSelectionRect() {
        if (!this.selection?.ranges.length) {
            return null;
        }
        
        const first = this.selection.ranges[0];
        const range = document.createRange();
        range.setStart(first.node, first.start);
        range.setEnd(first.node, first.start + 1);
        
        const rect = range.getBoundingClientRect();
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    },
    
    highlightSelection(charCount) {
        if (!this.selection?.ranges.length) {
            return;
        }
        
        const highlights = [];
        let remaining = charCount;
        
        for (const r of this.selection.ranges) {
            if (remaining <= 0) {
                break;
            }
            
            const length = r.end - r.start;
            const end = remaining >= length ? r.end : r.start + remaining;
            
            const range = document.createRange();
            range.setStart(r.node, r.start);
            range.setEnd(r.node, end);
            highlights.push(range);
            
            remaining -= length;
        }
        
        CSS.highlights?.set('hoshi-selection', new Highlight(...highlights));
    },
    
    clearHighlight() {
        window.getSelection()?.removeAllRanges();
        CSS.highlights?.clear();
        this.selection = null;
    }
};
