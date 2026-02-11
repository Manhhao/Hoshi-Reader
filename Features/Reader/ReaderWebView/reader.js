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
        var vertical = window.getComputedStyle(document.body).writingMode === "vertical-rl";
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
                var rect = range.getBoundingClientRect();
                if ((vertical ? rect.top : rect.left) < 0) {
                    exploredChars += nodeLen;
                }
            }
        }
        
        return totalChars > 0 ? exploredChars / totalChars : 0;
    },
    
    registerSnapScroll(initialScroll) {
        if (window.snapScrollRegistered) {
            return;
        }
        window.snapScrollRegistered = true;
        window.lastPageScroll = initialScroll;
        
        var vertical = window.getComputedStyle(document.body).writingMode === "vertical-rl";
        window.addEventListener('scroll', function() {
            if (vertical) {
                var pageHeight = window.innerHeight;
                var snappedScroll = Math.round(window.scrollY / pageHeight) * pageHeight;
                if (Math.abs(window.scrollY - snappedScroll) > 1) {
                    window.scrollTo(0, window.lastPageScroll);
                } else {
                    window.lastPageScroll = snappedScroll;
                }
            } else {
                var pageWidth = window.innerWidth;
                var snappedScroll = Math.round(window.scrollX / pageWidth) * pageWidth;
                if (Math.abs(window.scrollX - snappedScroll) > 1) {
                    window.scrollTo(window.lastPageScroll, 0);
                } else {
                    window.lastPageScroll = snappedScroll;
                }
            }
        }, { passive: true });
    },
    
    registerCopyText() {
        if (window.copyTextRegistered) {
            return;
        }
        window.copyTextRegistered = true
        document.addEventListener('copy', function(event) {
            let text = window.getSelection()?.toString();
            if (!text) {
                return;
            }
            event.preventDefault();
            event.clipboardData.setData('text/plain', text);
        }, true);
    },
    
    restoreProgress(progress) {
        var notifyComplete = () => window.webkit?.messageHandlers?.restoreCompleted?.postMessage(null);
        var vertical = window.getComputedStyle(document.body).writingMode === "vertical-rl";
        var scrollEl = document.scrollingElement || document.documentElement || document.body;
        var pageSize = vertical ? scrollEl.clientHeight : scrollEl.clientWidth;
        var totalSize = vertical ? scrollEl.scrollHeight : scrollEl.scrollWidth;
        var maxScroll = Math.max(0, totalSize - pageSize);
        
        if (pageSize <= 0) {
            this.registerSnapScroll(0);
            notifyComplete();
            return;
        }
        
        if (progress <= 0) {
            if (vertical) {
                scrollEl.scrollTop = 0;
                window.scrollTo(0, 0);
            } else {
                scrollEl.scrollLeft = 0;
                window.scrollTo(0, 0);
            }
            this.registerSnapScroll(0);
            notifyComplete();
            return;
        }
        
        if (progress >= 0.99) {
            var lastPage = Math.floor(maxScroll / pageSize) * pageSize;
            lastPage = Math.max(0, lastPage);
            if (vertical) {
                scrollEl.scrollTop = lastPage;
                window.scrollTo(0, lastPage);
            } else {
                scrollEl.scrollLeft = lastPage;
                window.scrollTo(lastPage, 0);
            }
            this.registerSnapScroll(lastPage);
            notifyComplete();
            return;
        }
        
        var walker = this.createWalker();
        var totalChars = 0;
        var node;
        
        while (node = walker.nextNode()) {
            totalChars += this.countChars(node.textContent);
        }
        
        if (totalChars <= 0) {
            this.registerSnapScroll(0);
            notifyComplete();
            return;
        }
        
        var targetCharCount = Math.ceil(totalChars * progress);
        var runningSum = 0;
        var targetNode = null;
        
        walker = this.createWalker();
        while (node = walker.nextNode()) {
            runningSum += this.countChars(node.textContent);
            if (runningSum > targetCharCount) {
                targetNode = node;
                break;
            }
        }
        
        if (targetNode) {
            var range = document.createRange();
            range.setStart(targetNode, 0);
            range.setEnd(targetNode, 1);
            var rect = range.getBoundingClientRect();
            var anchor = (vertical ? rect.top : rect.left) + (vertical ? scrollEl.scrollTop : scrollEl.scrollLeft);
            var pageIndex = Math.floor(anchor / pageSize);
            var targetScroll = Math.min(pageIndex * pageSize, maxScroll);
            
            if (vertical) {
                scrollEl.scrollTop = targetScroll;
                window.scrollTo(0, targetScroll);
            } else {
                scrollEl.scrollLeft = targetScroll;
                window.scrollTo(targetScroll, 0);
            }
            requestAnimationFrame(() => {
                if (vertical) {
                    scrollEl.scrollTop = targetScroll;
                    window.scrollTo(0, targetScroll);
                } else {
                    scrollEl.scrollLeft = targetScroll;
                    window.scrollTo(targetScroll, 0);
                }
                window.hoshiReader.registerSnapScroll(targetScroll);
            });
        } else {
            this.registerSnapScroll(0);
        }
        notifyComplete();
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
        } else {
            const element = document.elementFromPoint(x, y);
            if (!element) {
                return null;
            }
            
            const container = element.closest('p, div, span, ruby, a') || document.body;
            const walker = this.createWalker(container);
            
            const range = document.createRange();
            let node;
            while (node = walker.nextNode()) {
                for (let i = 0; i < node.textContent.length; i++) {
                    range.setStart(node, i);
                    range.setEnd(node, i + 1);
                    const rect = range.getBoundingClientRect();
                    if (rect.left <= x && x <= rect.right && rect.top <= y && y <= rect.bottom) {
                        range.collapse(true);
                        return range;
                    }
                }
            }
            return document.caretRangeFromPoint(x, y);
        }
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
        
        // Dismiss popup if tapping on the first character of the current selection
        if (this.selection &&
            hit.node === this.selection.startNode &&
            hit.offset === this.selection.startOffset) {
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
