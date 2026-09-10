//
//  highlights.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

window.hoshiHighlights = {
    wrappers: new Map(),
    
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
        
        const fragment = range.cloneContents();
        fragment.querySelectorAll('rt, rp').forEach(el => el.remove());
        const text = fragment.textContent;
        
        selection.removeAllRanges();
        
        this.wrapHighlight({ id, color, offset: rawStart, text });
        window.hoshiReader.buildNodeOffsets();
        
        requestAnimationFrame(() => {
            document.body.style.transform = 'translateZ(0)';
            requestAnimationFrame(() => {
                document.body.style.transform = '';
            });
        });
        
        return { start, offset: rawStart, text };
    },
    
    collectSegments(offset, length) {
        const end = offset + length;
        const segments = [];
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
        // Initialize the cursor from the first walked node's own registered raw
        // offset instead of assuming the walk always starts at chapter offset 0.
        // For reader.js/scrollreader.js (which always walk the whole chapter) the
        // first node's offset is 0, so this is a no-op there. For VN mode, which
        // only ever has the current screen's content attached under document.body,
        // the first node's offset is that screen's actual chapter-relative start,
        // so highlight offsets (stored in whole-chapter terms) still line up
        // correctly against a walk that only covers a fragment of the chapter.
        let cursor = null;
        while ((cursor === null || cursor < end) && (node = walker.nextNode())) {
            if (cursor === null) {
                cursor = window.hoshiReader.nodeStartRawOffsets.get(node) ?? 0;
                if (cursor >= end) {
                    break;
                }
            }
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
        const segments = this.collectSegments(offset, Array.from(text).length);
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
        this.wrappers.set(id, wrappers);
    },
    
    applyHighlights(highlights) {
        for (const h of highlights) {
            this.wrapHighlight(h);
        }
        window.hoshiReader.buildNodeOffsets();
    },
    
    removeHighlight(id) {
        const wrappers = this.wrappers.get(id);
        if (!wrappers) {
            return;
        }
        
        window.hoshiReader.unwrap(wrappers);
        this.wrappers.delete(id);
        window.hoshiReader.buildNodeOffsets();
        
        requestAnimationFrame(() => {
            document.body.style.transform = 'translateZ(0)';
            requestAnimationFrame(() => {
                document.body.style.transform = '';
            });
        });
    }
};
