// Book loaders for formats foliate-js does not open on its own: RAR/CBR,
// generic ZIP, and DjVu. Archives either hold one book (opened as that
// book) or a set of page images (opened as a comic).
import { makeComicBook } from './foliate/comic-book.js'

const IMAGE = /\.(jpe?g|png|gif|bmp|webp|avif|jxl)$/i
const BOOK = /\.(epub|mobi|prc|azw3?|kf8|fb2|txt|djvu?)$/i

// comic-book.js only matches lowercase extensions, so expose names with the
// extension lowercased and map them back to the archive's own names.
const withLowerExt = name => name.replace(/\.[^./]+$/, ext => ext.toLowerCase())

const makeLoader = (names, load, size) => {
    const original = new Map(names.map(n => [withLowerExt(n), n]))
    return {
        entries: [...original.keys()].map(filename => ({ filename })),
        loadBlob: name => load(original.get(name) ?? name),
        getSize: name => size(original.get(name) ?? name),
    }
}

const zipLoader = async blob => {
    const { configure, ZipReader, BlobReader, BlobWriter } = await import('./foliate/vendor/zip.js')
    configure({ useWebWorkers: false })
    const entries = (await new ZipReader(new BlobReader(blob)).getEntries())
        .filter(e => !e.directory)
    const map = new Map(entries.map(e => [e.filename, e]))
    return makeLoader(entries.map(e => e.filename),
        name => map.get(name).getData(new BlobWriter()),
        name => map.get(name)?.uncompressedSize ?? 0)
}

const rarLoader = async blob => {
    const worker = new Worker('rar-worker.js', { type: 'module' })
    let next = 0
    const pending = new Map()
    worker.onmessage = ({ data: { id, result, error } }) => {
        const { resolve, reject } = pending.get(id)
        pending.delete(id)
        error ? reject(new Error(error)) : resolve(result)
    }
    const call = (message, transfer) => new Promise((resolve, reject) => {
        const id = next++
        pending.set(id, { resolve, reject })
        worker.postMessage({ ...message, id }, transfer ?? [])
    })
    const data = await blob.arrayBuffer()
    const files = await call({ type: 'open', data }, [data])
    const sizes = new Map(files.map(f => [f.name, f.size]))
    return makeLoader(files.map(f => f.name),
        async name => new Blob([await call({ type: 'extract', name })]),
        name => sizes.get(name) ?? 0)
}

let djvuReady
const loadDjVu = () => djvuReady ??= new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'vendor/djvu.js'
    script.onload = () => resolve(window.DjVu)
    script.onerror = () => reject(new Error('Could not load the DjVu library'))
    document.head.append(script)
})

const djvuLoader = async blob => {
    const DjVu = await loadDjVu()
    const doc = new DjVu.Document(await blob.arrayBuffer())
    const count = doc.getPagesQuantity()
    const names = Array.from({ length: count }, (_, i) => `page-${String(i + 1).padStart(5, '0')}.png`)
    const sizes = doc.getPagesSizes()
    const render = async name => {
        const page = await doc.getPage(names.indexOf(name) + 1)
        const image = page.getImageData()
        const canvas = document.createElement('canvas')
        canvas.width = image.width
        canvas.height = image.height
        canvas.getContext('2d').putImageData(image, 0, 0)
        return new Promise(resolve => canvas.toBlob(resolve, 'image/png'))
    }
    return makeLoader(names, render,
        name => { const s = sizes[names.indexOf(name)]; return s ? s.width * s.height : 0 })
}

const extOf = name => (name.match(/\.([^.]+)$/)?.[1] ?? '').toLowerCase()

const fromArchive = async (loader, name, open) => {
    const names = loader.entries.map(e => e.filename)
    const books = names.filter(n => BOOK.test(n))
        .sort((a, b) => loader.getSize(b) - loader.getSize(a))
    const images = names.filter(n => IMAGE.test(n))
    if (books.length && (books.length === 1 || !images.length)) {
        const inner = books[0].split('/').pop()
        return open(await loader.loadBlob(books[0]), inner)
    }
    if (images.length) return makeComicBook(loader, { name })
    throw new Error('This archive has no book or page images the reader can open.')
}

/** Returns a foliate book for formats that need our own loader, or null. */
export const makeExtraBook = async (blob, name, open) => {
    switch (extOf(name)) {
        case 'cbr': case 'rar':
            return fromArchive(await rarLoader(blob), name, open)
        case 'cbz': case 'zip':
            return fromArchive(await zipLoader(blob), name, open)
        case 'djvu': case 'djv': {
            const book = makeComicBook(await djvuLoader(blob), { name })
            book.metadata = { title: name.replace(/\.djvu?$/i, '') }
            book.toc = []
            return book
        }
        default:
            return null
    }
}
