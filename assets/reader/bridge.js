// Connects foliate-js to the Flutter app. Dart calls the window.reader
// functions; this script reports back through flutter_inappwebview handlers.
import './foliate/view.js'
import { makeExtraBook } from './formats.js'

const send = (name, data) =>
    window.flutter_inappwebview?.callHandler(name, data)

const themes = {
    light: { bg: '#ffffff', fg: '#1b1b1b', link: '#1a5fb4' },
    sepia: { bg: '#f4ecd8', fg: '#433422', link: '#7b4a12' },
    dark: { bg: '#121212', fg: '#e3e3e3', link: '#8ab4f8' },
}

let view = null
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

window.reader = {
    async open({ url, name, format, lastLocation, columns, theme, fontSize }) {
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
            view.addEventListener('load', ({ detail: { doc } }) => {
                doc.addEventListener('click', handleTap)
                doc.addEventListener('keydown', handleKey)
            })
            view.addEventListener('relocate', ({ detail }) => detail.fraction != null && send('relocate', {
                cfi: detail.cfi ?? '',
                fraction: detail.fraction ?? 0,
                chapter: detail.tocItem?.label ?? '',
            }))
            await view.init({ lastLocation: lastLocation || null, showTextStart: !lastLocation })
            send('opened', {
                title: titleOf(view.book.metadata) || name,
                toc: flattenToc(view.book.toc),
                fixedLayout: !!view.isFixedLayout,
            })
        } catch (e) {
            send('error', String(e?.message ?? e))
        }
    },
    next: () => view?.goRight(),
    prev: () => view?.goLeft(),
    goTo: target => view?.goTo(target),
    goToFraction: f => view?.goToFraction(f),
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

