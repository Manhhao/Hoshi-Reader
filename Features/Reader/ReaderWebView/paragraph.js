//
//  paragraph.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

window.hoshiParagraph = {
    animationFrame: null,
    
    layoutParagraphs() {
        const paragraphs = [...document.querySelectorAll('p')].filter(p => p.textContent.trim() || p.querySelector('img, svg'));
        paragraphs.forEach(p => p.classList.add('hoshi-paragraph'));
        
        const reader = window.hoshiReader;
        const vertical = reader.isVertical();
        const style = window.getComputedStyle(document.body);
        const available = vertical
        ? parseFloat(style.columnWidth)
        : document.body.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
        const offsets = paragraphs.map(p => {
            const rect = p.getBoundingClientRect();
            return (available - (vertical ? rect.width : rect.height)) / 2;
        });
        paragraphs.forEach((p, i) => {
            if (offsets[i] > 0) {
                p.style.setProperty('padding-block-start', `${offsets[i]}px`, 'important');
            }
        });
    },
    
    isOnPage(rect) {
        const reader = window.hoshiReader;
        const position = reader.isVertical() ? reader.pageWidth - rect.right : rect.left;
        return position >= 0 && position < reader.pageWidth;
    },
    
    pageSasayakiCues() {
        const reader = window.hoshiReader;
        const ids = [];
        reader.cueWrappers.forEach((wrappers, id) => {
            if (this.isOnPage(reader.getRect(wrappers[0]))) {
                ids.push(id);
            }
        });
        return ids;
    },
    
    animateText(speed) {
        this.finishTextAnimation();
        const reader = window.hoshiReader;
        const walker = reader.createWalker();
        const range = document.createRange();
        const chars = [];
        let last = null;
        let node;
        
        while (node = walker.nextNode()) {
            if (!node.textContent.trim()) {
                continue;
            }
            range.selectNodeContents(node);
            if (!this.isOnPage(reader.getRect(range))) {
                continue;
            }
            let offset = 0;
            for (const char of node.textContent) {
                chars.push({ node, offset });
                offset += char.length;
            }
            last = node;
        }
        
        if (chars.length < 2) {
            return;
        }
        
        const hidden = document.createRange();
        hidden.setStart(chars[1].node, chars[1].offset);
        hidden.setEnd(last, last.length);
        CSS.highlights.set('hoshi-animation', new Highlight(hidden));
        
        const startTime = performance.now();
        const tick = (now) => {
            const count = Math.floor((now - startTime) * speed / 1000) + 1;
            if (count >= chars.length) {
                this.finishTextAnimation();
                return;
            }
            hidden.setStart(chars[count].node, chars[count].offset);
            this.animationFrame = requestAnimationFrame(tick);
        };
        this.animationFrame = requestAnimationFrame(tick);
    },
    
    finishTextAnimation() {
        if (!this.animationFrame) {
            return false;
        }
        cancelAnimationFrame(this.animationFrame);
        this.animationFrame = null;
        CSS.highlights.delete('hoshi-animation');
        return true;
    }
};
