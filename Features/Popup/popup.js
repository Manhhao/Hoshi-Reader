//
//  popup.js
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  Copyright © 2023-2025 Yomitan Authors (marked pitch functions)
//  Copyright © 2021-2022 Yomichan Authors (marked pitch functions)
//  SPDX-License-Identifier: GPL-3.0-or-later
//

const KANJI_RANGE = '\u4E00-\u9FFF\u3400-\u4DBF\uF900-\uFAFF';
const KANJI_PATTERN = new RegExp(`[${KANJI_RANGE}]`);
const KANJI_SEGMENT_PATTERN = new RegExp(`[${KANJI_RANGE}]+|[^${KANJI_RANGE}]+`, 'g');
const DEFAULT_HARMONIC_RANK = '9999999';
const SMALL_KANA_SET = new Set('ぁぃぅぇぉゃゅょゎァィゥェォャュョヮ');

function el(tag, props = {}, children = []) {
    const element = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
        if (key in element) {
            element[key] = value;
        } else {
            element.setAttribute(key, value);
        }
    }
    
    if (children.length) {
        element.append(...children);
    }
    
    return element;
}

function toKebabCase(str) {
    return str.replace(/([A-Z])/g, (_, c, i) => (i ? '-' : '') + c.toLowerCase());
}

function openExternalLink(url) {
    webkit.messageHandlers.openLink.postMessage(url);
}

function showDescription(element) {
    const description = element.getAttribute('data-description');
    if (!description) {
        return;
    }
    const overlay = document.querySelector('.overlay');
    document.querySelector('.overlay-content').textContent = description;
    overlay.style.display = 'block';
}

function closeOverlay() {
    document.querySelector('.overlay').style.display = 'none';
}

function segmentFurigana(expression, reading) {
    if (!reading || reading === expression) {
        return [[expression, '']];
    }

    const segments = expression.match(KANJI_SEGMENT_PATTERN) || [];
    const result = [];
    let readingPos = 0;

    for (let i = 0; i < segments.length; i++) {
        const text = segments[i];
        const isKanji = KANJI_PATTERN.test(text[0]);

        if (!isKanji) {
            const matchPos = reading.indexOf(text, readingPos);
            if (matchPos > readingPos && result.length && result.at(-1)[1] === null) {
                result.at(-1)[1] = reading.slice(readingPos, matchPos);
            }
            result.push([text, '']);
            if (matchPos !== -1) {
                readingPos = matchPos + text.length;
            }
        } else {
            const nextKana = segments.slice(i + 1).find(segment => !KANJI_PATTERN.test(segment[0]));
            const nextPos = nextKana ? reading.indexOf(nextKana, readingPos) : -1;

            if (nextPos !== -1) {
                result.push([text, reading.slice(readingPos, nextPos)]);
                readingPos = nextPos;
            } else if (!nextKana) {
                result.push([text, reading.slice(readingPos)]);
                readingPos = reading.length;
            } else {
                result.push([text, null]);
            }
        }
    }

    return result.map(([text, furi]) => [text, furi || '']);
}

function buildFuriganaEl(parent, expression, reading) {
    for (const [text, furigana] of segmentFurigana(expression, reading)) {
        if (furigana) {
            const ruby = el('ruby', {}, [text]);
            ruby.appendChild(el('rt', { textContent: furigana }));
            parent.appendChild(ruby);
        } else {
            parent.appendChild(document.createTextNode(text));
        }
    }
}

function constructFuriganaPlain(expression, reading) {
    let result = '';
    for (const [text, furigana] of segmentFurigana(expression, reading)) {
        if (furigana) {
            result += `${text}[${furigana}]`;
        } else {
            // space to separate from next furigana segment, not sure if this is the correct solution
            result += `${text} `;
        }
    }
    return result;
}

// !AI SLOP! function to preprocess css
function constructDictCss(css, dictName) {
    if (!css) {
        return '';
    }
    const prefix = `.yomitan-glossary [data-dictionary="${dictName}"]`;
    const parts = [];
    let i = 0;
    while (i < css.length) {
        while (i < css.length && /\s/.test(css[i])) {
            parts.push(css[i++]);
        }
        if (css.slice(i, i + 2) === '/*') {
            const end = css.indexOf('*/', i + 2);
            if (end === -1) break;
            parts.push(css.slice(i, end + 2));
            i = end + 2;
            continue;
        }
        const bracePos = css.indexOf('{', i);
        if (bracePos === -1) break;
        const selectorPart = css.slice(i, bracePos);
        const selectors = selectorPart.split(',').map(s => {
            const trimmed = s.trim();
            if (!trimmed) return '';
            if (trimmed.startsWith('&')) {
                return s;
            }
            return `${prefix} ${trimmed}`;
        });
        parts.push(selectors.join(', '), ' {');
        i = bracePos + 1;
        let depth = 1;
        let blockStart = i;
        while (i < css.length && depth > 0) {
            if (css[i] === '{') depth++;
            else if (css[i] === '}') depth--;
            i++;
        }
        const blockContent = css.slice(blockStart, i - 1);
        if (blockContent.includes('{')) {
            let pos = 0;
            let properties = '';
            let nestedRules = '';
            while (pos < blockContent.length) {
                while (pos < blockContent.length && /\s/.test(blockContent[pos])) {
                    pos++;
                }
                if (pos >= blockContent.length) break;
                let nextSemi = blockContent.indexOf(';', pos);
                let nextBrace = blockContent.indexOf('{', pos);
                if (nextBrace !== -1 && (nextSemi === -1 || nextBrace < nextSemi)) {
                    let nestedDepth = 1;
                    let nestedEnd = nextBrace + 1;
                    while (nestedEnd < blockContent.length && nestedDepth > 0) {
                        if (blockContent[nestedEnd] === '{') nestedDepth++;
                        else if (blockContent[nestedEnd] === '}') nestedDepth--;
                        nestedEnd++;
                    }
                    nestedRules += blockContent.slice(pos, nestedEnd);
                    pos = nestedEnd;
                } else if (nextSemi !== -1) {
                    properties += blockContent.slice(pos, nextSemi + 1);
                    pos = nextSemi + 1;
                } else {
                    properties += blockContent.slice(pos);
                    break;
                }
            }
            parts.push(properties);
            if (nestedRules) {
                parts.push(constructDictCss(nestedRules, dictName));
            }
        } else {
            parts.push(blockContent);
        }
        parts.push('}');
    }
    return parts.join('');
}

// table styles taken from a jitendex glossary
function applyTableStyles(html) {
    const tableStyle = 'table-layout:auto;border-collapse:collapse;';
    const cellStyle = 'border-style:solid;padding:0.25em;vertical-align:top;border-width:1px;border-color:currentColor;';
    const thStyle = 'font-weight:bold;' + cellStyle;

    return html
        .replace(/<table(?=[>\s])/g, `<table style="${tableStyle}"`)
        .replace(/<th(?=[>\s])/g, `<th style="${thStyle}"`)
        .replace(/<td(?=[>\s])/g, `<td style="${cellStyle}"`);
}

function glossaryLiElement(dictName, html, css) {
    const content = applyTableStyles(html);
    let result = `<li data-dictionary="${dictName}"><i>(${dictName})</i> <span>${content}</span>`;

    if (css) {
        const scopedCss = constructDictCss(css, dictName);
        const formatted = scopedCss
            .replace(/\s+/g, ' ')
            .replace(/\s*\{\s*/g, ' { ')
            .replace(/\s*\}\s*/g, ' }\n')
            .replace(/;\s*/g, '; ')
            .trim();
        result += `<style>${formatted}</style>`;
    }

    result += '</li>';
    return result;
}

// the following two should roughly match the glossary format of yomitan and keep compatibility with notetypes like lapis
// 23.01.2026: this still has some differences
// 24.01.2026: should be a bit closer now
// 25.01.2026: fixed jmdict
function constructSingleGlossaryHtml(entryIndex) {
    if (!window.lookupEntries || entryIndex >= window.lookupEntries.length) {
        return {};
    }

    const entry = window.lookupEntries[entryIndex];
    const glossaries = {};

    entry.glossaries.forEach(g => {
        const dictName = g.dictionary;
        if (glossaries[dictName]) return;
        
        const tempDiv = document.createElement('div');
        try {
            renderStructuredContent(tempDiv, JSON.parse(g.content));
        } catch {
            renderStructuredContent(tempDiv, g.content);
        }
        
        const css = window.dictionaryStyles?.[dictName] ?? '';
        glossaries[dictName] = `<div style="text-align: left;" class="yomitan-glossary"><ol>${glossaryLiElement(dictName, tempDiv.innerHTML, css)}</ol></div>`;
    });

    return glossaries;
}

function constructGlossaryHtml(entryIndex) {
    if (!window.lookupEntries || entryIndex >= window.lookupEntries.length) {
        return null;
    }

    const entry = window.lookupEntries[entryIndex];
    let glossaryItems = '';
    const styles = {};
    let lastDict = '';
    let index = 0;

    entry.glossaries.forEach(g => {
        const dictName = g.dictionary;
        
        const tempDiv = document.createElement('div');
        try {
            renderStructuredContent(tempDiv, JSON.parse(g.content));
        } catch {
            renderStructuredContent(tempDiv, g.content);
        }
        
        index++;
        let label = '';
        if (dictName !== lastDict) {
            index = 1;
            lastDict = dictName;
            label = `<i>(${index}, ${dictName})</i> `
        }
        else {
            label = `<i>(${index})</i> `
        }
        
        glossaryItems += `<li data-dictionary="${dictName}">${label}<span>${applyTableStyles(tempDiv.innerHTML)}</span></li>`;
        
        const css = window.dictionaryStyles?.[dictName];
        if (css && !styles[dictName]) {
            styles[dictName] = css;
        }
    });

    let result = '<div style="text-align: left;" class="yomitan-glossary"><ol>';
    result += glossaryItems;
    result += '</ol>';
    
    for (const [dictName, css] of Object.entries(styles)) {
        const scopedCss = constructDictCss(css, dictName);
        const formatted = scopedCss
            .replace(/\s+/g, ' ')
            .replace(/\s*\{\s*/g, ' { ')
            .replace(/\s*\}\s*/g, ' }\n')
            .replace(/;\s*/g, '; ')
            .trim();
        result += `<style>${formatted}</style>`;
    }
    
    result += '</div>';
    return result;
}

function constructFrequencyHtml(frequencies) {
    if (!frequencies || frequencies.length === 0) {
        return '';
    }

    let result = '<ul style="text-align: left;">';
    frequencies.forEach(freqGroup => {
        if (!freqGroup?.frequencies?.length) {
            return;
        }
        const dictName = freqGroup.dictionary || '';
        freqGroup.frequencies.forEach(freq => {
            result += `<li>${dictName}: ${freq.displayValue || freq.value}</li>`;
        });
    });
    result += '</ul>';
    return result;
}

function constructPitchPositionHtml(pitches) {
    if (!pitches?.length) {
        return '';
    }
    
    let result = '<ol>';
    pitches.forEach(pitchGroup => {
        pitchGroup.pitchPositions.forEach(pos => {
            result += `<li><span style="display:inline;"><span>[</span><span>${pos}</span><span>]</span></span></li>`;
        });
    });
    result += '</ol>';
    return result;
}

function constructPitchCategories(pitches, reading, definitionTags) {
    if (!pitches?.length) {
        return '';
    }
    
    const verbOrAdj = isVerbOrAdjective(definitionTags);
    const categories = [];
    pitches.forEach(pitchGroup => {
        pitchGroup.pitchPositions.forEach(pos => {
            const category = getPitchCategory(reading, pos, verbOrAdj);
            if (category && !categories.includes(category)) {
                categories.push(category);
            }
        });
    });
    return categories.join(',');
}

function getFrequencyHarmonicRank(frequencies) {
    if (!frequencies || frequencies.length === 0) {
        return DEFAULT_HARMONIC_RANK;
    }

    const values = [];
    frequencies.forEach(freqGroup => {
        freqGroup.frequencies?.forEach(freq => {
            const val = freq.value;
            if (val && val > 0) {
                values.push(val);
            }
        });
    });

    if (values.length === 0) {
        return DEFAULT_HARMONIC_RANK;
    }

    const sumOfReciprocals = values.reduce((sum, val) => sum + (1 / val), 0);
    return String(Math.round(values.length / sumOfReciprocals));
}

function mineEntry(expression, reading, frequencies, pitches, definitionTags, matched, entryIndex) {
    const idx = entryIndex || 0;
    const furiganaPlain = constructFuriganaPlain(expression, reading);
    const glossary = constructGlossaryHtml(idx);
    const freqHarmonicRank = getFrequencyHarmonicRank(frequencies);
    const frequenciesHtml = constructFrequencyHtml(frequencies);
    const singleGlossaries = constructSingleGlossaryHtml(idx);
    const glossaryFirst = Object.values(singleGlossaries)[0] || '';
    const pitchPositions = constructPitchPositionHtml(pitches);
    const pitchCategories = constructPitchCategories(pitches, reading, definitionTags);
    webkit.messageHandlers.mineEntry.postMessage({
        expression,
        reading,
        matched,
        furiganaPlain,
        frequenciesHtml,
        freqHarmonicRank,
        glossary,
        glossaryFirst,
        pitchPositions,
        pitchCategories
    });
}

function renderStructuredContent(parent, node) {
    if (typeof node === 'string') {
        node.split(/\r?\n/).forEach((line, i) => {
            if (i > 0) {
                parent.appendChild(document.createElement('br'));
            }
            if (line) {
                parent.appendChild(document.createTextNode(line));
            }
        });
        return;
    }

    if (Array.isArray(node)) {
        const isStringArray = node.every(item => typeof item === 'string');
        const insideSpan = parent.tagName === 'SPAN';
        if (isStringArray && node.length > 1 && !insideSpan) {
            const ul = document.createElement('ul');
            node.forEach(child => {
                const li = document.createElement('li');
                li.appendChild(document.createTextNode(child));
                ul.appendChild(li);
            });
            parent.appendChild(ul);
            return;
        }
        
        node.forEach(child => renderStructuredContent(parent, child));
        return;
    }

    if (!node || typeof node !== 'object') {
        return;
    }

    if (node.type === 'structured-content') {
        renderStructuredContent(parent, node.content);
        return;
    }

    const element = document.createElement(node.tag || 'span');

    if (node.href) {
        element.setAttribute('href', node.href);
        const isExternal = /^https?:\/\//i.test(node.href);
        element.onclick = (e) => {
            e.preventDefault();
            if (isExternal) {
                openExternalLink(node.href);
            } else {
                // TODO: handle redirect to other entry
            }
        };
    }

    if (node.title) {
        element.setAttribute('title', node.title);
    }

    if (node.lang) {
        element.setAttribute('lang', node.lang);
    }

    if (node.data) {
        // this is necessary to fix formatting in dicts like daijijsen
        for (const [k, v] of Object.entries(node.data)) {
            const isCJK = /^[\u3000-\u9FFF\uF900-\uFAFF]/.test(k);
            element.setAttribute(`data-sc${isCJK ? '' : '-'}${toKebabCase(k)}`, v);
        }
    }

    if (node.style) {
        Object.assign(element.style, node.style);
    }

    if (node.content) {
        renderStructuredContent(element, node.content);
    }

    parent.appendChild(element);
}

function createDeinflectionTag(tag) {
    return el('span', {
        className: 'deinflection-tag',
        textContent: tag.name,
        'data-description': tag.description,
        onclick() {
            showDescription(this);
        }
    });
}

function createFrequencyGroup(freqGroup) {
    const values = freqGroup.frequencies.map(f => f.displayValue || f.value).join(', ');
    return el('span', { className: 'frequency-group' }, [
        el('span', { className: 'frequency-dict-label', textContent: freqGroup.dictionary }),
        el('span', { className: 'frequency-values', textContent: values })
    ]);
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L350
function isMoraPitchHigh(moraIndex, pitchAccentValue) {
    switch (pitchAccentValue) {
        case 0: return (moraIndex > 0);
        case 1: return (moraIndex < 1);
        default: return (moraIndex > 0 && moraIndex < pitchAccentValue);
    }
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L406
function getKanaMorae(text) {
    const morae = [];
    let i;
    for (const c of text) {
        if (SMALL_KANA_SET.has(c) && (i = morae.length) > 0) {
            morae[i - 1] += c;
        } else {
            morae.push(c);
        }
    }
    return morae;
}

// this might be unreliable
function isVerbOrAdjective(definitionTags) {
    return definitionTags?.some(tag => tag.startsWith('v') || tag.startsWith('adj-i')) ?? false;
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/language/ja/japanese.js#L366
function getPitchCategory(reading, pitchAccentValue, verbOrAdjective = false) {
    if (pitchAccentValue === 0) {
        return 'heiban';
    }
    if (verbOrAdjective) {
        return pitchAccentValue > 0 ? 'kifuku' : null;
    }
    if (pitchAccentValue === 1) {
        return 'atamadaka';
    }
    if (pitchAccentValue > 1) {
        const moraCount = getKanaMorae(reading).length;
        return pitchAccentValue >= moraCount ? 'odaka' : 'nakadaka';
    }
    return null;
}

// https://github.com/yomidevs/yomitan/blob/c24d4c9b39ceec1b5fd133df774c41972e9ebbdc/ext/js/display/pronunciation-generator.js#L38
function createPitchHtml(reading, pitchValue) {
    const morae = getKanaMorae(reading);
    const container = el('span', { className: 'pronunciation-text' });

    for (let i = 0; i < morae.length; i++) {
        const mora = morae[i];
        const isHigh = isMoraPitchHigh(i, pitchValue);
        const isHighNext = isMoraPitchHigh(i + 1, pitchValue);

        const moraSpan = el('span', {
            className: 'pronunciation-mora',
            'data-pitch': isHigh ? 'high' : 'low',
            'data-pitch-next': isHighNext ? 'high' : 'low',
            textContent: mora
        });

        moraSpan.appendChild(el('span', { className: 'pronunciation-mora-line' }));
        container.appendChild(moraSpan);
    }

    return container;
}

function createPitchGroup(pitchData, reading) {
    const container = el('div', { className: 'pitch-group' });
    container.appendChild(el('span', { className: 'pitch-dict-label', textContent: pitchData.dictionary }));

    const list = el('ul', { className: 'pitch-entries' });
    pitchData.pitchPositions.forEach((pitch) => {
        const li = el('li');
        li.appendChild(createPitchHtml(reading, pitch));
        li.appendChild(document.createTextNode(` [${pitch}]`));
        list.appendChild(li);
    });
    container.appendChild(list);

    return container;
}

function createTags(entry) {
    const { deinflectionTrace, frequencies, pitches, reading } = entry;
    const hasDeinflection = deinflectionTrace?.length;
    const hasFrequencies = frequencies?.length;
    const hasPitches = pitches?.length;

    if (!hasDeinflection && !hasFrequencies && !hasPitches) {
        return null;
    }

    const container = el('div', { className: 'entry-tags' });

    if (hasDeinflection) {
        const deinflectionDiv = el('div', { className: 'tag-row' });
        deinflectionTrace.forEach(tag => deinflectionDiv.appendChild(createDeinflectionTag(tag)));
        container.appendChild(deinflectionDiv);
    }

    if (hasFrequencies) {
        const freqContainer = el('div', { className: 'tag-row' });
        frequencies.forEach(freq => freqContainer.appendChild(createFrequencyGroup(freq)));
        container.appendChild(freqContainer);
    }

    if (hasPitches) {
        const pitchContainer = el('div', { className: 'pitch-list' });
        pitches.forEach(pitch => pitchContainer.appendChild(createPitchGroup(pitch, reading)));
        container.appendChild(pitchContainer);
    }

    return container;
}

function createEntryHeader(entry, idx) {
    const { expression, reading, matched, frequencies, pitches, definitionTags } = entry;
    const header = el('div', { className: 'entry-header' });

    const expressionSpan = el('span', { className: 'expression' });
    if (reading && reading !== expression) {
        buildFuriganaEl(expressionSpan, expression, reading);
    } else {
        expressionSpan.textContent = expression;
    }
    header.appendChild(expressionSpan);

    header.appendChild(el('button', {
        className: 'mine-button',
        textContent: '+',
        onclick: () => mineEntry(expression, reading, frequencies, pitches, definitionTags, matched, idx)
    }));

    return header;
}

function createGlossarySection(dictName, contents, isFirst) {
    const details = el('details', { className: 'glossary-group' });
    if (!window.collapseDictionaries || isFirst) {
        details.open = true;
    }

    details.appendChild(el('summary', { className: 'dict-label', textContent: dictName }));

    const shadowHost = document.createElement('div');
    const shadow = shadowHost.attachShadow({ mode: 'open' });

    const dictStyle = window.dictionaryStyles?.[dictName] ?? '';
    shadow.appendChild(el('style', {
        textContent: `
            :host {
                display: block;
                font-size: 14px;
                line-height: 1.4;
                padding: 0px 0;
            }
            ul, ol {
                padding-left: 1.2em;
                margin: 2px 0; 
            }
            li { 
                margin: 1px 0;
            }
            table {
                table-layout: auto;
                border-collapse: collapse;
            }
            th, td {
                border: 1px solid currentColor;
                padding: 0.25em;
                vertical-align: top;
            }
            th {
                font-weight: bold;
            }
            @media (prefers-color-scheme: light) { :host { color: #000; } }
            @media (prefers-color-scheme: dark) { :host { color: #fff; } }
            ${dictStyle}
        `.trim()
    }));
    
    if (contents.length > 1) {
        const ol = document.createElement('ol');
        contents.forEach(content => {
            const li = document.createElement('li');
            try {
                renderStructuredContent(li, JSON.parse(content));
            } catch {
                renderStructuredContent(li, content);
            }
            ol.appendChild(li);
        });
        shadow.appendChild(ol);
    } else {
        contents.forEach(content => {
            const wrapper = document.createElement('div');
            try {
                renderStructuredContent(wrapper, JSON.parse(content));
            } catch {
                renderStructuredContent(wrapper, content);
            }
            shadow.appendChild(wrapper);
        });
    }

    details.appendChild(shadowHost);
    return details;
}

document.addEventListener('DOMContentLoaded', () => {
    const container = document.getElementById('entries-container');
    if (!window.lookupEntries) {
        return;
    }

    window.lookupEntries.forEach((entry, idx) => {
        if (idx > 0) {
            container.appendChild(document.createElement('hr'));
        }

        const entryDiv = el('div', { className: 'entry' });
        entryDiv.appendChild(createEntryHeader(entry, idx));

        const tags = createTags(entry);
        if (tags) {
            entryDiv.appendChild(tags);
        }

        const grouped = {};
        entry.glossaries.forEach(g => {
            (grouped[g.dictionary] ??= []).push(g.content);
        });

        Object.keys(grouped).forEach((dictName, dictIdx) => {
            entryDiv.appendChild(createGlossarySection(dictName, grouped[dictName], dictIdx === 0));
        });

        container.appendChild(entryDiv);
    });
});
