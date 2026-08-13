//
//  highlights.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

window.hoshiHighlights = {
    highlights: new Map(),
    
    createHighlight(color, id) {
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        
        const startPrefix = range.startContainer.textContent.substring(0, range.startOffset);
        const endPrefix = range.endContainer.textContent.substring(0, range.endOffset);
        
        const start = window.hoshiReader.nodeStartOffsets.get(range.startContainer) + window.hoshiReader.countChars(startPrefix);
        const rawStart = window.hoshiReader.nodeStartRawOffsets.get(range.startContainer) + window.hoshiReader.countRawChars(startPrefix);
        const rawEnd = window.hoshiReader.nodeStartRawOffsets.get(range.endContainer) + window.hoshiReader.countRawChars(endPrefix);
        if (rawEnd <= rawStart) {
            return null;
        }
        
        const existing = this.findHighlight(rawStart, rawEnd - rawStart);
        if (existing) {
            selection.removeAllRanges();
            return this.updateHighlight(existing, color);
        }
        
        const fragment = range.cloneContents();
        fragment.querySelectorAll('rt, rp').forEach(el => el.remove());
        const text = fragment.textContent;
        
        const textFurigana = this.collectSegments(rawStart, Array.from(text).length).map(segment => {
            const t = segment.node.textContent.slice(segment.start, segment.end);
            let rt = segment.node.parentElement.nextElementSibling;
            while (rt?.matches('rp')) {
                rt = rt.nextElementSibling;
            }
            return rt?.matches('rt') && rt.textContent ? `${t}(${rt.textContent})` : t;
        }).join('');
        
        selection.removeAllRanges();
        
        this.wrapHighlight({ id, color, offset: rawStart, text });
        window.hoshiReader.buildNodeOffsets();
        
        requestAnimationFrame(() => {
            document.body.style.transform = 'translateZ(0)';
            requestAnimationFrame(() => {
                document.body.style.transform = '';
            });
        });
        
        return { start, offset: rawStart, text, textFurigana: textFurigana !== text ? textFurigana : null };
    },
    
    findHighlight(offset, length) {
        for (const [id, entry] of this.highlights) {
            if (entry.offset === offset && entry.length === length) {
                return id;
            }
        }
        return null;
    },
    
    updateHighlight(id, color) {
        const entry = this.highlights.get(id);
        if (entry.color === color) {
            this.removeHighlight(id);
        } else {
            entry.color = color;
            entry.wrappers.forEach(wrapper => {
                wrapper.className = `hoshi-highlight hoshi-highlight-${color}`;
            });
        }
        return { id };
    },
    
    collectSegments(offset, length) {
        const end = offset + length;
        const segments = [];
        let cursor = 0;
        let segment = null;
        
        const flushSegment = () => {
            if (!segment) {
                return;
            }
            
            segments.push(segment);
            segment = null;
        };
        
        let node;
        const walker = window.hoshiReader.createWalker();
        while (cursor < end && (node = walker.nextNode())) {
            const text = node.textContent;
            let i = 0;
            while (i < text.length && cursor < end) {
                const char = String.fromCodePoint(text.codePointAt(i));
                const next = i + char.length;
                
                if (cursor >= offset) {
                    if (!segment || segment.node !== node) {
                        flushSegment();
                        segment = { node, start: i, end: next };
                    } else {
                        segment.end = next;
                    }
                }
                cursor += 1;
                i = next;
            }
            flushSegment();
        }
        
        return segments;
    },
    
    wrapHighlight(highlight) {
        const { id, color, offset, text } = highlight;
        const length = window.hoshiReader.countRawChars(text);
        const segments = this.collectSegments(offset, length);
        if (!segments.length) {
            return;
        }
        
        const range = document.createRange();
        const wrappers = [];
        for (let i = segments.length - 1; i >= 0; i--) {
            const s = segments[i];
            range.setStart(s.node, s.start);
            range.setEnd(s.node, s.end);
            
            const wrapper = document.createElement('span');
            wrapper.className = `hoshi-highlight hoshi-highlight-${color}`;
            wrapper.appendChild(range.extractContents());
            range.insertNode(wrapper);
            
            wrappers.push(wrapper);
        }
        wrappers.reverse();
        this.highlights.set(id, { color, offset, length, wrappers });
    },
    
    applyHighlights(highlights) {
        for (const h of highlights) {
            this.wrapHighlight(h);
        }
        window.hoshiReader.buildNodeOffsets();
    },
    
    removeHighlight(id) {
        const entry = this.highlights.get(id);
        if (!entry) {
            return;
        }
        
        window.hoshiReader.unwrap(entry.wrappers);
        this.highlights.delete(id);
        window.hoshiReader.buildNodeOffsets();
        
        requestAnimationFrame(() => {
            document.body.style.transform = 'translateZ(0)';
            requestAnimationFrame(() => {
                document.body.style.transform = '';
            });
        });
    }
};
