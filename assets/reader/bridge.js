// Connects foliate-js to the Flutter app. Dart calls the window.reader
// functions; this script reports back through flutter_inappwebview handlers.
import './foliate/view.js'
import { makeExtraBook } from './formats.js'
import { Overlayer } from './foliate/overlayer.js'

const send = (name, data) =>
    window.flutter_inappwebview?.callHandler(name, data)

const themes = {
    light: { bg: '#ffffff', fg: '#1b1b1b', link: '#1a5fb4' },
    sepia: { bg: '#f4ecd8', fg: '#433422', link: '#7b4a12' },
    dark: { bg: '#121212', fg: '#e3e3e3', link: '#8ab4f8' },
}

let view = null

// Highlights, keyed by CFI. Re-drawn whenever a section's overlay is created.
const highlightColors = {
    yellow: '#f9d71c', green: '#5fd068', blue: '#4aa8ff', pink: '#ff6fae',
}
const annotations = new Map()
let speaking = false
let selectionTimer
let style = { theme: 'light', fontSize: 100, lineHeight: 1.5 }

const css = () => {
    const t = themes[style.theme] ?? themes.light
    return `
    html { color-scheme: ${style.theme === 'dark' ? 'dark' : 'light'}; }
    html, body { background: ${t.bg} !important; color: ${t.fg} !important;
        font-size: ${style.fontSize}% !important; }
    a:link, a:visited { color: ${t.link} !important; }
    p, li, blockquote, dd { line-height: ${style.lineHeight}; hyphens: auto; widows: 2; }
    pre { white-space: pre-wrap !important; }`
}

const escapeHTML = s => s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c])

// Plain text as a foliate book: split into ~64 KB sections at blank lines.
const makeTextBook = (text, title) => {
    const chunks = []
    let current = ''
    for (const para of text.replace(/\r\n?/g, '\n').split(/\n{2,}/)) {
        current += `<p>${escapeHTML(para).replace(/\n/g, '<br>')}</p>\n`
        if (current.length > 65536) { chunks.push(current); current = '' }
    }
    if (current || !chunks.length) chunks.push(current)
    const urls = []
    const html = body => `<!doctype html><html><head><meta charset="utf-8"></head><body>${body}</body></html>`
    return {
        metadata: { title },
        dir: 'ltr',
        toc: [],
        sections: chunks.map((body, i) => ({
            id: i,
            size: body.length,
            load: () => urls[i] ??= URL.createObjectURL(new Blob([html(body)], { type: 'text/html' })),
            unload: () => { if (urls[i]) URL.revokeObjectURL(urls[i]); urls[i] = undefined },
            createDocument: () => new DOMParser().parseFromString(html(body), 'text/html'),
        })),
        splitTOCHref: href => [Number(href), null],
        getTOCFragment: doc => doc.body,
        resolveHref: href => ({ index: Number(href), anchor: doc => doc.body }),
    }
}

// Picks the loader by file extension; archives call back in for the book inside.
const makeBook = async (blob, name) => {
    if (/\.txt$/i.test(name)) return makeTextBook(await blob.text(), name.replace(/\.txt$/i, ''))
    return await makeExtraBook(blob, name, makeBook) ?? new File([blob], name)
}

const flattenToc = (items, depth = 0, out = []) => {
    for (const item of items ?? []) {
        out.push({ label: (item.label ?? '').trim(), href: item.href ?? '', depth })
        flattenToc(item.subitems, depth + 1, out)
    }
    return out
}

const titleOf = metadata => {
    const t = metadata?.title
    return typeof t === 'string' ? t : Object.values(t ?? {})[0] ?? ''
}

const languageOf = metadata => {
    const lang = [metadata?.language ?? []].flat()[0]
    return typeof lang === 'string' ? lang : ''
}

const authorOf = metadata => {
    const names = [metadata?.author ?? []].flat()
        .map(a => typeof a === 'string' ? a : a?.name)
        .map(n => typeof n === 'string' ? n : Object.values(n ?? {})[0])
        .filter(Boolean)
    return names.join(', ')
}

// The book's own cover, scaled down to a JPEG for the library.
const sendCover = async () => {
    const blob = await view.book.getCover?.()
    if (!blob) return
    const bitmap = await createImageBitmap(blob)
    const scale = Math.min(1, 900 / bitmap.height)
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.round(bitmap.width * scale))
    canvas.height = Math.max(1, Math.round(bitmap.height * scale))
    canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    const url = canvas.toDataURL('image/jpeg', 0.85)
    send('cover', url.slice(url.indexOf(',') + 1))
}

// Left/right thirds turn pages, the middle toggles the app's controls.
const handleTap = e => {
    if (e.target.closest?.('a[href]')) return
    const doc = e.target.ownerDocument ?? document
    if (doc.getSelection()?.toString()) return
    // Clicks inside a section iframe are relative to that frame, which
    // fixed-layout pages also scale with a CSS transform.
    const frame = doc.defaultView?.frameElement
    const rect = frame?.getBoundingClientRect()
    const scale = rect ? rect.width / doc.defaultView.innerWidth : 1
    const x = (rect?.left ?? 0) + e.clientX * scale
    const width = window.innerWidth
    if (x < width / 3) view.goLeft()
    else if (x > width * 2 / 3) view.goRight()
    else send('toggleControls')
}

// Reports a finished text selection (or its clearing) to the app, which
// shows the highlight and note actions.
const onSelection = (doc, index) => {
    clearTimeout(selectionTimer)
    selectionTimer = setTimeout(() => {
        if (speaking) return
        const sel = doc.getSelection()
        const text = sel?.toString().trim()
        if (!sel || sel.rangeCount === 0 || !text) return send('selection', null)
        const range = sel.getRangeAt(0)
        send('selection', { cfi: view.getCFI(index, range), text })
    }, 500)
}

const SSML_NS = 'http://www.w3.org/2001/10/synthesis'

// Splits foliate's SSML into [{ mark, text }] so the app can speak each
// sentence and ask us to highlight it.
const toSegments = ssml => {
    if (!ssml) return null
    const doc = new DOMParser().parseFromString(ssml, 'application/xml')
    const segments = []
    let current = { mark: null, text: '' }
    const walk = node => {
        for (const child of node.childNodes) {
            if (child.nodeType === Node.TEXT_NODE) current.text += child.textContent
            else if (child.localName === 'mark' && child.namespaceURI === SSML_NS) {
                if (current.text.trim()) segments.push(current)
                current = { mark: child.getAttribute('name'), text: '' }
            } else walk(child)
        }
    }
    walk(doc.documentElement)
    if (current.text.trim()) segments.push(current)
    for (const seg of segments) seg.text = seg.text.replace(/\s+/g, ' ').trim()
    return segments
}

const highlightSpoken = range => {
    view.renderer.scrollToAnchor(range, true)
}

const initTTS = () => view.initTTS('sentence', highlightSpoken)

window.reader = {
    async open({ url, name, lastLocation, columns, theme, fontSize, annotations: annotations_ }) {
        try {
            style = { ...style, theme: theme ?? style.theme, fontSize: fontSize ?? style.fontSize }
            document.documentElement.style.setProperty('--bg', themes[style.theme].bg)
            const blob = await (await fetch(url)).blob()
            const book = await makeBook(blob, name)
            view = document.createElement('foliate-view')
            document.body.append(view)
            await view.open(book)
            view.renderer.setAttribute('max-column-count', String(columns ?? 1))
            view.renderer.setAttribute('margin', '48px')
            view.renderer.setAttribute('gap', '6%')
            view.renderer.setStyles?.(css())
            view.addEventListener('load', ({ detail: { doc, index } }) => {
                doc.addEventListener('click', handleTap)
                doc.addEventListener('keydown', handleKey)
                doc.addEventListener('selectionchange', () => onSelection(doc, index))
            })
            view.addEventListener('create-overlay', () => {
                for (const [cfi, color] of annotations) view.addAnnotation({ value: cfi, color })
            })
            view.addEventListener('draw-annotation', ({ detail: { draw, annotation } }) =>
                draw(Overlayer.highlight, { color: highlightColors[annotation.color] ?? annotation.color }))
            view.addEventListener('show-annotation', ({ detail: { value } }) =>
                send('annotationTapped', { cfi: value }))
            for (const a of annotations_ ?? []) annotations.set(a.cfi, a.color)
            view.addEventListener('relocate', ({ detail }) => detail.fraction != null && send('relocate', {
                cfi: detail.cfi ?? '',
                fraction: detail.fraction ?? 0,
                chapter: detail.tocItem?.label ?? '',
            }))
            await view.init({ lastLocation: lastLocation || null, showTextStart: !lastLocation })
            send('opened', {
                title: titleOf(view.book.metadata),
                author: authorOf(view.book.metadata),
                language: languageOf(view.book.metadata),
                toc: flattenToc(view.book.toc),
                fixedLayout: !!view.isFixedLayout,
            })
            sendCover().catch(() => {})
        } catch (e) {
            send('error', String(e?.message ?? e))
        }
    },
    next: () => view?.goRight(),
    prev: () => view?.goLeft(),
    goTo: target => view?.goTo(target),
    goToFraction: f => view?.goToFraction(f),
    addAnnotation({ cfi, color }) {
        annotations.set(cfi, color)
        view?.addAnnotation({ value: cfi, color })
        view?.renderer.getContents().forEach(({ doc }) => doc.getSelection()?.removeAllRanges())
    },
    removeAnnotation(cfi) {
        annotations.delete(cfi)
        view?.deleteAnnotation({ value: cfi })
    },
    clearSelection: () => view?.renderer.getContents().forEach(({ doc }) => doc.getSelection()?.removeAllRanges()),
    // Text-to-speech: each call returns the next block as [{ mark, text }],
    // or null at the end of the book.
    async ttsStart() {
        speaking = true
        await initTTS()
        const range = view.lastLocation?.range
        return toSegments(range ? view.tts.from(range) : view.tts.start())
    },
    async ttsNext() {
        let ssml = view.tts?.next()
        while (!ssml) {
            const before = view.renderer.getContents()[0]?.index
            await view.renderer.nextSection()
            if (view.renderer.getContents()[0]?.index === before) return null
            await initTTS()
            ssml = view.tts.start()
        }
        return toSegments(ssml)
    },
    ttsMark: mark => view?.tts?.setMark(mark),
    ttsStop() {
        speaking = false
        view?.renderer.getContents().forEach(({ doc }) => doc.getSelection()?.removeAllRanges())
    },
    setColumns: n => view?.renderer.setAttribute('max-column-count', String(n)),
    setStyle(next) {
        style = { ...style, ...next }
        document.documentElement.style.setProperty('--bg', themes[style.theme].bg)
        view?.renderer.setStyles?.(css())
    },
}

const handleKey = e => {
    if (e.key === 'ArrowLeft' || e.key === 'PageUp') view?.goLeft()
    else if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') view?.goRight()
}
document.addEventListener('keydown', handleKey)
document.addEventListener('click', e => view && handleTap(e))

