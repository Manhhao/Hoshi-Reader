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
        
        var vertical = this.isVertical();
        window.addEventListener('scroll', function () {
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
        document.addEventListener('copy', function (event) {
            let text = window.getSelection()?.toString();
            if (!text) {
                return;
            }
            event.preventDefault();
            event.clipboardData.setData('text/plain', text);
        }, true);
    },
    
    paginate(direction) {
        var vertical = this.isVertical();
        var pageSize = vertical ? window.innerHeight : window.innerWidth;
        if (pageSize <= 0) return "limit";
        
        if (direction === "forward") {
            var totalSize = vertical ? document.body.scrollHeight : document.body.scrollWidth;
            var maxScroll = Math.max(0, totalSize - pageSize);
            var maxAlignedScroll = Math.floor(maxScroll / pageSize) * pageSize;
            var currentScroll = vertical ? window.scrollY : window.scrollX;
            if ((currentScroll + pageSize) <= (maxAlignedScroll + 1)) {
                if (vertical) { window.scrollBy(0, pageSize); } else { window.scrollBy(pageSize, 0); }
                return "scrolled";
            }
            return "limit";
        } else {
            var currentScroll = vertical ? window.scrollY : window.scrollX;
            if (currentScroll > 0) {
                if (vertical) { window.scrollBy(0, -pageSize); } else { window.scrollBy(-pageSize, 0); }
                return "scrolled";
            }
            return "limit";
        }
    },
    
    restoreProgress(progress) {
        var notifyComplete = () => window.webkit?.messageHandlers?.restoreCompleted?.postMessage(null);
        var vertical = this.isVertical();
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
};
