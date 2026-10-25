// Runs UnRAR (WebAssembly) off the page. The Emscripten bindings need
// eval-like code generation, which the page's CSP forbids; a worker served
// from its own URL gets its own, empty policy.
import { createExtractorFromData } from './vendor/unrar.js'

let extractor

self.onmessage = async ({ data: { id, type, data, name } }) => {
    try {
        if (type === 'open') {
            const wasmBinary = await (await fetch('vendor/unrar.wasm')).arrayBuffer()
            extractor = await createExtractorFromData({ data, wasmBinary })
            const files = [...extractor.getFileList().fileHeaders]
                .filter(h => !h.flags.directory)
                .map(h => ({ name: h.name, size: h.unpSize }))
            self.postMessage({ id, result: files })
        } else if (type === 'extract') {
            // Drain the generator so the extractor frees its buffers.
            const [file] = [...extractor.extract({ files: [name] }).files]
            const bytes = file.extraction
            self.postMessage({ id, result: bytes.buffer }, [bytes.buffer])
        }
    } catch (e) {
        self.postMessage({ id, error: String(e?.message ?? e) })
    }
}
