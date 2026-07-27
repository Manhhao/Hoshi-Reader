//
//  reader.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

window.hoshiReader = {
    ttuRegexNegated: /[^0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\p{Radical}\p{Unified_Ideograph}]+/gimu,
    ttuRegex: /[0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\p{Radical}\p{Unified_Ideograph}]/iu,
    activeCueId: null,
    cueWrappers: new Map(),
    nodeStartOffsets: new WeakMap(),
    nodeStartRawOffsets: new WeakMap(),
    
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
    
    createWalker(rootNode) {
        const root = rootNode || document.body;
        
        return document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => this.isFurigana(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
        });
    },
    
    getRect(target) {
        const rect = target.getClientRects()[0];
        return rect || target.getBoundingClientRect();
    },
    
    async awaitFonts() {
        const style = window.getComputedStyle(document.body);
        try {
            await document.fonts.load(`${style.fontSize} ${style.fontFamily}`, 'あ');
        } catch {}
        await document.fonts.ready;
    },
    
    splitPoints(paragraph, pageSize, currentScroll, vertical) {
        const rect = paragraph.getBoundingClientRect();
        const start = (vertical ? rect.top : rect.left) + currentScroll;
        const first = Math.floor(start / pageSize);
        const last = Math.floor((start + (vertical ? rect.height : rect.width) - 1) / pageSize);
        const points = [];
        if (last === first) {
            return points;
        }
        
        const walker = this.createWalker(paragraph);
        const positions = [];
        let node;
        
        while (node = walker.nextNode()) {
            for (let i = 0; i < node.textContent.length; i++) {
                positions.push({ node, offset: i });
            }
        }
        
        const range = document.createRange();
        for (let column = first + 1; column <= last; column++) {
            const limit = column * pageSize;
            let low = 0;
            let high = positions.length - 1;
            let hit = -1;
            
            while (low <= high) {
                const mid = (low + high) >> 1;
                range.setStart(positions[mid].node, positions[mid].offset);
                range.setEnd(positions[mid].node, positions[mid].offset + 1);
                const charRect = range.getClientRects()[0];
                if (charRect && (vertical ? charRect.top : charRect.left) + currentScroll >= limit) {
                    hit = mid;
                    high = mid - 1;
                } else {
                    low = mid + 1;
                }
            }
            
            if (hit > 0) {
                points.push(positions[hit]);
            }
        }
        
        return points;
    },
    
    fragmentBlocks() {
        const vertical = this.isVertical();
        const pageSize = vertical ? this.pageHeight : this.pageWidth;
        const currentScroll = vertical ? document.body.scrollTop : document.body.scrollLeft;
        const targets = [];
        
        for (const paragraph of document.body.querySelectorAll('p')) {
            const points = this.splitPoints(paragraph, pageSize, currentScroll, vertical);
            if (points.length) {
                const justified = window.getComputedStyle(paragraph).textAlign === 'justify';
                targets.push({ paragraph, points, justified });
            }
        }
        
        const range = document.createRange();
        for (const { paragraph, points, justified } of targets) {
            const firstFragment = document.createElement('span');
            firstFragment.className = 'hoshi-fragment';
            while (paragraph.firstChild) {
                firstFragment.appendChild(paragraph.firstChild);
            }
            paragraph.appendChild(firstFragment);
            
            const fragments = [firstFragment];
            for (let i = points.length - 1; i >= 0; i--) {
                range.setStart(points[i].node, points[i].offset);
                range.setEnd(firstFragment, firstFragment.childNodes.length);
                
                const fragment = document.createElement('span');
                fragment.className = 'hoshi-fragment';
                fragment.appendChild(range.extractContents());
                firstFragment.after(fragment);
                fragments.splice(1, 0, fragment);
            }
            
            if (justified) {
                fragments.slice(0, -1).forEach(f => f.style.setProperty('text-align-last', 'justify', 'important'));
            }
        }
    },
    
    buildNodeOffsets() {
        const offsets = new WeakMap();
        const rawOffsets = new WeakMap();
        const walker = this.createWalker();
        let count = 0;
        let rawCount = 0;
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
    
    calculateProgress() {
        var vertical = this.isVertical();
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
                var rect = this.getRect(range);
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
        
        var vertical = this.isVertical();
        var pageHeight = this.pageHeight;
        var pageWidth = this.pageWidth;
        document.body.addEventListener('scroll', function () {
            if (vertical) {
                var currentScroll = document.body.scrollTop;
                var snappedScroll = Math.round(currentScroll / pageHeight) * pageHeight;
                if (Math.abs(currentScroll - snappedScroll) > 1) {
                    document.body.scrollTop = window.lastPageScroll;
                } else {
                    window.lastPageScroll = snappedScroll;
                }
            } else {
                var currentScroll = document.body.scrollLeft;
                var snappedScroll = Math.round(currentScroll / pageWidth) * pageWidth;
                if (Math.abs(currentScroll - snappedScroll) > 1) {
                    document.body.scrollLeft = window.lastPageScroll;
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
    
    getScrollContext() {
        var vertical = this.isVertical();
        var scrollEl = document.body;
        var pageSize = vertical ? this.pageHeight : this.pageWidth;
        var totalSize = vertical ? scrollEl.scrollHeight : scrollEl.scrollWidth;
        var maxScroll = Math.max(0, totalSize - pageSize);
        return { vertical, scrollEl, pageSize, maxScroll };
    },
    
    setScrollOffset(context, scroll) {
        var clampedScroll = Math.min(Math.max(0, scroll), context.maxScroll);
        if (context.vertical) {
            context.scrollEl.scrollTop = clampedScroll;
        } else {
            context.scrollEl.scrollLeft = clampedScroll;
        }
        return clampedScroll;
    },
    
    alignToPage(context, anchor) {
        if (context.pageSize <= 0) {
            return 0;
        }
        var pageIndex = Math.floor(Math.max(0, anchor) / context.pageSize);
        return Math.min(Math.max(0, pageIndex * context.pageSize), context.maxScroll);
    },
    
    paginate(direction) {
        var vertical = this.isVertical();
        var pageSize = vertical ? this.pageHeight : this.pageWidth;
        if (pageSize <= 0) return "limit";
        
        if (direction === "forward") {
            var totalSize = vertical ? document.body.scrollHeight : document.body.scrollWidth;
            var maxScroll = Math.max(0, totalSize - pageSize);
            var maxAlignedScroll = Math.floor(maxScroll / pageSize) * pageSize;
            var currentScroll = vertical ? document.body.scrollTop : document.body.scrollLeft;
            if ((currentScroll + pageSize) <= (maxAlignedScroll + 1)) {
                var targetScroll = Math.round((currentScroll + pageSize) / pageSize) * pageSize;
                window.lastPageScroll = targetScroll;
                if (vertical) { document.body.scrollTop = targetScroll; } else { document.body.scrollLeft = targetScroll; }
                return "scrolled";
            }
            return "limit";
        } else {
            var currentScroll = vertical ? document.body.scrollTop : document.body.scrollLeft;
            if (currentScroll > 0) {
                var targetScroll = Math.round((currentScroll - pageSize) / pageSize) * pageSize;
                window.lastPageScroll = targetScroll;
                if (vertical) { document.body.scrollTop = targetScroll; } else { document.body.scrollLeft = targetScroll; }
                return "scrolled";
            }
            return "limit";
        }
    },
    
    scrollToRange(range) {
        const context = this.getScrollContext();
        if (context.pageSize <= 0) {
            return false;
        }
        
        const rect = this.getRect(range);
        const currentScroll = context.vertical ? context.scrollEl.scrollTop : context.scrollEl.scrollLeft;
        const anchor = (context.vertical ? (rect.top + rect.bottom) / 2 : (rect.left + rect.right) / 2) + currentScroll;
        const targetScroll = this.alignToPage(context, anchor);
        
        if (targetScroll === currentScroll) {
            return false;
        }
        
        window.lastPageScroll = targetScroll;
        this.setScrollOffset(context, targetScroll);
        requestAnimationFrame(() => {
            this.setScrollOffset(context, targetScroll);
        });
        
        return true;
    },
    
    collectSasayakiCueRanges(cues) {
        const cueRanges = new Map();
        if (!cues.length) {
            return [];
        }
        
        let index = 0;
        let current = cues[0];
        let start = current.start;
        let end = start + current.length;
        let cursor = 0;
        let segment = null;
        
        const flushSegment = (node) => {
            if (!segment) {
                return;
            }
            
            const ranges = cueRanges.get(segment.id) || [];
            ranges.push({ node, start: segment.start, end: segment.end });
            cueRanges.set(segment.id, ranges);
            segment = null;
        };
        
        const advanceCue = () => {
            index += 1;
            current = cues[index];
            if (current) {
                start = current.start;
                end = start + current.length;
            }
        };
        
        let node;
        const walker = this.createWalker();
        while (current && (node = walker.nextNode())) {
            const text = node.textContent;
            let i = 0;
            while (i < text.length && current) {
                const char = String.fromCodePoint(text.codePointAt(i));
                const next = i + char.length;
                if (this.isMatchableChar(char)) {
                    if (cursor >= start && cursor < end) {
                        if (!segment) {
                            segment = { id: current.id, start: i, end: next };
                        } else {
                            segment.end = next;
                        }
                    } else {
                        flushSegment(node);
                    }
                    cursor += 1;
                    if (cursor === end) {
                        flushSegment(node);
                        advanceCue();
                    }
                } else if (segment) {
                    segment.end = next;
                } else if (cursor > start && cursor < end) {
                    segment = { id: current.id, start: i, end: next };
                }
                i = next;
            }
            flushSegment(node);
        }
        
        return cues.map(cue => ({
            id: cue.id,
            ranges: cueRanges.get(cue.id) || []
        }));
    },
    
    applySasayakiCues(cues) {
        this.resetSasayakiCues();
        
        const cueRanges = this.collectSasayakiCueRanges(cues);
        const range = document.createRange();
        for (let i = cueRanges.length - 1; i >= 0; i--) {
            const { id, ranges } = cueRanges[i];
            if (!ranges.length) {
                continue;
            }
            
            const wrappers = [];
            for (let j = ranges.length - 1; j >= 0; j--) {
                const segment = ranges[j];
                range.setStart(segment.node, segment.start);
                range.setEnd(segment.node, segment.end);
                
                const wrapper = document.createElement('span');
                wrapper.className = 'hoshi-sasayaki-cue';
                wrapper.appendChild(range.extractContents());
                range.insertNode(wrapper);
                
                wrappers.push(wrapper);
            }
            wrappers.reverse();
            this.cueWrappers.set(id, wrappers);
        }
        
        this.buildNodeOffsets();
    },
    
    highlightSasayakiCue(cueId, reveal) {
        this.clearSasayakiCue();
        
        const wrappers = this.cueWrappers.get(cueId);
        if (!wrappers?.length) {
            return null;
        }
        
        this.activeCueId = cueId;
        wrappers.forEach(wrapper => wrapper.classList.add('hoshi-sasayaki-active'));
        
        if (reveal) {
            const range = document.createRange();
            range.selectNodeContents(wrappers[0]);
            if (this.scrollToRange(range)) {
                return this.calculateProgress();
            }
        }
        
        return null;
    },
    
    clearSasayakiCue() {
        if (!this.activeCueId) {
            return;
        }
        
        const wrappers = this.cueWrappers.get(this.activeCueId) || [];
        wrappers.forEach(wrapper => wrapper.classList.remove('hoshi-sasayaki-active'));
        this.activeCueId = null;
    },
    
    scrollToSasayakiImage(index) {
        const el = document.querySelectorAll('img, image')[index];
        if (!el || !(el.classList.contains('block-img') || el.namespaceURI === 'http://www.w3.org/2000/svg')) {
            return null;
        }
        
        const range = document.createRange();
        range.selectNode(el);
        const scrolled = this.scrollToRange(range);
        return { progress: scrolled ? this.calculateProgress() : null };
    },
    
    resetSasayakiCues() {
        this.cueWrappers.forEach(wrappers => this.unwrap(wrappers));
        this.cueWrappers.clear();
        this.activeCueId = null;
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
    
    async restoreProgress(progress) {
        await this.awaitFonts();
        var context = this.getScrollContext();
        
        if (context.pageSize <= 0) {
            this.registerSnapScroll(0);
            this.notifyRestoreComplete();
            return;
        }
        
        if (progress <= 0) {
            this.setScrollOffset(context, 0);
            this.registerSnapScroll(0);
            this.notifyRestoreComplete();
            return;
        }
        
        if (progress >= 0.99) {
            var lastPage = Math.floor(context.maxScroll / context.pageSize) * context.pageSize;
            lastPage = Math.max(0, lastPage);
            this.setScrollOffset(context, lastPage);
            requestAnimationFrame(() => {
                this.setScrollOffset(context, lastPage);
                this.registerSnapScroll(lastPage);
                requestAnimationFrame(() => this.notifyRestoreComplete());
            });
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
            this.notifyRestoreComplete();
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
            var rect = this.getRect(range);
            var anchor = (context.vertical ? rect.top : rect.left) + (context.vertical ? context.scrollEl.scrollTop : context.scrollEl.scrollLeft);
            var targetScroll = this.alignToPage(context, anchor);
            
            this.setScrollOffset(context, targetScroll);
            requestAnimationFrame(() => {
                this.setScrollOffset(context, targetScroll);
                this.registerSnapScroll(targetScroll);
            });
        } else {
            this.registerSnapScroll(0);
        }
        
        requestAnimationFrame(() => {
            requestAnimationFrame(() => this.notifyRestoreComplete());
        });
    },
    
    async jumpToFragment(fragment) {
        await this.awaitFonts();
        var context = this.getScrollContext();
        var rawFragment = (fragment || '').trim();
        var target = rawFragment && (document.getElementById(rawFragment) || document.getElementsByName(rawFragment)[0]);
        
        if (context.pageSize <= 0 || !target) {
            this.registerSnapScroll(0);
            this.notifyRestoreComplete();
            return false;
        }
        
        var rect = this.getRect(target);
        var currentScroll = context.vertical ? context.scrollEl.scrollTop : context.scrollEl.scrollLeft;
        var anchor = (context.vertical ? rect.top : rect.left) + currentScroll;
        var targetScroll = this.alignToPage(context, anchor);
        
        this.setScrollOffset(context, targetScroll);
        
        requestAnimationFrame(() => {
            this.setScrollOffset(context, targetScroll);
            this.registerSnapScroll(targetScroll);
            requestAnimationFrame(() => this.notifyRestoreComplete());
        });
        
        return true;
    }
};
